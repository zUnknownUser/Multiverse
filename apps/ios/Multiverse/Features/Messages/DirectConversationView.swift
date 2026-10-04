import SwiftUI

private struct DirectBottomPosition: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
struct DirectConversationView: View {
    @Bindable var thread: DirectThreadStore
    let inbox: DirectMessagesStore
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var blockError: String?
    @State private var showingCards = false
    @State private var confirmingBlock = false
    @State private var reportMessage: DirectMessage?
    @State private var following = true
    @State private var opened = false
    @State private var newMessages = false
    @State private var scrollRequest = 0
    private let bottomID = "direct-bottom"
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).frame(width: 30, height: 40) }.accessibilityLabel(L10n.text("Voltar"))
                if let user = thread.user {
                    AvatarView(user: user, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name).font(MVFont.bold(16)).lineLimit(1)
                        Text(user.handle).font(MVFont.body(11)).foregroundStyle(MV.C.muted)
                    }
                    Spacer()
                    Menu {
                        Button(L10n.text("Ver perfil")) { store.openUserProfile(user.id) }
                        Button(L10n.text("Bloquear"), role: .destructive) { confirmingBlock = true }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 20, weight: .bold)).frame(width: 40, height: 40) }
                    .accessibilityLabel(L10n.text("Opções da conversa"))
                } else { Text(L10n.text("Mensagens")).font(MVFont.bold(16)); Spacer() }
            }.padding(.horizontal, MV.pad).padding(.vertical, 8)
            if let error = thread.error {
                PeopleStatusNotice(message: error) { await thread.refresh() }.padding(.horizontal, MV.pad)
            }
            if let blockError { AuthErrorBanner(message: blockError).padding(.horizontal, MV.pad) }
            if thread.state == "pending" && !thread.unavailable { requestBanner }
            if thread.loading && !thread.loaded { ProgressView().padding() }
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if thread.before != nil {
                                Button(L10n.text("MENSAGENS ANTERIORES")) {
                                    let first = thread.messages.first?.id
                                    Task { await thread.refresh(older: true); if let first { proxy.scrollTo(first, anchor: .top) } }
                                }.font(MVFont.bold(11)).disabled(thread.loading)
                            }
                            if thread.loaded && thread.messages.isEmpty && !thread.unavailable {
                                Text(L10n.text("Dê o primeiro oi ou compartilhe uma obra.")).font(MVFont.body(14)).foregroundStyle(MV.C.muted).padding(24)
                            }
                            ForEach(thread.messages) { message in
                                DirectMessageBubble(message: message, isMe: message.senderID == inbox.ownerID,
                                    read: thread.state == "accepted" && (UInt64(message.sequence) ?? .max) <= thread.readThrough)
                                .id(message.id)
                                .contextMenu {
                                    if message.senderID != inbox.ownerID && message.kind != "removed" {
                                        Button(L10n.text("Denunciar"), role: .destructive) { reportMessage = message }
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id(bottomID)
                                .background(GeometryReader { geo in Color.clear.preference(key: DirectBottomPosition.self, value: geo.frame(in: .named("direct-chat")).maxY) })
                        }.padding(MV.pad)
                    }.coordinateSpace(name: "direct-chat").scrollDismissesKeyboard(.interactively)
                        .onPreferenceChange(DirectBottomPosition.self) { y in
                            following = y >= 0 && y <= viewport.size.height + 40
                            if following { newMessages = false }
                        }
                        .onChange(of: scrollRequest) { _, _ in proxy.scrollTo(bottomID, anchor: .bottom) }
                        .onChange(of: viewport.size.height) { _, _ in if following { proxy.scrollTo(bottomID, anchor: .bottom) } }
                        .onChange(of: thread.messages.last?.id) { _, _ in
                            if !opened || following { opened = true; scrollRequest += 1 }
                            else { newMessages = true }
                        }
                        .onAppear { if thread.loaded { scrollRequest += 1 } }
                }
            }
            if newMessages {
                Button(L10n.text("NOVAS MENSAGENS ↓")) { following = true; newMessages = false; scrollRequest += 1 }
                    .font(MVFont.bold(11)).padding(8).frame(maxWidth: .infinity).background(MV.C.accent)
            }
            if !thread.unavailable { composer }
        }.background(MV.C.paper).foregroundStyle(MV.C.ink).toolbar(.hidden, for: .navigationBar)
            .task {
                inbox.activePeer = thread.peerID
                await thread.refresh()
                scrollRequest += 1
            }
            .onDisappear { if inbox.activePeer == thread.peerID { inbox.activePeer = nil }; thread.compactHistory() }
            .task(id: "\(following)-\(thread.messages.last?.sequence ?? "0")-\(scenePhase)-\(thread.state)") {
                guard scenePhase == .active, following, thread.state == "accepted", let seq = thread.messages.last?.sequence else { return }
                await thread.markVisible(through: seq)
            }
            .sheet(isPresented: $showingCards) {
                DirectCardPicker { id in thread.attachedItemID = id }
            }
            .sheet(item: $reportMessage) { message in DirectReportSheet(thread: thread, message: message) }
            .confirmationDialog(L10n.text("Bloquear este lorista?"), isPresented: $confirmingBlock, titleVisibility: .visible) {
                Button(L10n.text("Bloquear"), role: .destructive) {
                    Task {
                        if await store.social?.setBlock(thread.peerID, blocked: true) == true {
                            store.people?.invalidateDiscovery(); await thread.refresh(); await inbox.refresh(); dismiss()
                        } else { blockError = store.social?.actionError ?? SocialError.invalid.localizedDescription }
                    }
                }
            } message: { Text(L10n.text("Vocês deixarão de ver a conversa e não poderão trocar mensagens enquanto houver bloqueio.")) }
    }
    private var requestBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(thread.incomingRequest ? "Aceite o pedido para conversar com este lorista." : "Aguarde o pedido de conversa ser aceito para enviar mais mensagens."))
                .font(MVFont.body(13, weight: 600))
            if thread.incomingRequest {
                HStack(spacing: 16) {
                    Button(L10n.text("ACEITAR")) { Task { _ = await thread.decide(accepted: true); await inbox.refresh() } }
                    Button(L10n.text("RECUSAR"), role: .destructive) { Task { if await thread.decide(accepted: false) { await inbox.refresh(); dismiss() } } }
                }.font(MVFont.bold(12)).disabled(thread.sending)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard(bg: MV.C.accent.opacity(0.2), shadow: 0).padding(.horizontal, MV.pad)
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if let id = thread.attachedItemID, let item = store.item(id) {
                HStack {
                    Image(systemName: "book.closed")
                    Text(item.title).font(MVFont.bold(12)).lineLimit(1)
                    Spacer()
                    Button { thread.attachedItemID = nil } label: { Image(systemName: "xmark.circle.fill") }.disabled(thread.pendingID != nil || thread.sending)
                }
            }
            if thread.pendingID != nil && !thread.sending {
                Text(L10n.text("Envio não confirmado. Toque em reenviar; sua mensagem não será duplicada."))
                    .font(MVFont.body(11)).foregroundStyle(MV.C.muted)
            }
            HStack(spacing: 8) {
                Button { showingCards = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .bold)).frame(width: 40, height: 40)
                        .background(MV.C.card).clipShape(Circle()).overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                }.accessibilityLabel(L10n.text("Mandar carta")).disabled(thread.state == "pending" || thread.pendingID != nil || thread.sending)
                TextField(L10n.text("Escreva algo…"), text: $thread.draft, axis: .vertical)
                    .font(MVFont.body(14)).lineLimit(1...4).padding(.horizontal, 12).padding(.vertical, 10)
                    .background(MV.C.card).clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
                    .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .disabled(thread.pendingID != nil || thread.sending || thread.state == "pending")
                Button {
                    Task { if await thread.send() { following = true; scrollRequest += 1; await inbox.refresh() } }
                } label: {
                    Group {
                        if thread.sending { ProgressView().tint(MV.C.paper) }
                        else { Image(systemName: thread.pendingID == nil ? "arrow.up" : "arrow.clockwise").font(.system(size: 17, weight: .bold)) }
                    }.foregroundStyle(MV.C.paper).frame(width: 44, height: 44).background(thread.canSend ? MV.C.ink : MV.C.muted).clipShape(Circle())
                }.accessibilityLabel(L10n.text(thread.pendingID == nil ? "ENVIAR" : "REENVIAR")).disabled(!thread.canSend)
            }
            HStack {
                Toggle(L10n.text("Contém spoiler"), isOn: $thread.spoiler).font(MVFont.body(11)).toggleStyle(.button).tint(MV.C.dc)
                    .disabled(thread.pendingID != nil || thread.sending || thread.state == "pending")
                Spacer()
                if thread.draft.count > 1800 { Text("\(thread.draft.count)/2000").font(MVFont.body(11)).foregroundStyle(thread.draft.count > 2000 ? MV.C.marvel : MV.C.muted) }
            }
        }.padding(.horizontal, MV.pad).padding(.vertical, 10).background(MV.C.paper)
            .overlay(alignment: .top) { Rectangle().fill(MV.C.ink).frame(height: MV.stroke) }
    }
}

