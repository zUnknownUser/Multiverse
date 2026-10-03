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
    var initialFeed = "recent"
    var kind: String? = nil; var club: String? = nil; var schedule: String? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var timeline = CommunityTimeline()
    @State private var composing = false
    @State private var search = ""
    @State private var feed = "recent"
    @State private var selectedUniverse = ""
    init(universe: String?, item: String?, initialFeed: String = "recent", initialSearch: String = "", kind: String? = nil, club: String? = nil, schedule: String? = nil) {
        self.universe = universe; self.item = item; self.initialFeed = initialFeed
        self.kind = kind; self.club = club; self.schedule = schedule
        _feed = State(initialValue: initialFeed); _search = State(initialValue: initialSearch)
    }
    private var filter: CommunityFilter { .init(universe: universe ?? (selectedUniverse.isEmpty ? nil : selectedUniverse), item: item, search: search.trimmingCharacters(in: .whitespacesAndNewlines), feed: initialFeed == "unanswered" ? "unanswered" : feed, kind: kind, club: club, schedule: schedule) }
    private var title: String { initialFeed == "unanswered" ? L10n.text("SEM RESPOSTAS") : kind == "theory" ? L10n.text("TEORIAS") : kind == "duel" ? L10n.text("DUELOS") : L10n.text("COMUNIDADE") }
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(title).font(MVFont.display(28, width: 122))
                if let universe { Text(store.universe(universe)?.name ?? universe).kicker() }
                if let item { Text(store.item(item)?.title ?? item).font(MVFont.bold(14)) }
                if kind == nil && club == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            module(L10n.text("CLUBES"), icon: "person.3", route: .liveClubs(universe))
                            module(L10n.text("SALAS"), icon: "bubble.left.and.bubble.right", route: .liveRooms(universe))
                            module(L10n.text("TEORIAS"), icon: "lightbulb", route: .communityFeed(.init(universe: universe, item: item, kind: "theory")))
                            module(L10n.text("DUELOS"), icon: "bolt", route: .communityFeed(.init(universe: universe, item: item, kind: "duel")))
                        }.padding(.bottom, 4)
                    }
                }
                TextField(L10n.text("Buscar publicações"), text: $search).textInputAutocapitalization(.never).autocorrectionDisabled().padding(12).comicCard(shadow: MV.Shadow.s)
                if universe == nil && club == nil {
                    Picker(L10n.text("Universo"), selection: $selectedUniverse) {
                        Text(L10n.text("Todos os universos")).tag("")
                        ForEach(store.universes) { Text($0.name).tag($0.id) }
                    }.tint(MV.C.ink)
                }
                if initialFeed != "unanswered" {
                    Picker(L10n.text("Ordenar publicações"), selection: $feed) {
                        Text(L10n.text("Recentes")).tag("recent")
                        Text(L10n.text("Seguindo")).tag("following")
                        Text(L10n.text("Em conversa")).tag("active")
                    }.pickerStyle(.segmented)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { publicationActions }
                    VStack(alignment: .leading) { publicationActions }
                }
                if let error = timeline.error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if timeline.busy { ProgressView() }
                if timeline.posts.isEmpty && !timeline.busy && timeline.error == nil {
                    Text(initialFeed == "unanswered" ? L10n.text("Nenhuma conversa sem respostas por aqui. Explore as outras publicações ou comece a sua.") : L10n.text("Nenhuma publicação por aqui ainda. Comece uma conversa.")).font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.muted).frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard(shadow: MV.Shadow.s)
                }
                ForEach(timeline.posts) { post in CommunityPostCard(post: post, user: timeline.users[post.user]) }
                if timeline.cursor != nil { Button(L10n.text("CARREGAR MAIS")) { Task { await load(more: true) } }.disabled(timeline.busy) }
            }.padding(MV.pad)
        }.task(id: filter) {
            do { if !search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await load() } catch { }
        }.refreshable { await load() }
        .sheet(isPresented: $composing, onDismiss: { Task { await load() } }) {
            PostComposer(universe: filter.universe, item: item, kind: kind ?? "discussion", club: club, schedule: schedule)
        }
    }
    @ViewBuilder private var publicationActions: some View {
        Button(L10n.text("NOVA PUBLICAÇÃO")) { composing = true }.buttonStyle(.borderedProminent).fixedSize(horizontal: true, vertical: false)
        if initialFeed != "unanswered" {
            Button(L10n.text("SEM RESPOSTAS")) {
                var unanswered = filter; unanswered.feed = "unanswered"
                store.push(.communityFeed(unanswered))
            }.font(MVFont.bold(11)).foregroundStyle(MV.C.ink).buttonStyle(.bordered).fixedSize(horizontal: true, vertical: false)
        }
    }
    private func module(_ title: String, icon: String, route: Route) -> some View {
        Button { store.push(route) } label: { Label(title, systemImage: icon).font(MVFont.bold(12)).foregroundStyle(MV.C.ink).padding(12).comicCard(shadow: MV.Shadow.s) }.buttonStyle(.plain)
    }
    private func load(more: Bool = false) async {
        if let api = store.communityAPI { await timeline.load(api: api, filter: filter, more: more) }
    }
}
struct CommunityPostCard: View {
    let post: CommunityPost; let user: User?
    var compact = false
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.push(.post(post.id)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let user { HStack { AvatarView(user: user, size: 28); Text(user.name).font(MVFont.bold(13)); Spacer(); Text(post.createdAt, style: .relative).font(MVFont.body(10, weight: 500)) } }
                if post.kind == "theory" { Text(L10n.text("TEORIA")).kicker() }
                if post.kind == "duel" { Text(L10n.text("DUELO")).kicker() }
                if post.spoiler { Text(L10n.text("PUBLICAÇÃO COM SPOILER")).kicker().foregroundStyle(MV.C.muted) }
                else {
                    Text(post.title).font(MVFont.section(18)).lineLimit(compact ? 2 : nil)
                    Text(post.text).font(MVFont.body(14, weight: 500)).lineLimit(compact ? 2 : 3)
                    if !compact, let image = post.images?.first { CommunityImageView(post: post.id, image: image).frame(maxHeight: 230).clipped() }
                }
                HStack { Text(store.universe(post.universeID)?.name ?? post.universeID); Spacer(); Label("\(post.commentCount)", systemImage: "bubble.right"); Label("\(post.interaction.likes)", systemImage: "heart") }.font(MVFont.body(11, weight: 600))
            }.foregroundStyle(MV.C.ink).frame(maxWidth: .infinity, alignment: .leading).padding(14).comicCard()
        }.buttonStyle(.plain)
    }
}
