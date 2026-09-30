import Foundation

/// Catálogo estático (equivalente a `sample-data.json`).
struct Catalog: Sendable {
    let universes: [Universe]
    let items: [Item]
    let users: [User]
    let badgeNames: [String: String]
    let connections: [String: [String]]
    let timelines: [String: [TimelineEntry]]
    let readingOrders: [ReadingOrder]
    let lists: [LoreList]
    let genericReviewTexts: [String]
    let canonStatus: [String: CanonInfo]
    let canonStatusColors: [String: StatusColor]
    let duels: [Duel]
    let me: Me
}

/// Alvo polimórfico de uma votação de opção única (o resultado só aparece depois do voto).
enum PollTopic: Hashable, Sendable {
    case weekly
    case essential(itemID: String)
    case canon(itemID: String)
    case duel(index: Int)
    /// Plausível (0) / Viajou (1) — voto numa teoria.
    case theory(id: String)
}

struct PollVotes: Sendable {
    var weekly: Int?
    var essential: [String: Int] = [:]
    var canon: [String: Int] = [:]
    var duel: [Int: Int] = [:]
    var theory: [String: Int] = [:]

    func value(for topic: PollTopic) -> Int? {
        switch topic {
        case .weekly: return weekly
        case .essential(let id): return essential[id]
        case .canon(let id): return canon[id]
        case .duel(let i): return duel[i]
        case .theory(let id): return theory[id]
        }
    }
}

struct ItemToggles: Sendable {
    var seenOverrides: [String: Bool] = [:]
    var wanted: Set<String> = ["w-cata"]
    var liked: Set<String> = []
}

struct ReviewToggles: Sendable {
    var liked: Set<String> = []
    var likedComments: Set<String> = []   // chave "reviewId:index"
    var revealedSpoilers: Set<String> = []
}

struct OrderState: Sendable {
    var upvoted: Set<String> = []
    var following: Set<String> = ["o-azeroth"]
}

// MARK: - Escudo de spoiler

struct ShieldState: Sendable {
    var points: [String: Int] = [:]           // universeID → índice na timeline
    var advanceAutomatically: Bool = true
}

// MARK: - Clubes

struct ClubState: Sendable {
    var memberUnits: [String: Int] = [:]      // chave "clubID|userID" → unidades concluídas na semana
    var heartedMessages: Set<String> = []
    var powedMessages: Set<String> = []
}

// MARK: - Teorias

struct TheoryLoreState: Sendable {
    var points: Int = 0
    var accuracyPercent: Int = 64
}

// MARK: - Previsões

enum PredictionAnswer: Sendable, Equatable {
    case choice(Int)
    case slider(Double)
}

struct PredictionState: Sendable {
    var points: Int = 0
    var answers: [String: PredictionAnswer] = [:]   // questionID → resposta
}

// MARK: - Denúncia

struct ReportSubmission: Sendable {
    let targetType: String
    let targetID: String
    let reason: ReportReason
    let alsoBlock: Bool
}

/// Fonte única de dados e mutações do app. Hoje só existe `MockRepository` (sample-data.json
/// em memória); a fase 2 (Supabase/Firebase, ver README) troca a implementação sem tocar
/// em `AppStore` ou nas Views.
protocol MultiverseRepository: Sendable {
    func loadCatalog() async throws -> Catalog

    // Feed / reviews / comentários
    func fetchReviews() async throws -> [Review]
    func publishReview(_ review: Review) async throws
    func fetchReviewToggles() async throws -> ReviewToggles
    func setReviewLiked(reviewID: String, liked: Bool) async throws
    func postComment(reviewID: String, comment: Comment) async throws
    func setCommentLiked(reviewID: String, commentIndex: Int, liked: Bool) async throws
    func setSpoilerRevealed(reviewID: String) async throws
    func fetchReactions() async throws -> [String: ReactionType]
    func setReaction(reviewID: String, type: ReactionType?) async throws

    // Itens (visto, quero, curtir)
    func fetchItemToggles() async throws -> ItemToggles
    func setItemSeen(itemID: String, seen: Bool) async throws
    func setItemWanted(itemID: String, wanted: Bool) async throws
    func setItemLiked(itemID: String, liked: Bool) async throws

    // Votos (polimórfico: semanal, essencial, cânone, duelo)
    func fetchPollVotes() async throws -> PollVotes
    func submitPollVote(topic: PollTopic, optionIndex: Int) async throws

    // Follows (de pessoas)
    func fetchFollows() async throws -> Set<String>
    func setFollowing(userID: String, following: Bool) async throws

    // Diário
    func fetchDiary() async throws -> [DiaryEntry]
    func addDiaryEntry(_ entry: DiaryEntry) async throws

    // Ordens de leitura (voto ▲ e "seguir ordem")
    func fetchOrderState() async throws -> OrderState
    func setOrderUpvoted(orderID: String, upvoted: Bool) async throws
    func setOrderFollowing(orderID: String, following: Bool) async throws

    // Listas
    func fetchLikedLists() async throws -> Set<String>
    func setListLiked(listID: String, liked: Bool) async throws

    // Escudo de spoiler
    func fetchShieldState() async throws -> ShieldState
    func setShieldPoint(universeID: String, timelineIndex: Int) async throws
    func setShieldAdvanceAutomatically(_ enabled: Bool) async throws

    // Clubes de maratona
    func fetchClubs() async throws -> [Club]
    func fetchClubMessages(clubID: String) async throws -> [ClubMessage]
    func postClubMessage(_ message: ClubMessage) async throws
    func fetchClubState() async throws -> ClubState
    func setClubUnitsCompleted(clubID: String, units: Int) async throws
    func setClubMessageHearted(messageID: String, hearted: Bool) async throws
    func addClubMessagePow(messageID: String) async throws

    // Teorias
    func fetchTheories() async throws -> [Theory]
    func postTheory(_ theory: Theory) async throws
    func fetchTheoryLoreState() async throws -> TheoryLoreState

    // Previsões
    func fetchPredictionEvents() async throws -> [PredictionEvent]
    func fetchPredictionState() async throws -> PredictionState
    func submitPredictionAnswer(questionID: String, answer: PredictionAnswer) async throws

    // Denúncia e moderação
    func submitReport(_ report: ReportSubmission) async throws

    // Sugerir correção
    func fetchCorrectionSuggestions(itemID: String) async throws -> [CorrectionSuggestion]
    func submitCorrection(_ suggestion: CorrectionSuggestion) async throws

    // Onde assistir
    func fetchWatchAvailability(itemID: String) async throws -> WatchAvailability?

    // Mensagens e cartas
    func fetchConversations() async throws -> [Conversation]
    func fetchMessages(conversationID: String) async throws -> [Message]
    func sendMessage(_ message: Message) async throws
    func respondToDuelChallenge(messageID: String, choice: Int) async throws
    func markConversationRead(_ conversationID: String) async throws

    // Salas por obra
    func fetchRooms() async throws -> [Room]
    func fetchRoomMessages(itemID: String) async throws -> [RoomMessage]
    func postRoomMessage(_ message: RoomMessage) async throws
    func fetchRoomProgress() async throws -> [String: Int]
    func setRoomProgress(itemID: String, segmentIndex: Int) async throws

    // Estreia ao vivo
    func fetchLiveEvent() async throws -> LiveEvent?
}
