import SwiftUI

struct LogDraft: Equatable {
    var itemID: String?
    var rating: Double = 0
    var liked: Bool = false
    var rewatch: Bool = false
    var spoiler: Bool = false
    var text: String = ""
}

enum OnboardingPhase: Equatable {
    case step1, step2, step3, loading
}

enum SearchFilter: String, CaseIterable {
    case all = "Tudo", works = "Obras", characters = "Personagens", events = "Eventos", people = "Pessoas"
}

struct SearchResultRow: Identifiable {
    let id: String
    let title: String
    let meta: String
    let typeLabel: String
    let pillBG: Color
    let pillFG: Color
    let posterBG: Color
    let posterFG: Color
    let initials: String
    let isCircular: Bool
    let route: Route
}

struct WrappedData {
    let logCount: Int
    let deltaLabel: String
    let hours: Int
    let hoursNote: String
    let universe: Universe
    let universeNote: String
    let topItem: Item?
    let topStars: Double
    let archetypeTitle: String
    let archetypeNote: String
    let topReviewText: String
    let topReviewLikes: Int
    let topReviewItemTitle: String
}

/// Estado global do app, injetado no ambiente. Espelha 1:1 os números e regras do
/// protótipo HTML (ver `<script>` de `reference/Multiverse v2.dc.html`).
@Observable
final class AppStore {
    /// Única fonte de dados/mutações — hoje `MockRepository`; a fase 2 (Supabase/Firebase)
    /// troca essa instância sem que `AppStore` ou as Views precisem mudar.
    private let repository: MultiverseRepository

    // MARK: - Catálogo (carregado por `bootstrap()`)
    var universes: [Universe] = []
    var items: [Item] = []
    var users: [User] = []
    var badgeNames: [String: String] = [:]
    var connections: [String: [String]] = [:]
    var timelines: [String: [TimelineEntry]] = [:]
    var readingOrders: [ReadingOrder] = []
    var lists: [LoreList] = []
    var genericReviewTexts: [String] = []
    var canonStatus: [String: CanonInfo] = [:]
    var canonStatusColors: [String: StatusColor] = [:]
    var duels: [Duel] = []
    var me = Me(id: "duda", following: [], followers: 0)
    let meID = "duda"

    private(set) var itemsByID: [String: Item] = [:]
    private(set) var usersByID: [String: User] = [:]
    private(set) var universesByID: [String: Universe] = [:]

    /// `true` até `bootstrap()` terminar de carregar o catálogo do repositório.
    var isLoading = true

    // MARK: - Navegação
    var tab: AppTab = .home
    var homePath: [Route] = []
    var searchPath: [Route] = []
    var notificationsPath: [Route] = []
    var profilePath: [Route] = []
    var unreadCount: Int = 4

    // MARK: - Rede
    var follows: Set<String> = []

    // MARK: - Conteúdo (amostras + geradas; ordem = mais recente primeiro)
    var reviews: [Review] = []
    var diary: [DiaryEntry] = []

    // MARK: - Toggles
    var likedReviews: Set<String> = []
    var likedComments: Set<String> = []   // chave "reviewId:index"
    var likedItems: Set<String> = []
    var wantList: Set<String> = []
    var revealedSpoilers: Set<String> = []
    var checks: [String: Bool] = [:]
    var orderVotes: Set<String> = []
    var orderFollows: Set<String> = []
    var likedLists: Set<String> = []

    // MARK: - Votos
    var pollVote: Int?
    var duelIndex: Int = 0
    var duelVotes: [Int: Int] = [:]
    var canonVotes: [String: Int] = [:]
    var essentialVotes: [String: Int] = [:]

    // MARK: - Registro
    var logDraft: LogDraft?

