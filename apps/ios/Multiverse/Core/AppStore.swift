import SwiftUI

struct LogDraft: Equatable {
    var id = UUID()
    var loggedAt: Date?
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

enum TheoryFeedFilter: String, CaseIterable {
    case open = "Em aberto", confirmed = "Confirmadas", refuted = "Refutadas", mine = "Minhas"
}

/// Modo Noir — "Siga o modo do sistema" ou força claro/escuro (Ajustes).
enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return L10n.text("Sistema")
        case .light: return L10n.text("Claro")
        case .dark: return L10n.text("Noir")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
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
@MainActor
@Observable
final class AppStore {
    /// Conteúdo de demonstração; perfil e onboarding usam a API NestJS via `AccountAPI`.
    private let repository: MultiverseRepository
    private let catalogAPI: (any CatalogAPI)?
    private let activityAPI: (any ActivityAPI)?
    let directMessages: DirectMessagesStore?
    let library: LibraryStore?
    var showsDemoFeatures: Bool { !usesAccountAPI }
    let communityAPI: (any CommunityAPI)?
    var spacesAPI: (any SpacesAPI)? { communityAPI as? any SpacesAPI }
    let notifications: NotificationStore?
    let social: SocialStore?
    let people: PeopleStore?
    var usesRemotePeople: Bool { people != nil }
    var activityLoadError: String?
    private(set) var activityRefreshError: String?
    private(set) var isRefreshingActivity = false
    private var activityRevision = 0
    var usesRemoteActivity: Bool { activityAPI != nil }
    var logSaveError: String?
    private(set) var isSavingLog = false
    private var activityFollowerCount = 0
    var usesRemoteCatalog: Bool { catalogAPI != nil }
    private(set) var catalogIssue: CatalogError?
    var catalogLoadError: String? { catalogIssue?.errorDescription }
    var comingSoonUniverses = StaticContent.comingSoonUniverses.map { UpcomingUniverse(id: $0, name: $0) }
    private let widgetWriter: (any WidgetSnapshotWriting)?

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
    let meID: String
    private let onboardingKey: String
    private let accountAPI: (any AccountAPI)?
    var accountLoadError: String?
    var onboardingError: String?
    var onboardingTransitioning = false
    private var remoteVersion = 0
    private var onboardingCandidates: [User] = []
    var minimumOnboardingFollows = 3
    var usesAccountAPI: Bool { accountAPI != nil }
    @ObservationIgnored private var onboardingSaveQueue: Task<OnboardingState, Error>?
    @ObservationIgnored private var onboardingDebounce: Task<Void, Never>?

    private(set) var itemsByID: [String: Item] = [:]
    private(set) var usersByID: [String: User] = [:]
    private(set) var universesByID: [String: Universe] = [:]

    /// `true` até `bootstrap()` terminar de carregar o catálogo do repositório.
    var isLoading = true

    // MARK: - Navegação
    var tab: AppTab = .home
    var homePath: [Route] = []
    var searchPath: [Route] = []
    var libraryPath: [Route] = []
    var clubsPath: [Route] = []
    var profilePath: [Route] = []
    var unreadCount: Int { notifications?.unreadCount ?? 0 }

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
    var reactions: [String: ReactionType] = [:]   // reviewID → reação escolhida
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

    /// Usuário sendo desafiado — abre a `DuelChallengeSheet` de qualquer tela (perfil, Home, conversa).
    var showingChallengeUserID: String?

