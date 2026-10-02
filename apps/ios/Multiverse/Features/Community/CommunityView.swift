import SwiftUI

struct CommunityLink: View {
    var universe: String? = nil
    var item: String? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.communityAPI != nil {
            Button { store.push(.community(universe: universe, item: item)) } label: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    VStack(alignment: .leading) {
                        Text(L10n.text("COMUNIDADE")).font(MVFont.section(17))
                        Text(L10n.text("Perguntas, ideias e conversas sobre este universo.")).font(MVFont.body(12, weight: 500))
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }.foregroundStyle(MV.C.ink).padding(14).comicCard()
            }.buttonStyle(.plain)
        }
    }
}
struct CommunityView: View {
    let universe: String?; let item: String?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var timeline = CommunityTimeline()
    @State private var composing = false
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("COMUNIDADE")).font(MVFont.display(28, width: 122))
                if let universe { Text(store.universe(universe)?.name ?? universe).kicker() }
                if let item { Text(store.item(item)?.title ?? item).font(MVFont.bold(14)) }
                Button(L10n.text("NOVA PUBLICAÇÃO")) { composing = true }.buttonStyle(.borderedProminent)
                if let error = timeline.error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if timeline.busy { ProgressView() }
                if timeline.posts.isEmpty && !timeline.busy && timeline.error == nil {
                    Text(L10n.text("Nenhuma publicação por aqui ainda. Comece uma conversa.")).foregroundStyle(MV.C.muted)
                }
                ForEach(timeline.posts) { post in
                    Button { store.push(.post(post.id)) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            if let user = timeline.users[post.user] { HStack { AvatarView(user: user, size: 28); Text(user.name).font(MVFont.bold(13)) } }
                            if post.spoiler {
                                Text(L10n.text("PUBLICAÇÃO COM SPOILER")).kicker().foregroundStyle(MV.C.muted)
                            } else {
                                Text(post.title).font(MVFont.section(18))
                                Text(post.text).font(MVFont.body(14, weight: 500)).lineLimit(3)
                            }
                            HStack { Text(store.universe(post.universeID)?.name ?? post.universeID); Spacer(); Label("\(post.commentCount)", systemImage: "bubble.right"); Label("\(post.interaction.likes)", systemImage: "heart") }.font(MVFont.body(11, weight: 600))
                        }.foregroundStyle(MV.C.ink).frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard()
                    }.buttonStyle(.plain)
                }
                if timeline.cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await load(more: true) } }.disabled(timeline.busy) }
            }.padding(MV.pad)
        }.task { await load() }.refreshable { await load() }
        .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) {
            PostComposer(universe: universe, item: item)
        }
    }
    private func load(more: Bool = false) async {
        if let api = store.communityAPI { await timeline.load(api: api, universe: universe, item: item, more: more) }
    }
}
private struct PostComposer: View {
    let universe: String?; let item: String?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUniverse = ""
    @State private var title = ""
    @State private var text = ""
    @State private var spoiler = false
    @State private var busy = false
    @State private var error: String?
    @State private var pending: (id: String, input: PostInput)?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text("Publicações da comunidade são públicas, mesmo quando seu diário é privado."))
                    if universe == nil {
                        Picker(L10n.text("Universo"), selection: $selectedUniverse) {
                            ForEach(store.universes) { u in Text(u.name).tag(u.id) }
                        }
                    } else { Text(store.universe(universe!)?.name ?? universe!) }
                    if let item { Text(store.item(item)?.title ?? item) }
                    TextField(L10n.text("Título"), text: $title, axis: .vertical)
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel(L10n.text("Texto da publicação"))
                    Text("\(title.unicodeScalars.count)/140 · \(text.unicodeScalars.count)/5000").font(.caption)
                    Toggle(L10n.text("Contém spoiler"), isOn: $spoiler)
                }.disabled(busy || pending != nil)
                if pending != nil { Text(L10n.text("Envio pendente. Tente novamente para confirmar sem duplicar sua publicação.")) }
                if let error { AuthErrorBanner(message: error) }
                Button(busy ? L10n.text("ENVIANDO…") : L10n.text("PUBLICAR")) { Task { await publish() } }
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.unicodeScalars.count > 140 || text.unicodeScalars.count > 5000 || selectedUniverse.isEmpty)
            }.navigationTitle(L10n.text("NOVA PUBLICAÇÃO"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("FECHAR")) { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy || pending != nil)
        .onAppear { if selectedUniverse.isEmpty { selectedUniverse = universe ?? store.universes.first?.id ?? "" } }
    }
    private func publish() async {
        guard let api = store.communityAPI else { return }; busy = true; error = nil
        defer { busy = false }
        let draft = pending ?? (UUID().uuidString.lowercased(), PostInput(universeID: selectedUniverse, itemID: item, title: title, text: text, spoiler: spoiler))
        pending = draft
        do {
            let r = try await api.publishPost(id: draft.0, input: draft.1)
            guard r.saved, r.id == draft.0 else { throw SocialError.invalid }
            pending = nil; dismiss(); store.push(.post(r.id))
        } catch { self.error = error.localizedDescription }
    }
}
