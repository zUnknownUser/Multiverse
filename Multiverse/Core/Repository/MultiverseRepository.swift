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
}

struct PollVotes: Sendable {
    var weekly: Int?
    var essential: [String: Int] = [:]
    var canon: [String: Int] = [:]
    var duel: [Int: Int] = [:]

    func value(for topic: PollTopic) -> Int? {
        switch topic {
        case .weekly: return weekly
        case .essential(let id): return essential[id]
        case .canon(let id): return canon[id]
        case .duel(let i): return duel[i]
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
}