    // MARK: - Onboarding
    var onboardingPhase: OnboardingPhase = .step1
    var onboardingUniverses: Set<String> = []
    /// Persistido em `UserDefaults` (chave `mv-onboarded`); precisa ser uma propriedade
    /// armazenada (não computada) pra que a Observation dispare a atualização da UI.
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: "mv-onboarded") }
    }

    // MARK: - Toast
    var toast: String?
    private var toastTask: Task<Void, Never>?

    // MARK: - Init

    init(repository: MultiverseRepository? = nil) {
        let onboarded = UserDefaults.standard.bool(forKey: "mv-onboarded")
        isOnboarded = onboarded
        self.repository = repository ?? MockRepository(startFollowing: onboarded)
    }

    /// Carrega tudo do repositório. Chamado uma vez, a partir de `.task` na `RootView`.
    @MainActor
    func bootstrap() async {
        guard isLoading else { return }
        do {
            async let catalogResult = repository.loadCatalog()
            async let reviewsResult = repository.fetchReviews()
            async let diaryResult = repository.fetchDiary()
            async let followsResult = repository.fetchFollows()
            async let itemTogglesResult = repository.fetchItemToggles()
            async let reviewTogglesResult = repository.fetchReviewToggles()
            async let pollVotesResult = repository.fetchPollVotes()
            async let orderStateResult = repository.fetchOrderState()
            async let likedListsResult = repository.fetchLikedLists()

            let catalog = try await catalogResult
            universes = catalog.universes
            items = catalog.items
            users = catalog.users
            badgeNames = catalog.badgeNames
            connections = catalog.connections
            timelines = catalog.timelines
            readingOrders = catalog.readingOrders
            lists = catalog.lists
            genericReviewTexts = catalog.genericReviewTexts
            canonStatus = catalog.canonStatus
            canonStatusColors = catalog.canonStatusColors
            duels = catalog.duels
            me = catalog.me
            itemsByID = Dictionary(uniqueKeysWithValues: catalog.items.map { ($0.id, $0) })
            usersByID = Dictionary(uniqueKeysWithValues: catalog.users.map { ($0.id, $0) })
            universesByID = Dictionary(uniqueKeysWithValues: catalog.universes.map { ($0.id, $0) })

            reviews = try await reviewsResult
            diary = try await diaryResult
            follows = try await followsResult

            let itemToggles = try await itemTogglesResult
            wantList = itemToggles.wanted
            likedItems = itemToggles.liked
            checks = itemToggles.seenOverrides

            let reviewToggles = try await reviewTogglesResult
            likedReviews = reviewToggles.liked
            likedComments = reviewToggles.likedComments
            revealedSpoilers = reviewToggles.revealedSpoilers

            let pollVotes = try await pollVotesResult
            pollVote = pollVotes.weekly
            essentialVotes = pollVotes.essential
            canonVotes = pollVotes.canon
            duelVotes = pollVotes.duel

            let orderState = try await orderStateResult
            orderVotes = orderState.upvoted
            orderFollows = orderState.following

            likedLists = try await likedListsResult
        } catch {
            // MockRepository nunca lança; um repositório real trataria erro de rede aqui
            // (ex.: `loadError` pra a RootView mostrar um estado de erro com "tentar de novo").
        }
        isLoading = false
    }

    // MARK: - Acesso a dados

    func item(_ id: String) -> Item? { itemsByID[id] }
    func user(_ id: String) -> User? { usersByID[id] }
    func universe(_ id: String) -> Universe? { universesByID[id] }
    func universe(of item: Item) -> Universe { universesByID[item.uni]! }

    // MARK: - Visto / diário

    func isSeen(_ id: String) -> Bool {
        if let c = checks[id] { return c }
        return diary.contains { $0.itemId == id }
    }

    func toggleSeen(_ id: String) {
        let value = !isSeen(id)
        checks[id] = value
        let repository = self.repository
        Task { try? await repository.setItemSeen(itemID: id, seen: value) }
    }

    func myDiaryEntry(for itemID: String) -> DiaryEntry? {
        diary.first { $0.itemId == itemID }
    }

    // MARK: - Seguir

    func isFollowing(_ id: String) -> Bool { follows.contains(id) }

    var friendsList: [User] { users.filter { $0.id != meID && follows.contains($0.id) } }
    var friendsCount: Int { follows.count }

    /// Retorna `true` quando a ação acabou de seguir (pra a View decidir se dispara o ZAP!).
    @discardableResult
    func toggleFollow(_ id: String, silent: Bool = false) -> Bool {
        let turningOn = !follows.contains(id)
        if turningOn {
            follows.insert(id)
            if !silent, let u = usersByID[id] {
                showToast("Seguindo \(u.name). Seu feed ganhou reviews novas.")
            }
        } else {
            follows.remove(id)
        }
        let repository = self.repository
        Task { try? await repository.setFollowing(userID: id, following: turningOn) }
        return turningOn
    }

    func followAll(_ ids: [String]) {
        follows.formUnion(ids)
        let repository = self.repository
        Task { for id in ids { try? await repository.setFollowing(userID: id, following: true) } }
    }

    // MARK: - Curtidas / spoilers / listas

    func isLikedReview(_ id: String) -> Bool { likedReviews.contains(id) }
    func reviewLikeCount(_ review: Review) -> Int { review.likes + (isLikedReview(review.id) ? 1 : 0) }

    @discardableResult
    func toggleLikedReview(_ id: String) -> Bool {
        let turningOn = !likedReviews.contains(id)
        if turningOn { likedReviews.insert(id) } else { likedReviews.remove(id) }
        let repository = self.repository
        Task { try? await repository.setReviewLiked(reviewID: id, liked: turningOn) }
        return turningOn
    }

    func isSpoilerHidden(_ review: Review) -> Bool { review.spoiler && !revealedSpoilers.contains(review.id) }
    func revealSpoiler(_ id: String) {
        revealedSpoilers.insert(id)
        let repository = self.repository
        Task { try? await repository.setSpoilerRevealed(reviewID: id) }
    }

    func commentsLabel(for review: Review) -> String {
        let n = review.comments.count
        return n > 0 ? "\(n) comentário\(n > 1 ? "s" : "")" : "Comentar"
    }

    func isLikedComment(reviewID: String, index: Int) -> Bool { likedComments.contains("\(reviewID):\(index)") }
    func toggleLikedComment(reviewID: String, index: Int) {
        let key = "\(reviewID):\(index)"
        let turningOn = !likedComments.contains(key)
        if turningOn { likedComments.insert(key) } else { likedComments.remove(key) }
        let repository = self.repository
        Task { try? await repository.setCommentLiked(reviewID: reviewID, commentIndex: index, liked: turningOn) }
    }
    func commentLikeCount(review: Review, index: Int) -> Int {
        review.comments[index].likes + (isLikedComment(reviewID: review.id, index: index) ? 1 : 0)
    }

    func isItemLiked(_ id: String) -> Bool { likedItems.contains(id) }
    func toggleItemLiked(_ id: String) {
        let turningOn = !likedItems.contains(id)
        if turningOn { likedItems.insert(id) } else { likedItems.remove(id) }
        let repository = self.repository
        Task { try? await repository.setItemLiked(itemID: id, liked: turningOn) }
    }

    func isWanted(_ id: String) -> Bool { wantList.contains(id) }
    func toggleWanted(_ id: String) {
        let turningOn = !wantList.contains(id)
        if turningOn { wantList.insert(id) } else { wantList.remove(id) }
        let repository = self.repository
        Task { try? await repository.setItemWanted(itemID: id, wanted: turningOn) }
    }

    func isListLiked(_ id: String) -> Bool { likedLists.contains(id) }
    func listLikeCount(_ list: LoreList) -> Int { list.likes + (isListLiked(list.id) ? 1 : 0) }
    func toggleListLiked(_ id: String) {
        let turningOn = !likedLists.contains(id)
        if turningOn { likedLists.insert(id) } else { likedLists.remove(id) }
        let repository = self.repository
        Task { try? await repository.setListLiked(listID: id, liked: turningOn) }
    }

    // MARK: - Votações

    func weeklyPollPercents() -> [Int]? {
        guard pollVote != nil else { return nil }
        return Logic.pollPercents(base: StaticContent.weeklyDebateBase, chosen: pollVote)
    }
    func voteWeekly(_ index: Int) {
        guard pollVote == nil else { return }
        pollVote = index
        showToast("Voto computado. Veja o que o pessoal acha.")
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .weekly, optionIndex: index) }
    }

    func essentialPercents(for item: Item) -> [Int]? {
        guard essentialVotes[item.id] != nil else { return nil }
        return Logic.pollPercents(base: Logic.essentialVoteBase(item), chosen: essentialVotes[item.id])
    }
    func essentialTotalLabel(for item: Item) -> String {
        let base = Logic.essentialVoteBase(item).reduce(0, +)
        return essentialVotes[item.id] == nil ? "\(Logic.fmt(base)) votos · vote pra ver" : "\(Logic.fmt(base + 1)) votos"
    }
    func voteEssential(_ itemID: String, index: Int) {
        guard essentialVotes[itemID] == nil else { return }
        essentialVotes[itemID] = index
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .essential(itemID: itemID), optionIndex: index) }
    }

    func canonPercents(for item: Item) -> [Int]? {
        guard canonVotes[item.id] != nil else { return nil }
        return Logic.pollPercents(base: Logic.canonVoteBase(item), chosen: canonVotes[item.id])
    }
    func voteCanon(_ itemID: String, index: Int) {
        guard canonVotes[itemID] == nil else { return }
        canonVotes[itemID] = index
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .canon(itemID: itemID), optionIndex: index) }
    }

    var currentDuel: Duel { duels[duelIndex % duels.count] }
    var currentDuelPosition: Int { duelIndex % duels.count }
    func duelPercents() -> [Int]? {
        let di = currentDuelPosition
        guard duelVotes[di] != nil else { return nil }
        return Logic.pollPercents(base: duels[di].baseVotes, chosen: duelVotes[di])
    }
    func voteDuel(_ side: Int) {
        let di = currentDuelPosition
        guard duelVotes[di] == nil else { return }
        duelVotes[di] = side
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .duel(index: di), optionIndex: side) }
    }
    func nextDuel() { duelIndex += 1 }
    func duelTotalVotesLabel() -> String {
        let di = currentDuelPosition
        let base = duels[di].baseVotes
        let total = base[0] + base[1] + (duelVotes[di] != nil ? 1 : 0)
        return "\(Logic.fmt(total)) votos"
    }
    func duelResultNote() -> String? {
        let di = currentDuelPosition
        guard let ch = duelVotes[di] else { return nil }
        let base = duels[di].baseVotes
        let total = base[0] + base[1] + 1
        let frac = Double(base[ch] + 1) / Double(total)
        return frac >= 0.5 ? "Você está com a maioria" : "Você está com a minoria. Defenda nos comentários."
    }

    func weeklyPollTotalLabel() -> String {
        let total = StaticContent.weeklyDebateBase.reduce(0, +) + (pollVote != nil ? 1 : 0)
        return pollVote == nil ? "\(Logic.fmt(total)) votos · vote pra ver o resultado" : "\(Logic.fmt(total)) votos · você votou"
    }

    func isOrderVoted(_ id: String) -> Bool { orderVotes.contains(id) }
    func orderVoteCount(_ order: ReadingOrder) -> Int { order.votes + (isOrderVoted(order.id) ? 1 : 0) }
    @discardableResult
    func voteOrder(_ id: String) -> Bool {
        let turningOn = !orderVotes.contains(id)
        if turningOn { orderVotes.insert(id) } else { orderVotes.remove(id) }
        let repository = self.repository
        Task { try? await repository.setOrderUpvoted(orderID: id, upvoted: turningOn) }
        return turningOn
    }

    func isFollowingOrder(_ id: String) -> Bool { orderFollows.contains(id) }
    func toggleOrderFollow(_ id: String) {
        let turningOn = !orderFollows.contains(id)
        if turningOn { orderFollows.insert(id) } else { orderFollows.remove(id) }
        let repository = self.repository
        Task { try? await repository.setOrderFollowing(orderID: id, following: turningOn) }
    }

    // MARK: - Obra / Personagem / Evento

    func logActionLabel(for item: Item) -> String {
        if isSeen(item.id) { return "Registrar de novo" }
        return ["Personagem", "Evento"].contains(item.type) ? "Avaliar" : "Registrar"
    }

    func canonInfo(for item: Item) -> (status: String, note: String) {
        if let c = canonStatus[item.id] { return (c.status, c.note) }
        return ("Cânone", "Faz parte da continuidade principal (\(item.canon)).")
    }
    func canonColors(for status: String) -> (bg: Color, fg: Color) {
        if let c = canonStatusColors[status] { return (Color(hex: c.bg), Color(hex: c.fg)) }
        return (MV.C.ink, MV.C.card)
    }
    func timelineNeighbors(for item: Item) -> (before: TimelineEntry?, current: TimelineEntry?, after: TimelineEntry?) {
        guard let entries = timelines[item.uni], let idx = entries.firstIndex(where: { $0.itemId == item.id }) else {
            return (nil, nil, nil)
        }
        let before = idx > 0 ? entries[idx - 1] : nil
        let after = idx < entries.count - 1 ? entries[idx + 1] : nil
        return (before, entries[idx], after)
    }
    func connectedItems(for itemID: String) -> [Item] {
        (connections[itemID] ?? []).prefix(6).compactMap { itemsByID[$0] }
    }

    // MARK: - Universo

    func universePercent(_ uniID: String) -> Int {
        guard let u = universesByID[uniID] else { return 0 }
        let count = items.filter { $0.uni == uniID && isSeen($0.id) }.count
        return min(99, u.base + count)
    }

    func universeStats(_ uniID: String) -> [(count: String, label: String)] {
        guard let u = universesByID[uniID] else { return [] }
        return [(Logic.fmt(u.total), "Itens no cânone"), (Logic.fmt(u.members), "Membros"), (Logic.fmt(u.live), "Ativos agora")]
    }

    func topRatedItems(in uniID: String) -> [Item] {
        items.filter { $0.uni == uniID && $0.type != "Personagem" }.sorted { $0.avg > $1.avg }
    }
    func charactersList(in uniID: String) -> [Item] {
        items.filter { $0.uni == uniID && $0.type == "Personagem" }
    }
    func ordersList(in uniID: String) -> [ReadingOrder] {
        readingOrders.filter { $0.uni == uniID }.sorted { $0.votes > $1.votes }
    }
    func orderProgress(_ order: ReadingOrder) -> (done: Int, total: Int) {
        (order.steps.filter { isSeen($0) }.count, order.steps.count)
    }

    struct TimelineRow: Identifiable {
        var id: String { entry.itemId }
        let entry: TimelineEntry
        let item: Item
        let isSeen: Bool
        let friends: [User]
        let friendsLabel: String
    }
    func timelineRows(for uniID: String) -> [TimelineRow] {
        (timelines[uniID] ?? []).compactMap { entry in
            guard let it = itemsByID[entry.itemId] else { return nil }
            let fr = Array(friendRatings(for: it).prefix(4).map(\.user))
            var label = ""
            if fr.count == 1 { label = "\((fr[0].name.components(separatedBy: " ").first ?? fr[0].name)) já passou por aqui" }
            else if fr.count > 1 { label = "\(fr.count) amigos já passaram por aqui" }
            return TimelineRow(entry: entry, item: it, isSeen: isSeen(it.id), friends: fr, friendsLabel: label)
        }
    }
    func timelineIndex(for item: Item) -> Int? {
        timelines[item.uni]?.firstIndex { $0.itemId == item.id }
    }
    func timelineFriendChips(for uniID: String) -> [(user: User, whereLabel: String)] {
        guard let entries = timelines[uniID] else { return [] }
        return friendsList.compactMap { f in
            var lastIndex = -1
            for (i, entry) in entries.enumerated() {
                guard let it = itemsByID[entry.itemId] else { continue }
                if friendRatings(for: it).contains(where: { $0.user.id == f.id }) { lastIndex = i }
            }
            guard lastIndex >= 0 else { return nil }
            let era = entries[lastIndex].era.components(separatedBy: " · ").first ?? entries[lastIndex].era
            let firstName = f.name.components(separatedBy: " ").first ?? f.name
            return (f, "\(firstName) · \(era)")
        }
    }

    // MARK: - Reviews / feed

    func friendRatings(for item: Item) -> [(user: User, rating: Double)] {
        users.compactMap { u in
            guard u.id != meID, follows.contains(u.id) else { return nil }
            guard let r = Logic.friendRating(friend: u.id, item: item, reviews: reviews) else { return nil }
            return (u, r)
        }
    }
    func friendAvgLabel(for item: Item) -> String? {
        let fr = friendRatings(for: item)
        guard !fr.isEmpty else { return nil }
        let avg = fr.reduce(0.0) { $0 + $1.rating } / Double(fr.count)
        return "★ " + String(format: "%.1f", avg).replacingOccurrences(of: ".", with: ",")
    }

    func homeFeed(limit: Int = 8) -> [Review] {
        reviews.filter { follows.contains($0.user) || $0.user == meID }.prefix(limit).map { $0 }
    }

    func reviewsForItem(_ itemID: String, friendsOnly: Bool) -> [Review] {
        var revs = reviews.filter { $0.item == itemID }
        if friendsOnly {
            revs = revs.filter { follows.contains($0.user) || $0.user == meID }
        } else {
            revs.sort { $0.likes > $1.likes }
        }
        return revs
    }

    func reviewsIn(universe uniID: String, limit: Int) -> [Review] {
        reviews.filter { itemsByID[$0.item]?.uni == uniID }
            .sorted { $0.likes > $1.likes }
            .prefix(limit).map { $0 }
    }

    func trendingBuzz(for item: Item) -> String {
        let n = friendRatings(for: item).count
        if n > 0 { return "\(n) amigo\(n > 1 ? "s" : "") registrou" }
        return "\(Logic.fmt(Logic.logCount(item))) esta semana"
    }

    func review(_ id: String) -> Review? { reviews.first { $0.id == id } }

    // MARK: - Busca

    func searchResults(query: String, filter: SearchFilter) -> (rows: [SearchResultRow], totalCount: Int) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows: [SearchResultRow] = []

        if filter != .people {
            let filtered = items.filter { it in
                let typeOK: Bool
                switch filter {
                case .all: typeOK = true
                case .works: typeOK = !["Personagem", "Evento"].contains(it.type)
                case .characters: typeOK = it.type == "Personagem"
                case .events: typeOK = it.type == "Evento"
                case .people: typeOK = false
                }
                guard typeOK else { return false }
                guard !q.isEmpty else { return true }
                let uniName = universesByID[it.uni]?.name ?? ""
                return (it.title + uniName).lowercased().contains(q)
            }.sorted { Logic.logCount($0) > Logic.logCount($1) }

            rows.append(contentsOf: filtered.map { it in
                let uni = universesByID[it.uni]!
                let p = Logic.posterColors(item: it, universe: uni)
                let isCircular = it.type == "Personagem"
                let meta = "\(uni.name) · \(it.year) · ★ \(String(format: "%.1f", it.avg)) · \(Logic.fmt(Logic.logCount(it))) registros"
                return SearchResultRow(id: it.id, title: it.title, meta: meta, typeLabel: it.type, pillBG: uni.color, pillFG: uni.inkColor, posterBG: p.bg, posterFG: p.fg, initials: "", isCircular: isCircular, route: .item(it.id))
            })
        }

        if filter == .all || filter == .people {
            let peopleFiltered = users.filter { u in
                guard u.id != meID else { return false }
                let matches = q.isEmpty || (u.name + u.handle).lowercased().contains(q)
                if filter == .people { return matches }
                return !q.isEmpty && matches
            }
            rows.append(contentsOf: peopleFiltered.map { u in
                SearchResultRow(id: u.id, title: u.name, meta: "\(u.handle) · \(u.bio)", typeLabel: follows.contains(u.id) ? "Seguindo" : "Pessoa", pillBG: MV.C.card, pillFG: MV.C.ink, posterBG: Color(hex: u.avatarColor), posterFG: Logic.inkOn(hex: u.avatarColor), initials: Logic.initials(u.name), isCircular: true, route: .user(u.id))
            })
        }

        return (Array(rows.prefix(14)), rows.count)
    }

    // MARK: - Perfil

    struct BadgeProgress { let universe: Universe; let achieved: Bool; let remainingPct: Int }

    struct ProfileData {
        let user: User
        let isMe: Bool
        let stats: [(count: String, label: String)]
        let progress: [(universe: Universe, pct: Int)]
        let favorites: [Item]
        let recentReviews: [Review]
        let compatPercent: Int?
        let compatLine: String?
        let compatByUniverse: [(universe: Universe, pct: Int)]?
        let agreeLine: String?
        let disagreeLine: String?
        let badges: [BadgeProgress]
    }

    func profileData(for userID: String) -> ProfileData {
        let isMe = userID == meID
        let u = usersByID[userID]!
        let sd = Logic.seed(userID)
        let myRevs = reviews.filter { $0.user == userID }

        func pctFor(_ k: String) -> Int {
            if isMe { return universePercent(k) }
            let base = 10 + Int(Logic.seed(userID + k) % 85)
            return u.badgeUniverse == k ? max(base, 62) : base
        }

        let stats: [(String, String)]
        if isMe {
            stats = [("\(diary.count + 318)", "Registros"), ("312", "Seguidores"), ("\(friendsList.count)", "Seguindo")]
        } else {
            let followers = (u.followers ?? (200 + Int(sd % 700))) + (follows.contains(userID) ? 1 : 0)
            stats = [("\(120 + Int(sd % 600))", "Registros"), (Logic.fmt(followers), "Seguidores"), ("\(40 + Int(sd % 200))", "Seguindo")]
        }

        let progress = ["marvel", "dc", "wow"].map { k in (universesByID[k]!, pctFor(k)) }
        let favIDs: [String] = isMe ? StaticContent.myFavoriteItemIDs : Array(Set(myRevs.map(\.item)).prefix(4))
        let favorites = favIDs.compactMap { itemsByID[$0] }
        let recentReviews = Array(myRevs.prefix(4))

        var compatPercent: Int?
        var compatLine: String?
        var compatByUniverse: [(Universe, Int)]?
        var agreeLine: String?
        var disagreeLine: String?
        if !isMe {
            let cp = Logic.compat(userID)
            compatPercent = cp
            compatLine = cp > 78 ? "Almas gêmeas de cânone." : (cp > 62 ? "Gostos parecidos, brigas saudáveis." : "Discordam bastante. Rende bons debates.")
            compatByUniverse = ["marvel", "dc", "wow"].map { k in (universesByID[k]!, 30 + Int(Logic.seed(userID + k + "c") % 68)) }
            let agreeWork = StaticContent.compatAgreeWorks[Int(sd) % StaticContent.compatAgreeWorks.count]
            let agreePerson = StaticContent.compatAgreePeople[Int(sd) % StaticContent.compatAgreePeople.count]
            agreeLine = "\(agreeWork), \(agreePerson)"
            disagreeLine = StaticContent.compatDisagreeWorks[Int(sd >> 2) % StaticContent.compatDisagreeWorks.count]
        }

        let badges = ["wow", "marvel", "dc"].map { k -> BadgeProgress in
            let pct = pctFor(k)
            return BadgeProgress(universe: universesByID[k]!, achieved: pct >= 50, remainingPct: max(0, 50 - pct))
        }

        return ProfileData(user: u, isMe: isMe, stats: stats, progress: progress, favorites: favorites, recentReviews: recentReviews, compatPercent: compatPercent, compatLine: compatLine, compatByUniverse: compatByUniverse, agreeLine: agreeLine, disagreeLine: disagreeLine, badges: badges)
    }

    func profileLists() -> [(list: LoreList, stackColors: [Color])] {
        lists.map { l in
            let colors = l.items.prefix(4).compactMap { id -> Color? in
                guard let it = itemsByID[id] else { return nil }
                return Logic.posterColors(item: it, universe: universesByID[it.uni]!).bg
            }
            return (l, colors)
        }
    }

    // MARK: - Wrapped

    func wrappedData() -> WrappedData {
        let sep = diary.filter { $0.month == "Setembro" }
        var byUniverse: [String: Int] = [:]
        for d in sep {
            guard let it = itemsByID[d.itemId] else { continue }
            byUniverse[it.uni, default: 0] += 1
        }
        let topUni = byUniverse.max { $0.value < $1.value }?.key ?? "wow"
        let topDiary = sep.max { $0.rating < $1.rating }
        let topItem = topDiary.flatMap { itemsByID[$0.itemId] } ?? itemsByID["w-wotlk"]
        let mostLiked = reviews.filter { $0.user == meID }.max { reviewLikeCount($0) < reviewLikeCount($1) }
        let hours = sep.reduce(0.0) { total, d in
            total + (itemsByID[d.itemId].map { Logic.loreHours($0.type) } ?? 1)
        }
        let u = universesByID[topUni]!
        return WrappedData(
            logCount: sep.count,
            deltaLabel: "+\(max(1, sep.count - 4)) que agosto",
            hours: Int(hours.rounded()),
            hoursNote: "≈ \(max(1, Int((hours / 24).rounded()))) dias em outras realidades",
            universe: u,
            universeNote: "\(byUniverse[topUni] ?? 0) registros · \(universePercent(topUni))% do cânone visto",
            topItem: topItem,
            topStars: topDiary?.rating ?? 5,
            archetypeTitle: StaticContent.wrappedArchetypeTitle,
            archetypeNote: StaticContent.wrappedArchetypeNote,
            topReviewText: mostLiked?.text ?? "",
            topReviewLikes: mostLiked.map { reviewLikeCount($0) } ?? 0,
            topReviewItemTitle: mostLiked.flatMap { itemsByID[$0.item]?.title } ?? ""
        )
    }

    // MARK: - Sheet de registro

    func openLogBlank() { logDraft = LogDraft() }
    func openLog(for itemID: String) {
        let mine = myDiaryEntry(for: itemID)
        logDraft = LogDraft(itemID: itemID, rating: mine?.rating ?? 0, liked: false, rewatch: isSeen(itemID), spoiler: false, text: "")
    }
    func closeLog() { logDraft = nil }

    func setLogItem(_ itemID: String) {
        guard var d = logDraft else { return }
        d.itemID = itemID
        d.rewatch = isSeen(itemID)
        logDraft = d
    }

    /// Tocar na mesma nota de novo marca meia estrela
    func setLogRating(_ n: Int) {
        guard var d = logDraft else { return }
        d.rating = d.rating == Double(n) ? Double(n) - 0.5 : Double(n)
        logDraft = d
    }

    func saveLog() {
        guard let d = logDraft, let itemID = d.itemID, let item = itemsByID[itemID] else { return }
        let entry = DiaryEntry(itemId: itemID, day: 29, month: "Setembro", rating: d.rating, liked: d.liked, rewatch: d.rewatch)
        diary.insert(entry, at: 0)
        checks[itemID] = true

        let trimmed = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var newReview: Review?
        if !trimmed.isEmpty || d.rating > 0 {
            let text = trimmed.isEmpty ? "\(Logic.verb(item.type)) hoje." : trimmed
            let review = Review(id: "r-\(UUID().uuidString.prefix(8))", user: meID, item: itemID, rating: d.rating, text: text, spoiler: d.spoiler, likes: 0, when: "agora", comments: [])
            reviews.insert(review, at: 0)
            newReview = review
        }
        logDraft = nil
        showToast("Publicado no feed do seu pessoal")

        let repository = self.repository
        Task {
            try? await repository.addDiaryEntry(entry)
            try? await repository.setItemSeen(itemID: itemID, seen: true)
            if let newReview { try? await repository.publishReview(newReview) }
        }
    }

    /// Resposta na thread da review (campo de resposta da Tela 7).
    func postComment(reviewID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        let comment = Comment(user: meID, text: trimmed, likes: 0, when: "agora")
        reviews[idx].comments.append(comment)
        let authorID = reviews[idx].user
        showToast(authorID == meID ? "Resposta publicada" : "\(usersByID[authorID]?.name ?? "") vai ser notificado")
        let repository = self.repository
        Task { try? await repository.postComment(reviewID: reviewID, comment: comment) }
    }

    // MARK: - Onboarding

    @discardableResult
    func toggleOnboardingUniverse(_ id: String) -> Bool {
        let turningOn = !onboardingUniverses.contains(id)
        if turningOn { onboardingUniverses.insert(id) } else { onboardingUniverses.remove(id) }
        return turningOn
    }

    func onboardingConsumablePicks() -> [Item] {
        Array(items.filter { onboardingUniverses.contains($0.uni) && $0.type != "Personagem" }.prefix(15))
    }

    func onboardingPeopleSorted() -> [User] {
        users.filter { $0.id != meID }.sorted { a, b in
            let aPri = onboardingUniverses.contains(a.badgeUniverse) ? 1 : 0
            let bPri = onboardingUniverses.contains(b.badgeUniverse) ? 1 : 0
            if aPri != bPri { return aPri > bPri }
            return Logic.compat(a.id) > Logic.compat(b.id)
        }
    }

    func advanceOnboarding() {
        switch onboardingPhase {
        case .step1: onboardingPhase = .step2
        case .step2: onboardingPhase = .step3
        case .step3: finishOnboardingLoading()
        case .loading: break
        }
    }
    func backOnboarding() {
        switch onboardingPhase {
        case .step2: onboardingPhase = .step1
        case .step3: onboardingPhase = .step2
        default: break
        }
    }

    private func finishOnboardingLoading() {
        onboardingPhase = .loading
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard let self else { return }
            self.isOnboarded = true
            self.tab = .home
            self.homePath = []
            self.showToast("Feed pronto. Bem-vindo ao Multiverse.")
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Navegação por aba

    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .notifications: notificationsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Trocar de aba preserva a pilha de cada aba; tocar na aba já ativa volta pro topo.
    func goToTab(_ newTab: AppTab) {
        if tab == newTab {
            switch newTab {
            case .home: homePath = []
            case .search: searchPath = []
            case .notifications: notificationsPath = []
            case .profile: profilePath = []
            }
        }
        tab = newTab
        if newTab == .notifications { unreadCount = 0 }
    }

    func openMyProfile() {
        tab = .profile
        profilePath = []
    }

    /// Tocar no seu próprio nome/avatar leva pro Perfil (aba); tocar no de outros empilha o perfil.
    func openUserProfile(_ id: String) {
        if id == meID { openMyProfile() } else { push(.user(id)) }
    }

    // MARK: - Perfil (edição vinda do fluxo de criação de conta)

    /// Aplica nome/usuário/avatar/bio escolhidos na criação de conta ao usuário logado.
    func applyProfileEdits(name: String, handle: String, avatarColor: String, bio: String) {
        guard let idx = users.firstIndex(where: { $0.id == meID }) else { return }
        let current = users[idx]
        let updated = User(id: current.id, name: name, handle: handle, avatarColor: avatarColor, bio: bio, followers: current.followers, badgeUniverse: current.badgeUniverse)
        users[idx] = updated
        usersByID[meID] = updated
    }
}
