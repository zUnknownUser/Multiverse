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
struct LiveRoomView: View {
    let itemID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeline = CommunityTimeline()
    @State private var presence: RoomVisit?
    @State private var progress = 0
    @State private var segment = 0
    @State private var draft = ""
    @State private var spoiler = false
    @State private var pending: (id: String, input: PostInput)?
    @State private var sending = false
    @State private var error: String?
    @State private var mentioning = false
    @State private var composing = false
    @State private var olderLoaded = false
    private var locked: Bool { (presence?.progress ?? 0) < segment * 50 }
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let item = store.item(itemID) {
                    HStack(spacing: 12) {
                        PosterView(item: item, universe: store.universe(of: item), width: 50, height: 75, titleSize: 9)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(MVFont.section(20))
                            Text(L10n.format("%1$@ pessoas na sala", String(presence?.online ?? 0))).font(MVFont.body(12, weight: 500))
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(value: $progress, in: 0...100, step: 10) { Text(L10n.format("Meu progresso: %1$@%%", String(progress))).font(MVFont.bold(13)) }
                        Button(L10n.text("SALVAR PROGRESSO")) { Task { await visit(progress) } }.disabled(sending || progress == presence?.progress)
                    }.padding(12).comicCard(shadow: MV.Shadow.s)
                    Picker(L10n.text("Trecho da conversa"), selection: $segment) {
                        Text(L10n.text("Geral")).tag(0); Text(L10n.text("Até a metade")).tag(1); Text(L10n.text("Final")).tag(2)
                    }.pickerStyle(.segmented).disabled(sending || pending != nil)
                    if let error { AuthErrorBanner(message: error) }
                    if let error = timeline.error { AuthErrorBanner(message: error) }
                    if locked { CommunityEmptyMessage(text: L10n.text("Este trecho contém spoilers. Atualize seu progresso para participar.")) }
                    else {
                        if timeline.posts.isEmpty && !timeline.busy && timeline.error == nil { CommunityEmptyMessage(text: L10n.text("A sala está quieta. Comece a conversa.")) }
                        ForEach(timeline.posts) { post in CommunityPostCard(post: post, user: timeline.users[post.user]) }
                        if timeline.cursor != nil { Button(L10n.text("MENSAGENS ANTERIORES")) { olderLoaded = true; Task { await load(more: true) } }.disabled(timeline.busy) }
                        if olderLoaded { Button(L10n.text("VER MENSAGENS RECENTES")) { olderLoaded = false; Task { await load() } } }
                    }
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.safeAreaInset(edge: .bottom) {
            if !locked {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.text("Escreva uma mensagem"), text: $draft, axis: .vertical).lineLimit(1...4).disabled(sending || pending != nil)
                    HStack {
                        Button { mentioning = true } label: { Image(systemName: "at") }.accessibilityLabel(L10n.text("MENCIONAR PESSOA")).disabled(sending || pending != nil)
                        Button { composing = true } label: { Image(systemName: "photo") }.accessibilityLabel(L10n.text("ADICIONAR IMAGENS")).disabled(sending || pending != nil)
                        Toggle(L10n.text("Spoiler"), isOn: $spoiler).font(MVFont.body(12, weight: 600)).disabled(sending || pending != nil)
                        Button(L10n.text("ENVIAR")) { Task { await send() } }.disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.unicodeScalars.count > 2000)
                    }
                    if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")).font(.caption) }
                }.padding(14).background(MV.C.paper).overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await visit(nil)
            while !Task.isCancelled {
                if !olderLoaded { await load() }
                do { try await Task.sleep(for: .seconds(10)); try Task.checkCancellation() } catch { return }
                await visit(nil)
            }
        }
        .task(id: segment) { olderLoaded = false; await load() }
        .refreshable { olderLoaded = false; await visit(nil); await load() }
        .sheet(isPresented: $mentioning) { MentionPicker { user in draft += (draft.isEmpty || draft.hasSuffix(" ") ? "" : " ") + user.handle + " " } }
        .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) { if let item = store.item(itemID) { PostComposer(universe: item.uni, item: itemID, segment: segment, kind: "room") } }
    }
    private func visit(_ value: Int?) async {
        guard let api = store.spacesAPI else { return }
        do { let result = try await api.visitRoom(itemID, progress: value); try Task.checkCancellation(); guard result.itemID == itemID else { throw SocialError.invalid }; let old = presence?.progress; presence = result; if value != nil || old == nil { progress = result.progress }; error = nil }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func load(more: Bool = false) async {
        guard !locked, let api = store.communityAPI, let item = store.item(itemID) else { return }
        await timeline.load(api: api, filter: .init(universe: item.uni, item: itemID, kind: "room", segment: segment), more: more)
    }
    private func send() async {
        guard !sending, let api = store.communityAPI, let item = store.item(itemID) else { return }; sending = true; error = nil
        defer { sending = false }
        if pending == nil { var input = PostInput(universeID: item.uni, itemID: itemID, title: String(item.title.prefix(140)), text: draft, spoiler: spoiler); input.kind = "room"; input.segment = segment; pending = (UUID().uuidString.lowercased(), input) }
        guard let pending else { return }
        do { let r = try await api.publishPost(id: pending.id, input: pending.input); guard r.saved, r.id == pending.id else { throw SocialError.invalid }; self.pending = nil; draft = ""; spoiler = false; olderLoaded = false; await load() }
        catch { self.error = error.localizedDescription }
    }
}
