import SwiftUI

struct LiveRoomsView: View {
    var universe: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rooms: [LiveRoom] = []
    @State private var cursor: String?
    @State private var query = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("SALAS")).font(MVFont.display(28, width: 122))
                Text(L10n.text("Uma conversa para cada obra do catálogo.")).font(MVFont.body(14, weight: 500))
                TextField(L10n.text("Buscar obra"), text: $query).padding(12).comicCard(shadow: MV.Shadow.s)
                if let error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if busy { ProgressView() }
                if rooms.isEmpty && !busy && error == nil { CommunityEmptyMessage(text: L10n.text("Nenhuma sala encontrada para esta busca.")) }
                ForEach(rooms) { room in
                    if let item = store.item(room.itemID) {
                        Button { store.push(.liveRoom(item.id)) } label: {
                            HStack(spacing: 12) {
                                PosterView(item: item, universe: store.universe(of: item), width: 46, height: 69, titleSize: 8)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.title).font(MVFont.section(16))
                                    Text(L10n.format("%1$@ pessoas na sala", String(room.online))).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                                }; Spacer(); Image(systemName: "chevron.right")
                            }.foregroundStyle(MV.C.ink).padding(14).comicCard()
                        }.buttonStyle(.plain)
                    }
                }
                if cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await load(more: true) } }.disabled(busy) }
            }.padding(MV.pad)
        }.task(id: query) {
            do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await load() } catch { }
        }.refreshable { await load() }
    }
    private func load(more: Bool = false) async {
        guard let api = store.spacesAPI else { return }; let requestedQuery = query; busy = true; error = nil
        defer { if requestedQuery == query { busy = false } }
        do {
            let page = try await api.fetchRooms(query: requestedQuery, universe: universe, after: more ? cursor : nil)
            try Task.checkCancellation(); guard requestedQuery == query else { return }
            let previous = more ? rooms : []; rooms = previous + page.rooms.filter { next in !previous.contains { $0.id == next.id } }; cursor = page.nextCursor
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
}
private struct RoomBottomPosition: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct LiveRoomView: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var voice = VoiceSession()
    @State private var showingVoice = false
    @State private var timeline = RoomTimeline()
    @State private var presence: RoomVisit?
    @State private var progress = 0.0
    @State private var segment = 0
    @State private var draft = ""
    @State private var spoiler = false
    @State private var pending: (id: String, input: PostInput)?
    @State private var sending = false
    @State private var savingProgress = false
    @State private var error: String?
    @State private var mentioning = false
    @State private var composing = false
    @State private var editingProgress = false
    @State private var following = true
    @State private var scrollRequest = 0
    @State private var reconnecting = false
    private var locked: Bool { (presence?.progress ?? 0) < segment * 50 }
    private let bottomID = "room-bottom"

    var body: some View {
        VStack(spacing: 0) {
            BackButtonBar(action: { dismiss() })
            roomHeader
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if let error { AuthErrorBanner(message: error) }
                            if let error = timeline.error { AuthErrorBanner(message: error) }
                            if locked {
                                CommunityEmptyMessage(text: L10n.text("Este trecho contém spoilers. Atualize seu progresso para participar."))
                                Button(L10n.text("AJUSTAR PROGRESSO")) { progress = Double(presence?.progress ?? 0); editingProgress = true }
                            } else {
                                if timeline.cursor != nil {
                                    Button(L10n.text("MENSAGENS ANTERIORES")) {
                                        let anchor = timeline.posts.first?.id
                                        following = false
                                        Task {
                                            await load(more: true)
                                            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                        }
                                    }.font(MVFont.label(11)).frame(minHeight: 44).disabled(timeline.busy)
                                }
                                if timeline.busy && timeline.posts.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                                if timeline.posts.isEmpty && !timeline.busy && timeline.error == nil {
                                    CommunityEmptyMessage(text: L10n.text("A sala está quieta. Comece a conversa."))
                                }
                                ForEach(timeline.posts) { post in
                                    CommunityPostCard(post: post, user: timeline.users[post.user]).id(post.id)
                                }
                            }
                            Color.clear.frame(height: 1).id(bottomID)
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: RoomBottomPosition.self, value: geometry.frame(in: .named("room-messages")).maxY)
                                })
                        }.padding(MV.pad)
                    }
                    .coordinateSpace(name: "room-messages")
                    .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(RoomBottomPosition.self) { y in
                        following = y >= 0 && y <= viewport.size.height + 40
                    }
                    .onChange(of: scrollRequest) { _, _ in proxy.scrollTo(bottomID, anchor: .bottom) }
                    .onChange(of: viewport.size.height) { _, _ in
                        if following { proxy.scrollTo(bottomID, anchor: .bottom) }
                    }
                    .refreshable { await load() }
                }
            }
        }
        .foregroundStyle(MV.C.ink).background(MV.C.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !locked && (timeline.hasNewMessages || !following) {
                    Button {
                        timeline.showBuffered(); following = true; scrollRequest += 1
                        Task { await load(forceFollow: true) }
                    } label: {
                        Label(timeline.hasNewMessages ? L10n.text("NOVAS MENSAGENS") : L10n.text("VER MENSAGENS RECENTES"), systemImage: "arrow.down")
                            .font(MVFont.label(11)).padding(12)
                            .comicCard(bg: MV.C.card, radius: MV.R.md, shadow: MV.Shadow.s)
                    }.buttonStyle(.plain).padding(.bottom, 10)
                }
                if !locked { composer }
            }.background(MV.C.paper)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await watchRoom()
        }
        .onDisappear { Task { await voice.leave() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { Task { await voice.leave() } } }
        .sheet(isPresented: $showingVoice) {
            VoiceRoomSheet(voice: voice, api: store.communityAPI as? any VoiceAPI, item: itemID, title: store.item(itemID)?.title ?? "", segment: segment)
        }
        .task(id: segment) {
            await voice.leave()
            timeline.reset(); following = true
            await load(forceFollow: true)
        }
        .onChange(of: locked) { _, isLocked in
            timeline.reset()
            if isLocked { Task { await voice.leave() } }
            if !isLocked { Task { await load(forceFollow: true) } }
        }
        .sheet(isPresented: $editingProgress) { progressSheet }
        .sheet(isPresented: $mentioning) { MentionPicker { user in draft += (draft.isEmpty || draft.hasSuffix(" ") ? "" : " ") + user.handle + " " } }
        .sheet(isPresented: $composing, onDismiss: { Task { await load(forceFollow: true) } }) {
            if let item = store.item(itemID) { PostComposer(universe: item.uni, item: itemID, segment: segment, kind: "room") }
        }
    }
    private var roomHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = store.item(itemID) {
                HStack(spacing: 12) {
                    PosterView(item: item, universe: store.universe(of: item), width: 34, height: 51, titleSize: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(MVFont.section(17)).lineLimit(2)
                        Text(reconnecting ? L10n.text("Reconectando à sala…") : L10n.format("%1$@ pessoas na sala", String(presence?.online ?? 0)))
                            .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                    }
                    Spacer(minLength: 0)
                    Button { progress = Double(presence?.progress ?? 0); editingProgress = true } label: {
                        VStack(spacing: 4) {
                            Text(verbatim: "\(presence?.progress ?? 0)%").font(MVFont.bold(15))
                            Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                        }.padding(10).comicCard(radius: MV.R.md, shadow: MV.Shadow.s)
                    }.buttonStyle(.plain).accessibilityLabel(L10n.text("AJUSTAR PROGRESSO"))
                        .accessibilityValue(L10n.format("Meu progresso: %1$@%%", String(presence?.progress ?? 0)))
                }
            }
            HStack {
                Button { showingVoice = true } label: {
                    Label(voice.active ? L10n.text("NA VOZ") : L10n.text("VOZ"), systemImage: voice.active ? "waveform" : "headphones")
                        .font(MVFont.label(11)).padding(.horizontal, 12).frame(minHeight: 44)
                        .comicCard(bg: voice.active ? MV.C.desk : MV.C.card, radius: MV.R.md, shadow: MV.Shadow.s)
                }.buttonStyle(.plain).disabled(locked)
                if voice.active {
                    Text(voice.muted ? L10n.text("Microfone desligado") : L10n.text("Microfone ligado"))
                        .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                }
                Spacer(minLength: 0)
            }
            Picker(L10n.text("Trecho da conversa"), selection: $segment) {
                Text(L10n.text("Geral")).tag(0); Text(L10n.text("Até a metade")).tag(1); Text(L10n.text("Final")).tag(2)
            }.pickerStyle(.segmented).disabled(sending || pending != nil)
        }.padding(.horizontal, MV.pad).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(MV.C.divider).frame(height: 1) }
    }
    private var progressSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.text("MEU PROGRESSO")).font(MVFont.section(22))
            Text(L10n.format("Meu progresso: %1$@%%", String(Int(progress)))).font(MVFont.bold(17))
            Slider(value: $progress, in: 0...100, step: 10).tint(MV.C.ink)
                .accessibilityLabel(L10n.text("MEU PROGRESSO"))
                .accessibilityValue(String(Int(progress)) + "%")
            HStack(spacing: 12) {
                ForEach([0, 50, 100], id: \.self) { value in
                    Button { progress = Double(value) } label: {
                        Text(verbatim: "\(value)%").font(MVFont.bold(13)).frame(maxWidth: .infinity, minHeight: 44)
                            .comicCard(bg: Int(progress) == value ? MV.C.desk : MV.C.card, radius: MV.R.md, shadow: MV.Shadow.s)
                    }.buttonStyle(.plain)
                }
            }
            Text(L10n.text("Geral: livre. Até a metade: 50%. Final: 100%. Você informa seu progresso para evitar spoilers."))
                .font(MVFont.body(13)).foregroundStyle(MV.C.muted)
            if let error { AuthErrorBanner(message: error) }
            Button {
                Task {
                    savingProgress = true
                    if await visit(Int(progress)) { editingProgress = false; await load(forceFollow: true) }
                    savingProgress = false
                }
            } label: {
                Text(savingProgress ? L10n.text("ENVIANDO…") : L10n.text("SALVAR PROGRESSO"))
                    .font(MVFont.label(13)).foregroundStyle(Color(hex: "#16130F"))
                    .frame(maxWidth: .infinity, minHeight: 50).comicCard(bg: MV.C.wow)
            }.buttonStyle(.plain).disabled(savingProgress || sending || pending != nil)
        }.padding(24).foregroundStyle(MV.C.ink)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationBackground(MV.C.paper).interactiveDismissDisabled(savingProgress)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.text("Escreva uma mensagem"), text: $draft, axis: .vertical).lineLimit(1...4)
                .font(MVFont.body(14)).disabled(sending || pending != nil)
            HStack(spacing: 12) {
                Button { mentioning = true } label: { Image(systemName: "at").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("MENCIONAR PESSOA")).disabled(sending || pending != nil)
                Button { composing = true } label: { Image(systemName: "photo").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n.text("ADICIONAR IMAGENS")).disabled(sending || pending != nil)
                Toggle(L10n.text("Spoiler"), isOn: $spoiler).font(MVFont.body(12, weight: 600)).disabled(sending || pending != nil)
                Button(L10n.text("ENVIAR")) { Task { await send() } }.font(MVFont.label(12)).frame(minHeight: 44)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 2000)
            }
            if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")).font(MVFont.body(11)) }
        }.padding(14).background(MV.C.paper)
        .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }
    private func watchRoom() async {
        guard let api = store.spacesAPI else { return }
        var revision: String?
        var retry = 1
        while !Task.isCancelled {
            do {
                let result = try await api.roomChanges(itemID, after: revision)
                try Task.checkCancellation()
                guard result.itemID == itemID, (0...100).contains(result.progress), result.online >= 0 else { throw SocialError.invalid }
                presence = .init(itemID: result.itemID, online: result.online, progress: result.progress)
                reconnecting = false; retry = 1
                if await load() { revision = result.revision }
                else if locked { revision = result.revision }
                else if timeline.busy { try await Task.sleep(for: .milliseconds(300)) }
                else { throw AuthError.apiUnavailable }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                reconnecting = true
                do { try await Task.sleep(for: .seconds(retry)) } catch { return }
                retry = min(retry * 2, 20); revision = nil
            }
        }
    }
    @discardableResult private func visit(_ value: Int?) async -> Bool {
        guard let api = store.spacesAPI else { return false }
        do {
            let result = try await api.visitRoom(itemID, progress: value)
            try Task.checkCancellation(); guard result.itemID == itemID else { throw SocialError.invalid }
            presence = result; error = nil; return true
        } catch is CancellationError { return false }
        catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult private func load(more: Bool = false, forceFollow: Bool = false) async -> Bool {
        guard !locked, let api = store.communityAPI, let item = store.item(itemID) else { return false }
        let wasEmpty = timeline.posts.isEmpty
        if forceFollow { following = true }
        let loaded = await timeline.load(api: api, filter: .init(universe: item.uni, item: itemID, kind: "room", segment: segment), more: more, following: { forceFollow || (following && !more) || wasEmpty })
        if loaded && !more && (forceFollow || following || wasEmpty) { following = true; scrollRequest += 1 }
        return loaded
    }
    private func send() async {
        guard !sending, let api = store.communityAPI, let item = store.item(itemID) else { return }
        sending = true; error = nil
        defer { sending = false }
        if pending == nil {
            var input = PostInput(universeID: item.uni, itemID: itemID, title: String(item.title.prefix(140)), text: draft, spoiler: spoiler)
            input.kind = "room"; input.segment = segment; pending = (UUID().uuidString.lowercased(), input)
        }
        guard let pending else { return }
        do {
            let result = try await api.publishPost(id: pending.id, input: pending.input)
            guard result.saved, result.id == pending.id else { throw SocialError.invalid }
            self.pending = nil; draft = ""; spoiler = false
            await load(forceFollow: true)
        } catch { self.error = error.localizedDescription }
    }
}