    // MARK: - Onboarding
    var onboardingPhase: OnboardingPhase = .step1
    var onboardingUniverses: Set<String> = []
    /// Persistido em `UserDefaults` por conta; precisa ser uma propriedade
    /// armazenada (não computada) pra que a Observation dispare a atualização da UI.
    var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: onboardingKey) }
    }

    /// Modo Noir. `RootView` aplica `.preferredColorScheme` a partir daqui.
    var themePreference: ThemePreference {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: "mv-theme") }
    }

    // MARK: - Escudo de spoiler
    var shieldPoints: [String: Int] = [:]         // universeID → índice na timeline
    var shieldAdvanceAutomatically = true

    // MARK: - Clubes de maratona
    var clubs: [Club] = []
    var clubMessages: [ClubMessage] = []
    var clubMemberUnits: [String: Int] = [:]      // "clubID|userID" → unidades concluídas
    var heartedClubMessages: Set<String> = []
    var powedClubMessages: Set<String> = []

    // MARK: - Teorias
    var theories: [Theory] = []
    var theoryVotes: [String: Int] = [:]          // theoryID → 0 (Plausível) / 1 (Viajou)
    var lorePoints = 0
    var theoryAccuracyPercent = 0

    // MARK: - Previsões
    var predictionEvents: [PredictionEvent] = []
    var predictionPoints = 0
    var predictionAnswers: [String: PredictionAnswer] = [:]

    // MARK: - Onde assistir (cache por obra, carregado sob demanda)
    var watchAvailabilityByItem: [String: WatchAvailability] = [:]

    // MARK: - Mensagens e cartas
    var conversations: [Conversation] = []
    var messagesByConversation: [String: [Message]] = [:]

    // MARK: - Salas por obra
    var rooms: [Room] = []
    var roomMessages: [String: [RoomMessage]] = [:]    // itemID → mensagens
    var roomProgress: [String: Int] = [:]              // itemID → índice de trecho alcançado
    var liveEvent: LiveEvent?

    // MARK: - Sugestões de correção (cache por obra, carregado sob demanda)
    var correctionsByItem: [String: [CorrectionSuggestion]] = [:]

    // MARK: - Toast
    var toast: String?
    private var toastTask: Task<Void, Never>?

    // MARK: - Init

    init(repository: MultiverseRepository? = nil, session: AuthSession? = nil, accountAPI: (any AccountAPI)? = nil, widgetWriter: (any WidgetSnapshotWriting)? = nil, catalogAPI: (any CatalogAPI)? = nil, activityAPI: (any ActivityAPI)? = nil, peopleAPI: (any PeopleAPI)? = nil, socialAPI: (any SocialAPI)? = nil, communityAPI: (any CommunityAPI)? = nil, notificationsAPI: (any NotificationsAPI)? = nil, libraryAPI: (any LibraryAPI)? = nil, directMessagesAPI: (any DirectMessagesAPI)? = nil) {
        self.directMessages = directMessagesAPI.map { DirectMessagesStore(api: $0, ownerID: session?.userID ?? "duda") }
        self.library = libraryAPI.map { LibraryStore(api: $0) }
        self.communityAPI = communityAPI
        self.notifications = notificationsAPI.map { NotificationStore(api: $0) }
        self.social = socialAPI.map { SocialStore(api: $0) }
        self.people = peopleAPI.map { PeopleStore(api: $0, ownerID: session?.userID ?? "duda") }
        self.activityAPI = activityAPI
        self.catalogAPI = catalogAPI
        self.accountAPI = accountAPI
        self.widgetWriter = widgetWriter
        meID = session?.userID ?? "duda"
        onboardingKey = session.map { "mv-onboarded-\($0.userID)" } ?? "mv-onboarded"
        let onboarded = accountAPI == nil ? UserDefaults.standard.bool(forKey: onboardingKey) : (session?.onboarding?.completed ?? false)
        isOnboarded = onboarded
        themePreference = ThemePreference(rawValue: UserDefaults.standard.string(forKey: "mv-theme") ?? "") ?? .system
        self.repository = repository ?? MockRepository(startFollowing: onboarded, session: session)
    }

    /// Carrega tudo do repositório. Chamado uma vez, a partir de `.task` na `RootView`.
    func bootstrap() async {
        guard isLoading else { return }
        catalogIssue = nil
        do {
            async let catalogResult = repository.loadCatalog()
            async let remoteCatalogResult = catalogAPI?.fetchCatalog()
            async let reviewsResult = repository.fetchReviews()
            async let diaryResult = repository.fetchDiary()
            async let followsResult = repository.fetchFollows()
            async let itemTogglesResult = repository.fetchItemToggles()
            async let reviewTogglesResult = repository.fetchReviewToggles()
            async let reactionsResult = repository.fetchReactions()
            async let pollVotesResult = repository.fetchPollVotes()
            async let orderStateResult = repository.fetchOrderState()
            async let likedListsResult = repository.fetchLikedLists()
            async let shieldStateResult = repository.fetchShieldState()
            async let clubsResult = repository.fetchClubs()
            async let clubStateResult = repository.fetchClubState()
            async let theoriesResult = repository.fetchTheories()
            async let theoryLoreResult = repository.fetchTheoryLoreState()
            async let predictionEventsResult = repository.fetchPredictionEvents()
            async let predictionStateResult = repository.fetchPredictionState()
            async let conversationsResult = repository.fetchConversations()
            async let roomsResult = repository.fetchRooms()
            async let roomProgressResult = repository.fetchRoomProgress()
            async let liveEventResult = repository.fetchLiveEvent()

            let catalog = try await catalogResult
            let remoteCatalog = try await remoteCatalogResult
            try remoteCatalog?.validate()
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
            if let remoteCatalog { applyCatalog(remoteCatalog) }

            let sampleReviews = try await reviewsResult
            let sampleDiary = try await diaryResult
            reviews = activityAPI == nil ? sampleReviews : []
            diary = activityAPI == nil ? sampleDiary : []
            follows = try await followsResult

            let itemToggles = try await itemTogglesResult
            wantList = itemToggles.wanted
            likedItems = itemToggles.liked
            checks = itemToggles.seenOverrides

            let reviewToggles = try await reviewTogglesResult
            likedReviews = reviewToggles.liked
            likedComments = reviewToggles.likedComments
            revealedSpoilers = reviewToggles.revealedSpoilers
            reactions = try await reactionsResult

            let pollVotes = try await pollVotesResult
            pollVote = pollVotes.weekly
            essentialVotes = pollVotes.essential
            canonVotes = pollVotes.canon
            duelVotes = pollVotes.duel

            let orderState = try await orderStateResult
            orderVotes = orderState.upvoted
            orderFollows = orderState.following

            likedLists = try await likedListsResult

            let shieldState = try await shieldStateResult
            shieldPoints = shieldState.points
            shieldAdvanceAutomatically = shieldState.advanceAutomatically

            clubs = try await clubsResult
            let clubState = try await clubStateResult
            clubMemberUnits = clubState.memberUnits
            heartedClubMessages = clubState.heartedMessages
            powedClubMessages = clubState.powedMessages
            if let firstClub = clubs.first {
                clubMessages = try await repository.fetchClubMessages(clubID: firstClub.id)
            }

            theories = try await theoriesResult
            theoryVotes = pollVotes.theory
            let loreState = try await theoryLoreResult
            lorePoints = loreState.points
            theoryAccuracyPercent = loreState.accuracyPercent

            predictionEvents = try await predictionEventsResult
            let predState = try await predictionStateResult
            predictionPoints = predState.points
            predictionAnswers = predState.answers

            conversations = try await conversationsResult
            rooms = try await roomsResult
            roomProgress = try await roomProgressResult
            liveEvent = try await liveEventResult
        } catch is CancellationError {
            return
        } catch {
            catalogIssue = error as? CatalogError ?? .unavailable
            isLoading = false
            return
        }
        if accountAPI != nil {
            do { try await loadRemoteAccount() }
            catch { accountLoadError = error.localizedDescription }
        }
        if accountLoadError == nil { await loadRemoteActivity() }
        isLoading = false
        syncWidgetData()
    }

    // MARK: - Acesso a dados

    private func applyCatalog(_ snapshot: CatalogSnapshot) {
        universes = snapshot.universes
        items = snapshot.items
        comingSoonUniverses = snapshot.comingSoon
        universesByID = Dictionary(uniqueKeysWithValues: universes.map { ($0.id, $0) })
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func loadRemoteActivity() async {
        guard let activityAPI else { return }
        activityLoadError = nil
        do {
            let snapshot = try await activityAPI.fetchActivity()
            try Task.checkCancellation()
            try snapshot.validate(for: meID)
            applyActivity(snapshot)
        } catch is CancellationError { return
        } catch { activityLoadError = error.localizedDescription }
    }

    /// Refresh in place: a network error must not turn known history into an empty diary.
    func refreshActivity() async {
        guard let activityAPI, !isLoading, !isSavingLog, !isRefreshingActivity else { return }
        isRefreshingActivity = true
        activityRefreshError = nil
        let revision = activityRevision
        defer { isRefreshingActivity = false }
        do {
            let snapshot = try await activityAPI.fetchActivity()
            try Task.checkCancellation()
            guard revision == activityRevision else { return }
            try snapshot.validate(for: meID)
            applyActivity(snapshot)
            syncWidgetData()
        } catch is CancellationError { return
        } catch {
            if revision == activityRevision { activityRefreshError = error.localizedDescription }
        }
    }

    private func applyActivity(_ snapshot: ActivitySnapshot) {
        diary = snapshot.entries
        reviews = snapshot.reviews.map(\.display)
        activityFollowerCount = snapshot.followerCount
        for universe in snapshot.universes where universesByID[universe.id] == nil { universesByID[universe.id] = universe }
        for item in snapshot.items { itemsByID[item.id] = item }
        items = items.map { itemsByID[$0.id] ?? $0 }
        for entry in diary { checks[entry.itemId] = true }
    }

    var logPickerItems: [Item] {
        let featured = StaticContent.logQuickPickIDs.compactMap { item($0) }.filter { item in items.contains { $0.id == item.id } }
        guard usesRemoteCatalog else { return featured }
        let ids = Set(featured.map(\.id))
        return featured + items.filter { !ids.contains($0.id) }
    }

    func item(_ id: String) -> Item? { itemsByID[id] ?? social?.items[id] }
    func user(_ id: String) -> User? { people?.profiles[id]?.user ?? social?.users[id] ?? usersByID[id] }
    func universe(_ id: String) -> Universe? { universesByID[id] ?? social?.universes[id] }
    func universe(of item: Item) -> Universe { universe(item.uni)! }

    // MARK: - Visto / diário

    func isSeen(_ id: String) -> Bool {
        if let c = checks[id] { return c }
        return diary.contains { $0.itemId == id }
    }

    func toggleSeen(_ id: String) {
        guard !onboardingTransitioning else { return }
        setSeen(id, seen: !isSeen(id))
    }

    /// Shared by reading orders, diary publication and the spoiler shield.
    private func setSeen(_ id: String, seen: Bool) {
        checks[id] = seen
        scheduleOnboardingSave()
        let repository = self.repository
        Task { try? await repository.setItemSeen(itemID: id, seen: seen) }
        syncWidgetData()
    }

    func myDiaryEntry(for itemID: String) -> DiaryEntry? {
        diary.first { $0.itemId == itemID }
    }

    // MARK: - Seguir

    func isFollowing(_ id: String) -> Bool {
        if isOnboarded, let people, people.state != nil { return people.followingIDs.contains(id) }
        return follows.contains(id)
    }

    var friendsList: [User] {
        if isOnboarded, let people { return people.followingIDs.sorted().compactMap { people.profiles[$0]?.user } }
        return users.filter { $0.id != meID && follows.contains($0.id) }
    }
    var friendsCount: Int { isOnboarded ? (people?.state?.followingIDs.count ?? follows.count) : follows.count }

    /// Retorna `true` quando a ação acabou de seguir (pra a View decidir se dispara o ZAP!).
    @discardableResult
    func toggleFollow(_ id: String, silent: Bool = false) -> Bool {
        guard !onboardingTransitioning else { return false }
        if isOnboarded, let people {
            let following = !isFollowing(id)
            Task {
                if await people.setFollowing(id, following: following) {
                    follows = people.followingIDs
                    if !silent { showToast(L10n.text(following ? "Agora você segue este lorista." : "Você deixou de seguir este lorista.")) }
                }
            }
            return false
        }
        let turningOn = !follows.contains(id)
        if turningOn {
            follows.insert(id)
            if !silent, let u = usersByID[id] {
                showToast(L10n.format("Seguindo %1$@. Seu feed ganhou reviews novas.", String(describing: u.name)))
            }
        } else {
            follows.remove(id)
        }
        let repository = self.repository
        Task { try? await repository.setFollowing(userID: id, following: turningOn) }
        scheduleOnboardingSave()
        return turningOn
    }

    func followAll(_ ids: [String]) {
        guard !onboardingTransitioning else { return }
        follows.formUnion(ids)
        scheduleOnboardingSave()
        let repository = self.repository
        Task { for id in ids { try? await repository.setFollowing(userID: id, following: true) } }
    }

    // MARK: - Curtidas / spoilers / listas

    func isLikedReview(_ id: String) -> Bool { isRemoteReview(id) ? (social?.interactions[id]?.liked ?? false) : likedReviews.contains(id) }
    func reviewLikeCount(_ review: Review) -> Int { isRemoteReview(review.id) ? (social?.interactions[review.id]?.likes ?? 0) : review.likes + (isLikedReview(review.id) ? 1 : 0) }

    @discardableResult
    func toggleLikedReview(_ id: String) -> Bool {
        if isRemoteReview(id), let social {
            Task {
                if !(await social.setReaction(reviewID: id, reaction: social.interactions[id]?.myReaction, liked: !isLikedReview(id))), let error = social.actionError { showToast(error) }
            }
            return false
        }
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

    /// Contagem base determinística por tipo (~20% chance de ficar em 0 e sumir do rodapé),
    /// mais 1 se for a reação escolhida pelo usuário — mesmo espírito de `Logic.logCount`.
    func reactionCounts(for reviewID: String) -> [(type: ReactionType, count: Int)] {
        if isRemoteReview(reviewID) {
            return ReactionType.allCases.compactMap { type in
                let count = social?.interactions[reviewID]?.reactions[type.rawValue] ?? 0
                return count > 0 ? (type, count) : nil
            }
        }
        let mine = reactions[reviewID]
        return ReactionType.allCases.compactMap { type in
            let sd = Logic.seed(reviewID + type.rawValue)
            let base = sd % 5 == 0 ? 0 : 1 + Int(sd % 60)
            let count = base + (mine == type ? 1 : 0)
            return count > 0 ? (type, count) : nil
        }
    }

    func userReaction(for reviewID: String) -> ReactionType? { isRemoteReview(reviewID) ? social?.interactions[reviewID]?.myReaction.flatMap(ReactionType.init(rawValue:)) : reactions[reviewID] }

    /// Tocar na mesma reação de novo remove; tocar numa diferente troca.
    func setReaction(_ type: ReactionType, for reviewID: String) {
        if isRemoteReview(reviewID), let social {
            let parent = social.comments.first { $0.value.contains { $0.id == reviewID } }?.key
            Task {
                let desired = social.interactions[reviewID]?.myReaction == type.rawValue ? nil : type.rawValue
                if !(await social.setReaction(reviewID: parent ?? reviewID, commentID: parent == nil ? nil : reviewID, reaction: desired, liked: social.interactions[reviewID]?.liked ?? false)), let error = social.actionError { showToast(error) }
            }
            return
        }
        reactions[reviewID] = (reactions[reviewID] == type) ? nil : type
        let newValue = reactions[reviewID]
        let repository = self.repository
        Task { try? await repository.setReaction(reviewID: reviewID, type: newValue) }
    }

    func commentsLabel(for review: Review) -> String {
        let n = isRemoteReview(review.id) ? (social?.commentCounts[review.id] ?? 0) : review.comments.count
        return n > 0 ? L10n.format("comments.count", n) : L10n.text("Comentar")
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

    func isItemLiked(_ id: String) -> Bool { library.map { $0.favoriteIDs.contains(id) } ?? likedItems.contains(id) }
    func toggleItemLiked(_ id: String) {
        if let library { Task { await library.change("favorite", itemID: id, enabled: !isItemLiked(id)) }; return }

        let turningOn = !likedItems.contains(id)
        if turningOn { likedItems.insert(id) } else { likedItems.remove(id) }
        let repository = self.repository
        Task { try? await repository.setItemLiked(itemID: id, liked: turningOn) }
    }

    func isWanted(_ id: String) -> Bool { library.map { $0.wantedIDs.contains(id) } ?? wantList.contains(id) }
    func toggleWanted(_ id: String) {
        if let library { Task { await library.change("wanted", itemID: id, enabled: !isWanted(id)) }; return }

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
        showToast(L10n.text("Voto computado. Veja o que o pessoal acha."))
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .weekly, optionIndex: index) }
    }

    func essentialPercents(for item: Item) -> [Int]? {
        guard essentialVotes[item.id] != nil else { return nil }
        return Logic.pollPercents(base: Logic.essentialVoteBase(item), chosen: essentialVotes[item.id])
    }
    func essentialTotalLabel(for item: Item) -> String {
        let base = Logic.essentialVoteBase(item).reduce(0, +)
        return essentialVotes[item.id] == nil ? L10n.format("%1$@ votos · vote pra ver", String(describing: Logic.fmt(base))) : L10n.format("%1$@ votos", String(describing: Logic.fmt(base + 1)))
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
        syncWidgetData()
    }
    func nextDuel() { duelIndex += 1; syncWidgetData() }

    /// Manda os números atuais pra extensão de widgets via App Group (ver `WidgetBridge`).
    func syncWidgetData() {
        guard showsDemoFeatures else { return }
        guard let widgetWriter, !isLoading, catalogLoadError == nil, accountLoadError == nil, activityLoadError == nil, !Task.isCancelled, !duels.isEmpty else { return }
        let mainUniID = user(meID)?.badgeUniverse ?? "marvel"
        let followedOrder = readingOrders.first { orderFollows.contains($0.id) } ?? readingOrders.first
        let progress = followedOrder.map { orderProgress($0) } ?? (done: 0, total: 0)
        let nextItem = followedOrder
            .flatMap { order in order.steps.first { !isSeen($0) } }
            .flatMap { itemsByID[$0] }

        let duel = currentDuel
        widgetWriter.save(WidgetBridge.Snapshot(
            universeName: universe(mainUniID)?.name ?? "",
            universePercent: universePercent(mainUniID),
            universePercentDelta: 3,
            nextOrderItemTitle: nextItem?.title ?? followedOrder?.title ?? "",
            nextOrderDone: progress.done,
            nextOrderTotal: progress.total,
            duelQuestion: duel.question,
            duelSideATitle: itemsByID[duel.a]?.title ?? "",
            duelSideBTitle: itemsByID[duel.b]?.title ?? "",
            duelVotesLabel: duelTotalVotesLabel()
        ))
    }
    func duelTotalVotesLabel() -> String {
        let di = currentDuelPosition
        let base = duels[di].baseVotes
        let total = base[0] + base[1] + (duelVotes[di] != nil ? 1 : 0)
        return L10n.format("%1$@ votos", String(describing: Logic.fmt(total)))
    }
    func duelResultNote() -> String? {
        let di = currentDuelPosition
        guard let ch = duelVotes[di] else { return nil }
        let base = duels[di].baseVotes
        let total = base[0] + base[1] + 1
        let frac = Double(base[ch] + 1) / Double(total)
        return frac >= 0.5 ? L10n.text("Você está com a maioria") : L10n.text("Você está com a minoria. Defenda nos comentários.")
    }

    func weeklyPollTotalLabel() -> String {
        let total = StaticContent.weeklyDebateBase.reduce(0, +) + (pollVote != nil ? 1 : 0)
        return pollVote == nil ? L10n.format("%1$@ votos · vote pra ver o resultado", String(describing: Logic.fmt(total))) : L10n.format("%1$@ votos · você votou", String(describing: Logic.fmt(total)))
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
        syncWidgetData()
    }

    // MARK: - Obra / Personagem / Evento

    func logActionLabel(for item: Item) -> String {
        if isSeen(item.id) { return L10n.text("Registrar de novo") }
        return ["Personagem", "Evento"].contains(item.type) ? L10n.text("Avaliar") : L10n.text("Registrar")
    }

    func canonInfo(for item: Item) -> (status: String, note: String) {
        if let c = canonStatus[item.id] { return (c.status, c.note) }
        return ("Cânone", L10n.format("Faz parte da continuidade principal (%1$@).", String(describing: item.canon)))
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
        if catalogAPI != nil { return u.total > 0 ? min(100, count * 100 / u.total) : 0 }
        return min(99, u.base + count)
    }

    func universeStats(_ uniID: String) -> [(count: String, label: String)] {
        guard let u = universesByID[uniID] else { return [] }
        return [(Logic.fmt(u.total), L10n.text("Itens no cânone")), (Logic.fmt(u.members), L10n.text("Membros"))] + (showsDemoFeatures ? [(Logic.fmt(u.live), L10n.text("Ativos agora"))] : [])
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
            if fr.count == 1 { label = L10n.format("%1$@ já passou por aqui", String(describing: (fr[0].name.components(separatedBy: " ").first ?? fr[0].name))) }
            else if fr.count > 1 { label = L10n.format("%1$@ amigos já passaram por aqui", String(describing: fr.count)) }
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
            if usesRemoteActivity {
                guard let review = reviews.first(where: { $0.user == u.id && $0.item == item.id && $0.rating > 0 }) else { return nil }
                return (u, review.rating)
            }
            guard let r = Logic.friendRating(friend: u.id, item: item, reviews: reviews) else { return nil }
            return (u, r)
        }
    }
    func friendAvgLabel(for item: Item) -> String? {
        let fr = friendRatings(for: item)
        guard !fr.isEmpty else { return nil }
        let avg = fr.reduce(0.0) { $0 + $1.rating } / Double(fr.count)
        return "★ " + L10n.decimal(avg)
    }

    func homeFeed(limit: Int = 8) -> [Review] {
        if let social { return social.feed }
        return reviews.filter { follows.contains($0.user) || $0.user == meID }.prefix(limit).map { $0 }
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
        if usesRemoteCatalog {
            let count = item.logCount ?? 0
            return count == 0 ? L10n.text("Faça o primeiro registro") : L10n.format("diary.recordCount", count)
        }
        let n = friendRatings(for: item).count
        if n > 0 { return L10n.format("friends.logged", n) }
        return L10n.format("%1$@ esta semana", String(describing: Logic.fmt(Logic.logCount(item))))
    }

    var homeDiscoveryItems: [Item] {
        if usesRemoteCatalog {
            return Array(items.lazy.filter { !["Personagem", "Evento"].contains($0.type) }.prefix(8))
        }
        return StaticContent.trendingItemIDs.compactMap { item($0) }
    }

    var homeSuggestedPeople: [User] {
        if let people { return people.suggestions }
        guard !usesAccountAPI else { return [] }
        return StaticContent.suggestionUserIDs.compactMap { user($0) }.filter { !isFollowing($0.id) }
    }

    var homeEmptyFeedMessage: String {
        if social != nil { return L10n.text("Ainda não há reviews públicas das pessoas que você segue. Explore os loristas ou registre uma obra.") }
        if usesRemoteActivity {
            if !diary.isEmpty { return L10n.text("Seus registros estão no diário. Adicione uma nota ou review para aparecer aqui.") }
            return L10n.text("Seu espaço começa com uma obra. Explore o catálogo e faça seu primeiro registro.")
        }
        return homeSuggestedPeople.isEmpty
            ? L10n.text("Ainda não há reviews por aqui. Que tal registrar uma obra?")
            : L10n.text("Seu feed ganha vida quando você segue gente. Comece pelos loristas abaixo.")
    }

    func review(_ id: String) -> Review? { social?.reviews[id] ?? reviews.first { $0.id == id } }

    // MARK: - Busca

    func searchResults(query: String, filter: SearchFilter, limit: Int = 40) -> (rows: [SearchResultRow], totalCount: Int) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleLimit = max(0, limit)
        let searchLocale = Locale(identifier: L10n.language())
        var rows: [SearchResultRow] = []
        var totalCount = 0
        func matches(_ value: String) -> Bool {
            q.isEmpty || value.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], locale: searchLocale) != nil
        }

        if filter != .people {
            var filtered = items.filter { it in
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
                return matches(it.title + " " + uniName)
            }
            if !usesRemoteCatalog { filtered.sort { Logic.logCount($0) > Logic.logCount($1) } }

            totalCount += filtered.count
            rows.append(contentsOf: filtered.prefix(visibleLimit).map { it in
                let uni = universesByID[it.uni]!
                let p = Logic.posterColors(item: it, universe: uni)
                let isCircular = it.type == "Personagem"
                let meta = usesRemoteCatalog
                    ? "\(uni.name) · \(it.year) · \(it.canon)"
                    : L10n.format("%1$@ · %2$@ · ★ %3$@ · %4$@ registros", String(describing: uni.name), String(describing: it.year), String(describing: L10n.decimal(it.avg)), String(describing: Logic.fmt(Logic.logCount(it))))
                return SearchResultRow(id: it.id, title: it.title, meta: meta, typeLabel: L10n.text(it.type), pillBG: uni.color, pillFG: uni.inkColor, posterBG: p.bg, posterFG: p.fg, initials: "", isCircular: isCircular, route: .item(it.id))
            })
        }

        if let people, (filter == .people || (filter == .all && !q.isEmpty)), people.searchQuery == q {
            let found = people.searchIDs.compactMap { people.profiles[$0]?.user }
            totalCount += found.count
            rows.append(contentsOf: found.prefix(max(0, visibleLimit - rows.count)).map { u in
                SearchResultRow(id: "person:" + u.id, title: u.name, meta: "\(u.handle) · \(u.bio)", typeLabel: isFollowing(u.id) ? L10n.text("Seguindo") : L10n.text("Pessoa"), pillBG: MV.C.card, pillFG: MV.C.ink, posterBG: Color(hex: u.avatarColor), posterFG: Logic.inkOn(hex: u.avatarColor), initials: Logic.initials(u.name), isCircular: true, route: .user(u.id))
            })
        } else if !usesAccountAPI && (filter == .all || filter == .people) {
            let peopleFiltered = users.filter { u in
                guard u.id != meID else { return false }
                let isMatch = matches(u.name + " " + u.handle)
                if filter == .people { return isMatch }
                return !q.isEmpty && isMatch
            }
            totalCount += peopleFiltered.count
            rows.append(contentsOf: peopleFiltered.prefix(max(0, visibleLimit - rows.count)).map { u in
                SearchResultRow(id: u.id, title: u.name, meta: "\(u.handle) · \(u.bio)", typeLabel: follows.contains(u.id) ? L10n.text("Seguindo") : L10n.text("Pessoa"), pillBG: MV.C.card, pillFG: MV.C.ink, posterBG: Color(hex: u.avatarColor), posterFG: Logic.inkOn(hex: u.avatarColor), initials: Logic.initials(u.name), isCircular: true, route: .user(u.id))
            })
        }

        return (rows, totalCount)
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
        let u = user(userID)!
        if !isMe, let person = people?.profiles[userID] {
            return ProfileData(user: u, isMe: false,
                stats: [(Logic.fmt(person.logCount), L10n.text("Registros")), (Logic.fmt(person.followerCount), L10n.text("Seguidores")), (Logic.fmt(person.followingCount), L10n.text("Seguindo"))],
                progress: [], favorites: [], recentReviews: [], compatPercent: nil, compatLine: nil,
                compatByUniverse: nil, agreeLine: nil, disagreeLine: nil, badges: [])
        }
        let sd = Logic.seed(userID)
        let myRevs = reviews.filter { $0.user == userID }

        func pctFor(_ k: String) -> Int {
            if isMe { return universePercent(k) }
            let base = 10 + Int(Logic.seed(userID + k) % 85)
            return u.badgeUniverse == k ? max(base, 62) : base
        }

        let stats: [(String, String)]
        if isMe {
            stats = [("\(diary.count + (activityAPI == nil ? 318 : 0))", L10n.text("Registros")), (people?.state.map { Logic.fmt($0.followerCount) } ?? (activityAPI == nil ? "312" : Logic.fmt(activityFollowerCount)), L10n.text("Seguidores")), ("\(usesRemotePeople || activityAPI != nil ? friendsCount : friendsList.count)", L10n.text("Seguindo"))]
        } else {
            let followers = (u.followers ?? (200 + Int(sd % 700))) + (follows.contains(userID) ? 1 : 0)
            stats = [("\(120 + Int(sd % 600))", L10n.text("Registros")), (Logic.fmt(followers), L10n.text("Seguidores")), ("\(40 + Int(sd % 200))", L10n.text("Seguindo"))]
        }

        let progress = universes.map { ($0, pctFor($0.id)) }
        let favIDs: [String]
        if isMe, let library {
            favIDs = Array(library.favoriteIDs.prefix(4))
        } else if isMe && usesRemoteActivity {
            // A revisit is still one favorite; the latest log owns its liked state.
            var seen = Set<String>()
            favIDs = Array(diary.filter { seen.insert($0.itemId).inserted && $0.liked }.prefix(4).map(\.itemId))
        } else {
            favIDs = isMe ? StaticContent.myFavoriteItemIDs : Array(Set(myRevs.map(\.item)).prefix(4))
        }
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
            compatLine = cp > 78 ? L10n.text("Almas gêmeas de cânone.") : (cp > 62 ? L10n.text("Gostos parecidos, brigas saudáveis.") : L10n.text("Discordam bastante. Rende bons debates."))
            compatByUniverse = universes.map { ($0, 30 + Int(Logic.seed(userID + $0.id + "c") % 68)) }
            let agreeWork = StaticContent.compatAgreeWorks[Int(sd) % StaticContent.compatAgreeWorks.count]
            let agreePerson = StaticContent.compatAgreePeople[Int(sd) % StaticContent.compatAgreePeople.count]
            agreeLine = "\(agreeWork), \(agreePerson)"
            disagreeLine = StaticContent.compatDisagreeWorks[Int(sd >> 2) % StaticContent.compatDisagreeWorks.count]
        }

        let badgeUniverses = ["marvel", "dc"].compactMap { universesByID[$0] } + universes.filter { !["marvel", "dc"].contains($0.id) }
        let badges = badgeUniverses.map { universe -> BadgeProgress in
            let pct = pctFor(universe.id)
            return BadgeProgress(universe: universe, achieved: pct >= 50, remainingPct: max(0, 50 - pct))
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
        // The current Wrapped prototype represents September 2026 only.
        let calendar = Calendar(identifier: .gregorian)
        let sep = diary.filter {
            let date = calendar.dateComponents([.year, .month], from: $0.loggedAt)
            return date.year == 2026 && date.month == 9
        }
        var byUniverse: [String: Int] = [:]
        for d in sep {
            guard let it = itemsByID[d.itemId] else { continue }
            byUniverse[it.uni, default: 0] += 1
        }
        let topUni = byUniverse.max { $0.value < $1.value }?.key ?? "marvel"
        let topDiary = sep.max { $0.rating < $1.rating }
        let topItem = topDiary.flatMap { itemsByID[$0.itemId] } ?? itemsByID["m-civil"]
        let mostLiked = reviews.filter { $0.user == meID }.max { reviewLikeCount($0) < reviewLikeCount($1) }
        let hours = sep.reduce(0.0) { total, d in
            total + (itemsByID[d.itemId].map { Logic.loreHours($0.type) } ?? 1)
        }
        // The catalog gate guarantees at least one universe; the old default may be archived.
        let u = universesByID[topUni] ?? universes[0]
        return WrappedData(
            logCount: sep.count,
            deltaLabel: L10n.format("+%1$@ que agosto", String(describing: max(1, sep.count - 4))),
            hours: Int(hours.rounded()),
            hoursNote: L10n.format("≈ %1$@ dias em outras realidades", String(describing: max(1, Int((hours / 24).rounded())))),
            universe: u,
            universeNote: L10n.format("%1$@ registros · %2$@%% do cânone visto", String(describing: byUniverse[topUni] ?? 0), String(describing: universePercent(topUni))),
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

    func openLogBlank() { guard !isSavingLog else { return }; logSaveError = nil; logDraft = LogDraft() }
    func openLog(for itemID: String) {
        guard !isSavingLog else { return }
        logSaveError = nil
        let mine = myDiaryEntry(for: itemID)
        logDraft = LogDraft(itemID: itemID, rating: mine?.rating ?? 0, liked: mine?.liked ?? false, rewatch: isSeen(itemID), spoiler: false, text: "")
    }
    func closeLog() { guard !isSavingLog else { return }; logDraft = nil; logSaveError = nil }

    func setLogItem(_ itemID: String) {
        guard !isSavingLog, var d = logDraft else { return }
        d.itemID = itemID
        d.rewatch = isSeen(itemID)
        logDraft = d
    }

    /// Repeated taps cycle through full star, half star and no rating.
    func setLogRating(_ n: Int) {
        guard !isSavingLog, (1...5).contains(n), var d = logDraft else { return }
        d.rating = d.rating == Double(n) ? Double(n) - 0.5 : (d.rating == Double(n) - 0.5 ? 0 : Double(n))
        logDraft = d
    }

    func saveLog(at date: Date = .now) {
        guard !isSavingLog else { return }
        if let activityAPI { saveRemoteLog(using: activityAPI, at: date); return }
        guard let d = logDraft, let itemID = d.itemID, let item = itemsByID[itemID] else { return }
        let entry = DiaryEntry(itemId: itemID, loggedAt: date, rating: d.rating, liked: d.liked, rewatch: d.rewatch)
        diary.insert(entry, at: 0)
        setSeen(itemID, seen: true)

        let trimmed = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var newReview: Review?
        if !trimmed.isEmpty || d.rating > 0 {
            let text = trimmed.isEmpty ? L10n.format("%1$@ hoje.", String(describing: Logic.verb(item.type))) : trimmed
            let review = Review(id: "r-\(UUID().uuidString.prefix(8))", user: meID, item: itemID, rating: d.rating, text: text, spoiler: d.spoiler, likes: 0, when: L10n.text("agora"), comments: [])
            reviews.insert(review, at: 0)
            newReview = review
        }
        logDraft = nil
        showToast(L10n.text("Publicado no feed do seu pessoal"))

        if shieldAdvanceAutomatically, let idx = timelineIndex(for: item) {
            advanceShieldPoint(universeID: item.uni, to: idx)
        }

        let repository = self.repository
        Task {
            try? await repository.addDiaryEntry(entry)
            if let newReview { try? await repository.publishReview(newReview) }
        }
    }

    private func saveRemoteLog(using api: any ActivityAPI, at date: Date) {
        guard var draft = logDraft, let itemID = draft.itemID, let item = itemsByID[itemID] else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.count <= 5000 else { logSaveError = ActivityError.tooLong.localizedDescription; return }
        draft.loggedAt = draft.loggedAt ?? date
        logDraft = draft
        let input = SaveLogInput(itemId: itemID, loggedAt: draft.loggedAt!, rating: draft.rating,
                                 liked: draft.liked, rewatch: draft.rewatch, spoiler: draft.spoiler, text: text)
        logSaveError = nil
        isSavingLog = true
        activityRevision += 1
        activityRefreshError = nil
        Task { @MainActor [self] in
            defer { isSavingLog = false }
            do {
                let snapshot = try await api.saveLog(id: draft.id, input: input)
                try snapshot.validate(for: meID)
                guard let confirmed = snapshot.entries.first(where: { $0.id == draft.id }),
                      confirmed.itemId == input.itemId, confirmed.rating == input.rating,
                      confirmed.liked == input.liked, confirmed.rewatch == input.rewatch,
                      abs(confirmed.loggedAt.timeIntervalSince(input.loggedAt)) < 1 else { throw AuthError.apiUnavailable }
                applyActivity(snapshot)
                social?.invalidateFeed()
                if let social { Task { await social.loadFeed() } }
                logDraft = nil
                showToast(L10n.text("Registro salvo no diário."))
                if shieldAdvanceAutomatically, let idx = timelineIndex(for: item) { advanceShieldPoint(universeID: item.uni, to: idx) }
                syncWidgetData()
            } catch {
                // A rejected future date was never committed. Allow a retry after
                // the device clock is corrected, preserving the UUID and review.
                if error as? ActivityError == .invalidDate { logDraft?.loggedAt = nil }
                logSaveError = error.localizedDescription
            }
        }
    }

    /// Resposta na thread da review (campo de resposta da Tela 7). `quote` vem de "Citar"
    /// no card segurado (recurso 5h).
    func postComment(reviewID: String, text: String, quote: (author: String, text: String)? = nil) {
        if isRemoteReview(reviewID) { showToast(L10n.text("Reações e comentários estarão disponíveis em breve.")); return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = reviews.firstIndex(where: { $0.id == reviewID }) else { return }
        let comment = Comment(user: meID, text: trimmed, likes: 0, when: L10n.text("agora"), quotedAuthor: quote?.author, quotedText: quote?.text)
        reviews[idx].comments.append(comment)
        let authorID = reviews[idx].user
        showToast(authorID == meID ? L10n.text("Resposta publicada") : L10n.format("%1$@ vai ser notificado", String(describing: usersByID[authorID]?.name ?? "")))
        let repository = self.repository
        Task { try? await repository.postComment(reviewID: reviewID, comment: comment) }
    }

    // MARK: - Onboarding

    var onboardingStepCount: Int { usesAccountAPI && onboardingCandidates.isEmpty ? 2 : 3 }

    var onboardingSelectedFollowCount: Int {
        usesAccountAPI ? follows.intersection(onboardingCandidates.map(\.id)).count : friendsCount
    }

    var canAdvanceOnboarding: Bool {
        guard !onboardingTransitioning else { return false }
        switch onboardingPhase {
        case .step1: return !onboardingUniverses.isEmpty
        case .step2: return true
        case .step3: return onboardingSelectedFollowCount >= minimumOnboardingFollows
        case .loading: return false
        }
    }

    @discardableResult
    func toggleOnboardingUniverse(_ id: String) -> Bool {
        guard !onboardingTransitioning else { return false }
        let turningOn = !onboardingUniverses.contains(id)
        if turningOn { onboardingUniverses.insert(id) } else { onboardingUniverses.remove(id) }
        scheduleOnboardingSave()
        return turningOn
    }

    func onboardingConsumablePicks() -> [Item] {
        Array(items.filter { onboardingUniverses.contains($0.uni) && $0.type != "Personagem" }.prefix(15))
    }

    func onboardingPeopleSorted() -> [User] {
        if accountAPI != nil { return onboardingCandidates }
        return users.filter { $0.id != meID }.sorted { a, b in
            let aPri = onboardingUniverses.contains(a.badgeUniverse) ? 1 : 0
            let bPri = onboardingUniverses.contains(b.badgeUniverse) ? 1 : 0
            if aPri != bPri { return aPri > bPri }
            return Logic.compat(a.id) > Logic.compat(b.id)
        }
    }

    func advanceOnboarding() {
        if accountAPI != nil { transitionRemoteOnboarding(back: false); return }
        switch onboardingPhase {
        case .step1: onboardingPhase = .step2
        case .step2: onboardingPhase = .step3
        case .step3: finishOnboardingLoading()
        case .loading: break
        }
    }
    func backOnboarding() {
        if accountAPI != nil { transitionRemoteOnboarding(back: true); return }
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
            self.showToast(L10n.text("Feed pronto. Bem-vindo ao Multiverse."))
        }
    }

    // MARK: - Account API onboarding

    func reloadAccount() async {
        guard !isLoading else { return }
        onboardingDebounce?.cancel()
        _ = try? await onboardingSaveQueue?.value
        accountLoadError = nil
        activityLoadError = nil
        onboardingError = nil
        isLoading = true
        if catalogLoadError != nil {
            await bootstrap()
            return
        }
        do {
            if let snapshot = try await catalogAPI?.fetchCatalog() {
                try snapshot.validate()
                applyCatalog(snapshot)
            }
        } catch is CancellationError {
            return
        } catch {
            catalogIssue = error as? CatalogError ?? .unavailable
            isLoading = false
            return
        }
        do { try await loadRemoteAccount() }
        catch { accountLoadError = error.localizedDescription }
        if accountLoadError == nil { await loadRemoteActivity() }
        isLoading = false
        syncWidgetData()
    }

    private func loadRemoteAccount() async throws {
        guard let accountAPI else { return }
        let account = try await accountAPI.fetchAccount()
        guard let profile = account.profile, profile.userID == meID else { throw AuthError.profileIncomplete }
        let suggestions = account.onboarding.completed
            ? FollowSuggestions(users: [], minimumFollows: 0)
            : try await accountAPI.suggestions()
        try applyOnboardingSuggestions(suggestions)
        let me = User(id: profile.userID, name: profile.displayName, handle: "@" + profile.username,
                      avatarColor: profile.avatarColor, bio: profile.bio, followers: nil, badgeUniverse: "")
        usersByID[meID] = me
        users.removeAll { $0.id == meID }; users.append(me)
        let progress = account.onboarding
        remoteVersion = progress.version
        onboardingUniverses = Set(progress.universeIDs).intersection(universes.map(\.id))
        if !progress.completed {
            let seen = Set(progress.seenItemIDs)
            for item in items where item.type != "Personagem" { checks[item.id] = seen.contains(item.id) }
        } else {
            for id in progress.seenItemIDs { checks[id] = true }
        }
        follows = Set(progress.followedUserIDs)
        onboardingPhase = progress.step == 1 ? .step1 : (progress.step == 2 ? .step2 : .step3)
        isOnboarded = progress.completed
        if !isOnboarded && onboardingUniverses.isEmpty { onboardingPhase = .step1 }
        // People may have left since the draft was saved; don't strand the last step.
        if !isOnboarded && onboardingPhase == .step3 && onboardingCandidates.isEmpty {
            onboardingPhase = .step2
        }
    }

    private func applyOnboardingSuggestions(_ suggestions: FollowSuggestions) throws {
        try suggestions.validate(for: meID)
        onboardingCandidates = suggestions.users.map {
            User(id: $0.userID, name: $0.displayName, handle: "@" + $0.username,
                 avatarColor: $0.avatarColor, bio: $0.bio, followers: nil, badgeUniverse: "")
        }
        minimumOnboardingFollows = suggestions.minimumFollows
        for user in onboardingCandidates {
            usersByID[user.id] = user
            users.removeAll { $0.id == user.id }
            users.append(user)
        }
    }

    private func refreshOnboardingSuggestions() async throws {
        guard let accountAPI else { return }
        let suggestions = try await accountAPI.suggestions()
        try Task.checkCancellation()
        try applyOnboardingSuggestions(suggestions)
        follows.formIntersection(onboardingCandidates.map(\.id))
    }

    func refreshOnboardingPeople() async {
        guard usesAccountAPI, !isOnboarded, !onboardingTransitioning else { return }
        onboardingTransitioning = true
        onboardingDebounce?.cancel()
        defer { onboardingTransitioning = false }
        _ = try? await onboardingSaveQueue?.value
        do {
            try await refreshOnboardingSuggestions()
            if onboardingCandidates.isEmpty && onboardingPhase == .step3 { onboardingPhase = .step2 }
            onboardingError = nil
        } catch is CancellationError { return
        } catch { onboardingError = error.localizedDescription }
    }

    private func onboardingSnapshot(step: Int? = nil, completed: Bool = false) -> OnboardingState {
        let currentStep = onboardingPhase == .step1 ? 1 : (onboardingPhase == .step2 ? 2 : 3)
        return OnboardingState(universeIDs: onboardingUniverses.sorted(),
                               seenItemIDs: items.filter { $0.type != "Personagem" && isSeen($0.id) }.map(\.id).sorted(),
                               followedUserIDs: follows.sorted(), step: step ?? currentStep,
                               completed: completed, version: remoteVersion)
    }

    private func enqueueOnboardingSave(_ snapshot: OnboardingState) -> Task<OnboardingState, Error> {
        let previous = onboardingSaveQueue
        let task = Task { @MainActor [self] in
            _ = try? await previous?.value
            guard let accountAPI else { return snapshot }
            var payload = snapshot
            payload.version = remoteVersion
            let saved = try await accountAPI.saveOnboarding(payload)
            remoteVersion = saved.version
            return saved
        }
        onboardingSaveQueue = task
        return task
    }

    private func scheduleOnboardingSave() {
        guard accountAPI != nil, !isOnboarded, !onboardingTransitioning else { return }
        onboardingDebounce?.cancel()
        onboardingDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            do { _ = try await self.enqueueOnboardingSave(self.onboardingSnapshot()).value }
            catch { self.onboardingError = error.localizedDescription }
        }
    }

    private func transitionRemoteOnboarding(back: Bool) {
        guard !onboardingTransitioning else { return }
        onboardingTransitioning = true
        onboardingDebounce?.cancel()
        Task { [self] in
            defer { onboardingTransitioning = false }
            _ = try? await onboardingSaveQueue?.value
            let step = onboardingPhase == .step1 ? 1 : (onboardingPhase == .step2 ? 2 : 3)
            do {
                if !back && step >= 2 {
                    try await refreshOnboardingSuggestions()
                    if step == 3 && onboardingSelectedFollowCount < minimumOnboardingFollows {
                        onboardingError = nil
                        showToast(L10n.text("As sugestões mudaram. Confira os loristas disponíveis para continuar."))
                        return
                    }
                    if onboardingCandidates.isEmpty { onboardingPhase = .step2 }
                }
                let finish = !back && (step == 3 || (step == 2 && onboardingCandidates.isEmpty))
                let next = back ? max(1, step - 1) : min(3, step + 1)
                _ = try await enqueueOnboardingSave(onboardingSnapshot(step: next, completed: finish)).value
                onboardingError = nil
                if finish {
                    isOnboarded = true
                    tab = .home
                    homePath = []
                    showToast(L10n.text("Tudo pronto para explorar. Bem-vindo ao Multiverse."))
                } else { onboardingPhase = next == 1 ? .step1 : (next == 2 ? .step2 : .step3) }
            } catch is CancellationError { return
            } catch {
                if error as? AuthError == .suggestionsChanged {
                    do {
                        try await refreshOnboardingSuggestions()
                        onboardingPhase = onboardingCandidates.isEmpty ? .step2 : .step3
                        onboardingError = nil
                        showToast(L10n.text("As sugestões mudaram. Confira os loristas disponíveis para continuar."))
                    } catch { onboardingError = error.localizedDescription }
                } else { onboardingError = error.localizedDescription }
            }
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
        guard showsDemoFeatures || !route.isDemonstration else { return }
        switch tab {
        case .library: libraryPath.append(route)
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .clubs: clubsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Trocar de aba preserva a pilha de cada aba; tocar na aba já ativa volta pro topo.
    func goToTab(_ newTab: AppTab) {
        if tab == newTab {
            switch newTab {
            case .home: homePath = []
            case .search: searchPath = []
            case .library: libraryPath = []
            case .clubs: clubsPath = []
            case .profile: profilePath = []
            }
        }
        tab = newTab
    }

    /// Abre a central; somente ações confirmadas de leitura alteram o contador.
    func openNotifications() {
        push(.notifications)
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

    // MARK: - Escudo de spoiler

    /// `true` quando o item está à frente do seu ponto na timeline do próprio universo.
    func isAheadOfShield(_ item: Item) -> Bool {
        guard let idx = timelineIndex(for: item) else { return false }
        return idx > (shieldPoints[item.uni] ?? -1)
    }

    func isShieldedReview(_ review: Review) -> Bool {
        guard showsDemoFeatures else { return false }
        guard let item = itemsByID[review.item], isAheadOfShield(item) else { return false }
        return !revealedSpoilers.contains(review.id)
    }

    /// Mesma lógica do escudo, aplicada a uma carta de obra numa DM/sala.
    /// "O escudo de spoiler deve funcionar em DMs, cartas, salas e chat ao vivo."
    func isShieldedMessage(_ message: Message) -> Bool {
        guard let itemID = message.itemID, let item = itemsByID[itemID], isAheadOfShield(item) else { return false }
        return !revealedSpoilers.contains(message.id)
    }

    /// Total de reviews escondidas pelo escudo agora — usado no banner da Home.
    var shieldHiddenCount: Int { reviews.filter { isShieldedReview($0) }.count }

    var isShieldActive: Bool { !shieldPoints.isEmpty }

    /// "Você está em Fase 3 (Marvel) e Pré-Crise (DC)." — texto do banner da Home.
    func shieldStatusLine() -> String? {
        let segments = universes.compactMap { u -> String? in
            guard let idx = shieldPoints[u.id], let entries = timelines[u.id], entries.indices.contains(idx) else { return nil }
            let era = entries[idx].era.components(separatedBy: " · ").first ?? entries[idx].era
            return "\(era) (\(u.name))"
        }
        guard !segments.isEmpty else { return nil }
        return L10n.text("Você está em ") + segments.joined(separator: L10n.text(" e ")) + "."
    }

    /// "3 anos à frente de onde você está" — tenta comparar o número no rótulo da era
    /// ("Ano 27", "Ano 30"); cai pra contagem de marcos na timeline quando não dá.
    func shieldDistanceLabel(for item: Item) -> String {
        guard let idx = timelineIndex(for: item), let entries = timelines[item.uni] else {
            return L10n.text("à frente de onde você está")
        }
        let point = shieldPoints[item.uni] ?? -1
        func yearNumber(_ era: String) -> Int? {
            guard let range = era.range(of: #"\d+"#, options: .regularExpression) else { return nil }
            return Int(era[range])
        }
        let targetYear = yearNumber(entries[idx].era)
        let pointYear = (point >= 0 && point < entries.count) ? yearNumber(entries[point].era) : nil
        if let t = targetYear, let p = pointYear, t > p {
            return L10n.format("shield.yearsAhead", t - p)
        }
        let steps = idx - point
        return L10n.format("shield.milestonesAhead", steps)
    }

    func revealShielded(reviewID: String) {
        revealedSpoilers.insert(reviewID)
        let repository = self.repository
        Task { try? await repository.setSpoilerRevealed(reviewID: reviewID) }
    }

    /// Botão "Já vi isso" do card do escudo: marca o item como visto e avança o ponto até ele.
    func shieldMarkSeen(_ itemID: String) {
        setSeen(itemID, seen: true)
        if let item = itemsByID[itemID], let idx = timelineIndex(for: item) {
            advanceShieldPoint(universeID: item.uni, to: idx)
        }
    }

    private func advanceShieldPoint(universeID: String, to index: Int) {
        guard index > (shieldPoints[universeID] ?? -1) else { return }
        shieldPoints[universeID] = index
        let repository = self.repository
        Task { try? await repository.setShieldPoint(universeID: universeID, timelineIndex: index) }
    }

    func setShieldPoint(universeID: String, index: Int) {
        shieldPoints[universeID] = index
        let repository = self.repository
        Task { try? await repository.setShieldPoint(universeID: universeID, timelineIndex: index) }
    }

    func setShieldAdvanceAutomatically(_ enabled: Bool) {
        shieldAdvanceAutomatically = enabled
        let repository = self.repository
        Task { try? await repository.setShieldAdvanceAutomatically(enabled) }
    }

    // MARK: - Clubes de maratona

    func club(_ id: String) -> Club? { clubs.first { $0.id == id } }
    func currentClubWeek(_ club: Club) -> ClubWeek? { club.weeks.first { $0.week == club.currentWeek } }

    func clubUnitsCompleted(clubID: String, userID: String) -> Int {
        clubMemberUnits["\(clubID)|\(userID)"] ?? 0
    }

    func clubMemberProgressLabel(clubID: String, userID: String, week: ClubWeek) -> String {
        let units = clubUnitsCompleted(clubID: clubID, userID: userID)
        if week.totalUnits <= 1 { return units > 0 ? L10n.text("Terminou ✓") : L10n.text("Não começou") }
        if units >= week.totalUnits { return L10n.text("Terminou ✓") }
        return "\(week.unitLabel) \(units)"
    }

    func setMyClubUnits(clubID: String, units: Int) {
        clubMemberUnits["\(clubID)|\(meID)"] = units
        let repository = self.repository
        Task { try? await repository.setClubUnitsCompleted(clubID: clubID, units: units) }
    }

    func clubMessagesFor(clubID: String, week: Int, segment: String) -> [ClubMessage] {
        clubMessages.filter { $0.clubID == clubID && $0.week == week && $0.segment == segment }
    }

    func clubMessageCount(clubID: String, week: Int) -> Int {
        clubMessages.filter { $0.clubID == clubID && $0.week == week }.count
    }

    func isClubMessageHidden(_ message: ClubMessage, clubID: String) -> Bool {
        message.aboutUnit > clubUnitsCompleted(clubID: clubID, userID: meID) && !revealedSpoilers.contains("club:\(message.id)")
    }

    func revealClubMessage(_ messageID: String) { revealedSpoilers.insert("club:\(messageID)") }

    func isClubMessageHearted(_ id: String) -> Bool { heartedClubMessages.contains(id) }

    func toggleClubMessageHeart(_ id: String) {
        let turningOn = !heartedClubMessages.contains(id)
        if turningOn { heartedClubMessages.insert(id) } else { heartedClubMessages.remove(id) }
        if let idx = clubMessages.firstIndex(where: { $0.id == id }) { clubMessages[idx].hearts += turningOn ? 1 : -1 }
        let repository = self.repository
        Task { try? await repository.setClubMessageHearted(messageID: id, hearted: turningOn) }
    }

    func powClubMessage(_ id: String) {
        guard !powedClubMessages.contains(id) else { return }
        powedClubMessages.insert(id)
        if let idx = clubMessages.firstIndex(where: { $0.id == id }) { clubMessages[idx].pows += 1 }
        let repository = self.repository
        Task { try? await repository.addClubMessagePow(messageID: id) }
    }

    func postClubMessage(clubID: String, week: Int, segment: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let myUnits = clubUnitsCompleted(clubID: clubID, userID: meID)
        let message = ClubMessage(id: "cm-\(UUID().uuidString.prefix(8))", clubID: clubID, week: week, segment: segment, userID: meID, text: trimmed, when: L10n.text("agora"), hearts: 0, pows: 0, aboutUnit: myUnits)
        clubMessages.append(message)
        let repository = self.repository
        Task { try? await repository.postClubMessage(message) }
    }

    func pokeLaggingMembers() { showToast(L10n.text("Lembrete enviado pros atrasados do clube.")) }
    func inviteToClub() { showToast(L10n.text("Link de convite copiado.")) }

    // MARK: - Teorias

    func theoriesFiltered(_ filter: TheoryFeedFilter) -> [Theory] {
        switch filter {
        case .open: return theories.filter { $0.status == .open }
        case .confirmed: return theories.filter { $0.status == .confirmed }
        case .refuted: return theories.filter { $0.status == .refuted }
        case .mine: return theories.filter { $0.userID == meID }
        }
    }

    func theoryPercents(_ theory: Theory) -> (plausible: Int, travel: Int) {
        let percents = Logic.pollPercents(base: [theory.plausibleBase, theory.travelBase], chosen: theoryVotes[theory.id])
        return (percents[0], percents[1])
    }

    func theoryTotalVotesLabel(_ theory: Theory) -> String {
        Logic.fmt(theory.plausibleBase + theory.travelBase + (theoryVotes[theory.id] != nil ? 1 : 0))
    }

    func isTheoryVoted(_ theoryID: String) -> Bool { theoryVotes[theoryID] != nil }

    func voteTheory(_ theoryID: String, plausible: Bool) {
        guard theoryVotes[theoryID] == nil else { return }
        let index = plausible ? 0 : 1
        theoryVotes[theoryID] = index
        let repository = self.repository
        Task { try? await repository.submitPollVote(topic: .theory(id: theoryID), optionIndex: index) }
    }

    /// "71% ACERTO" — reputação de quem postou a teoria (fixa pros 3 exemplos, determinística pro resto).
    func theoryAccuracyLabel(_ userID: String) -> String {
        let pct = StaticContent.theoryAccuracy[userID] ?? (49 + Int(Logic.seed(userID + "acc") % 40))
        return L10n.format("%1$@%% ACERTO", String(describing: pct))
    }

    // MARK: - Previsões

    func predictionAnswer(for questionID: String) -> PredictionAnswer? { predictionAnswers[questionID] }

    func submitPredictionChoice(questionID: String, optionIndex: Int) {
        guard predictionAnswers[questionID] == nil else { return }
        predictionAnswers[questionID] = .choice(optionIndex)
        let repository = self.repository
        Task { try? await repository.submitPredictionAnswer(questionID: questionID, answer: .choice(optionIndex)) }
    }

    func submitPredictionSlider(questionID: String, value: Double) {
        predictionAnswers[questionID] = .slider(value)
        let repository = self.repository
        Task { try? await repository.submitPredictionAnswer(questionID: questionID, answer: .slider(value)) }
    }

    func predictionLeague() -> [(user: User, points: Int, isMe: Bool)] {
        var entries = StaticContent.predictionLeague.compactMap { entry -> (User, Int, Bool)? in
            usersByID[entry.userID].map { ($0, entry.points, false) }
        }
        if let me = usersByID[meID] { entries.append((me, predictionPoints, true)) }
        return entries.sorted { $0.1 > $1.1 }
    }

    func isRemoteReview(_ id: String) -> Bool { social != nil && UUID(uuidString: id) != nil }

    func refreshAfterSafetyChange() async {
        people?.invalidateDiscovery()
        await people?.loadHome()
        await social?.loadBlocks()
        await social?.loadFeed()
    }

    // MARK: - Denúncia e moderação

    func submitReport(targetType: String, targetID: String, reason: ReportReason, alsoBlock: Bool) {
        showToast(L10n.text("Denúncia enviada. Revisamos em até 24h."))
        let repository = self.repository
        Task { try? await repository.submitReport(ReportSubmission(targetType: targetType, targetID: targetID, reason: reason, alsoBlock: alsoBlock)) }
    }

    // MARK: - Sugerir correção

    func loadCorrections(for itemID: String) async {
        guard let fetched = try? await repository.fetchCorrectionSuggestions(itemID: itemID) else { return }
        correctionsByItem[itemID] = fetched
    }

    func submitCorrection(itemID: String, changeType: CorrectionChangeType, from: String, to: String, source: String, reasoning: String) {
        let suggestion = CorrectionSuggestion(id: "cs-\(UUID().uuidString.prefix(8))", itemID: itemID, userID: meID, changeType: changeType, fromValue: from, toValue: to, source: source, reasoning: reasoning, approverIDs: [], approvalsNeeded: 3)
        correctionsByItem[itemID, default: []].insert(suggestion, at: 0)
        showToast(L10n.text("Sugestão enviada pra revisão."))
        let repository = self.repository
        Task { try? await repository.submitCorrection(suggestion) }
    }

    // MARK: - Onde assistir

    func loadWatchAvailability(for itemID: String) async {
        guard watchAvailabilityByItem[itemID] == nil else { return }
        guard let fetched = try? await repository.fetchWatchAvailability(itemID: itemID) else { return }
        watchAvailabilityByItem[itemID] = fetched
    }

    // MARK: - Mensagens e cartas

    var friendConversations: [Conversation] { conversations.filter { !$0.isRequest } }
    var requestConversations: [Conversation] { conversations.filter { $0.isRequest } }
    var totalUnreadMessages: Int { directMessages?.unreadCount ?? conversations.reduce(0) { $0 + $1.unreadCount } }

    func messages(with userID: String) -> [Message] { messagesByConversation[userID] ?? [] }

    func loadMessages(with userID: String) async {
        guard let fetched = try? await repository.fetchMessages(conversationID: userID) else { return }
        messagesByConversation[userID] = fetched
    }

    func openConversation(with userID: String) {
        if let idx = conversations.firstIndex(where: { $0.userID == userID }) { conversations[idx].unreadCount = 0 }
        let repository = self.repository
        Task { try? await repository.markConversationRead(userID) }
    }

    func sendMessage(to userID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendMessage(Message(id: "msg-\(UUID().uuidString.prefix(8))", conversationID: userID, senderID: meID, when: L10n.text("agora"), kind: .text, text: trimmed))
    }

    func sendCard(to userIDs: [String], itemID: String, text: String) {
        for userID in userIDs {
            appendMessage(Message(id: "msg-\(UUID().uuidString.prefix(8))", conversationID: userID, senderID: meID, when: L10n.text("agora"), kind: .workCard, text: text.isEmpty ? nil : text, itemID: itemID))
        }
        showToast(userIDs.count == 1 ? L10n.text("Carta enviada") : L10n.format("Carta enviada pra %1$@", String(describing: userIDs.count)))
    }

    func sendDuelChallenge(to userID: String, itemAID: String, itemBID: String, question: String, wager: String, myChoice: Int) {
        let payload = DuelChallengePayload(itemAID: itemAID, itemBID: itemBID, question: question, wager: wager, chooserChoice: myChoice, responderChoice: nil)
        appendMessage(Message(id: "msg-\(UUID().uuidString.prefix(8))", conversationID: userID, senderID: meID, when: L10n.text("agora"), kind: .duelChallenge, duelChallenge: payload))
        showToast(L10n.text("Desafio enviado"))
    }

    func respondToDuelChallenge(messageID: String, in userID: String, choice: Int) {
        guard var list = messagesByConversation[userID], let idx = list.firstIndex(where: { $0.id == messageID }) else { return }
        list[idx].duelChallenge?.responderChoice = choice
        messagesByConversation[userID] = list
        let repository = self.repository
        Task { try? await repository.respondToDuelChallenge(messageID: messageID, choice: choice) }
    }

    private func appendMessage(_ message: Message) {
        messagesByConversation[message.conversationID, default: []].append(message)
        if let idx = conversations.firstIndex(where: { $0.userID == message.conversationID }) {
            conversations[idx].lastPreview = message.text ?? L10n.text("mandou uma carta")
            conversations[idx].lastWhen = L10n.text("agora")
        } else {
            conversations.insert(Conversation(userID: message.conversationID, lastPreview: message.text ?? L10n.text("mandou uma carta"), lastWhen: L10n.text("agora"), unreadCount: 0, isRequest: !follows.contains(message.conversationID)), at: 0)
        }
        let repository = self.repository
        Task { try? await repository.sendMessage(message) }
    }

    // MARK: - Salas por obra

    func room(for itemID: String) -> Room? { rooms.first { $0.itemID == itemID } }
    func roomMessagesFor(itemID: String, segment: Int) -> [RoomMessage] {
        (roomMessages[itemID] ?? []).filter { $0.segmentIndex == segment }
    }

    func loadRoomMessages(itemID: String) async {
        guard let fetched = try? await repository.fetchRoomMessages(itemID: itemID) else { return }
        roomMessages[itemID] = fetched
    }

    func setRoomProgress(itemID: String, segment: Int) {
        roomProgress[itemID] = segment
        let repository = self.repository
        Task { try? await repository.setRoomProgress(itemID: itemID, segmentIndex: segment) }
    }

    func postRoomMessage(itemID: String, segment: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = RoomMessage(id: "rm-\(UUID().uuidString.prefix(8))", itemID: itemID, segmentIndex: segment, userID: meID, text: trimmed, when: L10n.text("agora"))
        roomMessages[itemID, default: []].append(message)
        let repository = self.repository
        Task { try? await repository.postRoomMessage(message) }
    }
}
