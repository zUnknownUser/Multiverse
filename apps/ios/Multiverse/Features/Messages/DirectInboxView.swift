import SwiftUI

struct DirectInboxView: View {
    @Bindable var messages: DirectMessagesStore
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var requests = false
    @State private var newConversation = false
    private var rows: [DirectConversation] { messages.conversations.filter { $0.incomingRequest == requests } }
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.text("MENSAGENS")).font(MVFont.display(30, width: 122))
                    Spacer()
                    Button { newConversation = true } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MV.C.paper).frame(width: 40, height: 40)
                            .background(MV.C.ink).clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    }.accessibilityLabel(L10n.text("Nova conversa"))
                }
                HStack(spacing: 0) {
                    tab(L10n.text("Conversas"), value: false)
                    tab(L10n.text("Pedidos"), value: true)
                }.clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                if let error = messages.error {
                    PeopleStatusNotice(message: error) { await messages.refresh() }
                }
                if messages.loading && !messages.loaded { ProgressView().frame(maxWidth: .infinity) }
                if messages.loaded && rows.isEmpty && messages.error == nil {
                    VStack(spacing: 10) {
                        Image(systemName: requests ? "tray" : "bubble.left.and.bubble.right").font(.system(size: 28, weight: .bold))
                        Text(L10n.text(requests ? "Nenhum pedido novo." : "Nenhuma conversa ainda.")).font(MVFont.bold(16))
                        Text(L10n.text(requests ? "Pedidos de pessoas que você não segue aparecem aqui." : "Converse com outros loristas e compartilhe suas próximas leituras."))
                            .font(MVFont.body(13)).foregroundStyle(MV.C.muted).multilineTextAlignment(.center)
                        if !requests { Button(L10n.text("Nova conversa")) { newConversation = true }.font(MVFont.bold(13)) }
                    }.frame(maxWidth: .infinity).padding(24).comicCard(shadow: 0, dashed: true)
                }
                LazyVStack(spacing: 0) {
                    ForEach(rows) { c in
                        Button { store.push(.conversation(c.user.id)) } label: {
                            HStack(spacing: 12) {
                                AvatarView(user: c.user, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.user.name).font(MVFont.bold(15))
                                    Text(preview(c.lastMessage)).font(MVFont.body(13)).foregroundStyle(MV.C.muted).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(c.updatedAt, style: .relative).font(MVFont.body(10)).foregroundStyle(MV.C.muted)
                                    if c.unreadCount > 0 {
                                        Text(String(c.unreadCount)).font(MVFont.black(11)).foregroundStyle(MV.C.paper)
                                            .padding(6).background(Capsule().fill(MV.C.marvel))
                                    }
                                }
                            }.padding(.vertical, 12)
                        }.buttonStyle(.plain)
                        Divider().overlay(MV.C.divider)
                    }
                }
                if messages.nextCursor != nil {
                    Button(L10n.text("CARREGAR MAIS")) { Task { await messages.refresh(more: true) } }.disabled(messages.loading)
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }.task { await messages.refresh() }.refreshable { await messages.refresh() }
        .sheet(isPresented: $newConversation) { DirectPeoplePicker(api: messages.api as? any PeopleAPI, owner: messages.ownerID) { store.push(.conversation($0)) } }
    }
    private func tab(_ text: String, value: Bool) -> some View {
        Button { requests = value } label: {
            Text(text.uppercased()).font(MVFont.bold(12)).frame(maxWidth: .infinity).frame(height: 44)
                .foregroundStyle(requests == value ? MV.C.paper : MV.C.ink).background(requests == value ? MV.C.ink : MV.C.card)
        }.buttonStyle(.plain)
    }
    private func preview(_ m: DirectMessage?) -> String {
        guard let m else { return "" }
        if m.kind == "removed" { return L10n.text("Mensagem indisponível") }
        if m.spoiler { return L10n.text("Mensagem com spoiler") }
        if m.kind == "workCard" { return L10n.text("mandou uma carta") }
        return m.text
    }
}

struct DirectPeoplePicker: View {
    let api: (any PeopleAPI)?
    let owner: String
    let onPick: (String) -> Void
    var onPickUser: ((User) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var users: [User] = []
    @State private var error: String?
    @State private var loading = false
    @State private var cursor: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let error { PeopleStatusNotice(message: error) { await search() } }
                    if loading { ProgressView() }
                    ForEach(users) { user in
                        Button { onPickUser?(user); onPick(user.id); dismiss() } label: {
                            HStack(spacing: 12) {
                                AvatarView(user: user, size: 40)
                                VStack(alignment: .leading) { Text(user.name).font(MVFont.bold(14)); Text(user.handle).font(MVFont.body(12)).foregroundStyle(MV.C.muted) }
                                Spacer(); Image(systemName: "chevron.right")
                            }.foregroundStyle(MV.C.ink).padding(12).comicCard(shadow: 0)
                        }.buttonStyle(.plain)
                    }
                    if !loading && users.isEmpty && error == nil { Text(L10n.text("Nenhum lorista encontrado. Tente outro nome ou volte mais tarde.")).font(MVFont.body(14)) }
                    if cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await search(more: true) } }.disabled(loading) }
                }.padding(MV.pad)
            }.background(MV.C.paper).navigationTitle(L10n.text("Nova conversa")).navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: L10n.text("Buscar loristas"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancelar")) { dismiss() } } }
                .task(id: query) {
                    users = []; cursor = nil
                    do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await search() } catch { }
                }
        }
    }
    private func search(more: Bool = false) async {
        guard let api else { return }; let requested = query; let previousCursor = cursor
        loading = true; error = nil
        defer { if requested == query { loading = false } }
        do {
            let page = try await api.searchPeople(query: requested, after: more ? previousCursor : nil)
            try Task.checkCancellation(); try page.validate(ownerID: owner); guard requested == query else { return }
            let next = page.users.map(\.user).filter { $0.id != owner && $0.id != "multiverse-editorial" }
            let old = more ? users : []; users = old + next.filter { u in !old.contains { $0.id == u.id } }; cursor = page.nextCursor
        } catch is CancellationError { } catch { if requested == query { self.error = error.localizedDescription } }
    }
}