private struct DirectMessageBubble: View {
    let message: DirectMessage
    let isMe: Bool
    let read: Bool
    @Environment(AppStore.self) private var store
    @State private var revealed = false
    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if message.kind == "removed" {
                    Text(L10n.text("Mensagem indisponível")).font(MVFont.body(13))
                } else if message.spoiler && !isMe && !revealed {
                    Button { revealed = true } label: { Label(L10n.text("Mostrar spoiler"), systemImage: "eye.slash").font(MVFont.bold(13)) }
                } else {
                    if message.kind == "workCard" {
                        if let id = message.itemID, let item = store.item(id) {
                            Button { store.push(.item(id)) } label: {
                                HStack(spacing: 10) {
                                    PosterView(item: item, universe: store.universe(of: item), width: 44, height: 66, titleSize: 9, shadow: 0)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(MVFont.bold(13)).lineLimit(3)
                                        Text(L10n.text("VER →")).font(MVFont.bold(11))
                                    }
                                }
                            }.buttonStyle(.plain)
                        } else { Text(L10n.text("Esta obra não está mais disponível.")).font(MVFont.body(13)) }
                    }
                    if let duelID = DuelInvitation.id(in: message.text) {
                        Button { store.push(.dailyDuel(duelID)) } label: {
                            Label(L10n.text("ENTRAR NO DUELO"), systemImage: "bolt.fill").font(MVFont.bold(13))
                        }.buttonStyle(.plain)
                    }
                    if !message.text.isEmpty { Text(DuelInvitation.displayText(in: message.text)).font(MVFont.body(14, weight: 500)).textSelection(.enabled) }
                }
                HStack(spacing: 6) {
                    Text(message.createdAt, format: .dateTime.day().month().hour().minute())
                    if isMe { Image(systemName: read ? "checkmark.circle.fill" : "checkmark").accessibilityLabel(L10n.text(read ? "Lida" : "Enviada")) }
                }.font(MVFont.body(9)).opacity(0.7)
            }.padding(12).foregroundStyle(isMe ? MV.C.paper : MV.C.ink)
                .background(isMe ? MV.C.ink : MV.C.card).clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
                .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            if !isMe { Spacer(minLength: 40) }
        }
    }
}
private struct DirectCardPicker: View {
    let pick: (String) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.prefix(60)) { item in
                    Button { pick(item.id); dismiss() } label: {
                        HStack(spacing: 12) {
                            PosterView(item: item, universe: store.universe(of: item), width: 40, height: 60, titleSize: 8, shadow: 0)
                            Text(item.title).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        }
                    }.listRowBackground(MV.C.paper)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(MV.C.paper)
                .searchable(text: $query, prompt: L10n.text("Buscar obra…"))
                .navigationTitle(L10n.text("Mandar carta")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancelar")) { dismiss() } } }
        }
    }
}
private struct DirectReportSheet: View {
    let thread: DirectThreadStore
    let message: DirectMessage
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "spam"
    @State private var block = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Picker(L10n.text("Motivo"), selection: $reason) {
                    Text(L10n.text("Spam")).tag("spam")
                    Text(L10n.text("Conteúdo ofensivo")).tag("offensive")
                    Text(L10n.text("Spoiler sem aviso")).tag("spoiler")
                    Text(L10n.text("Outro")).tag("other")
                }
                Toggle(L10n.text("Também bloquear este lorista"), isOn: $block).tint(MV.C.dc)
                Text(L10n.text("A mensagem denunciada será enviada para análise da moderação."))
                    .font(MVFont.body(12)).foregroundStyle(MV.C.muted)
                if let error = thread.error { AuthErrorBanner(message: error) }
                PrimaryAuthButton(title: L10n.text("DENUNCIAR"), enabled: !thread.sending) {
                    Task { if await thread.report(message, reason: reason, alsoBlock: block) { dismiss() } }
                }
                Spacer()
            }.padding(MV.pad).background(MV.C.paper).navigationTitle(L10n.text("Denunciar mensagem"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancelar")) { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
