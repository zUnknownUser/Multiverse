import Foundation

@MainActor
protocol ActivityAPI: Sendable {
    func fetchActivity() async throws -> ActivitySnapshot
    func fetchActivityPage(query: DiaryQuery, after: String?) async throws -> ActivitySnapshot
    func exportActivity() async throws -> ActivitySnapshot
    func fetchReviews(itemID: String?, universeID: String?) async throws -> ActivitySnapshot
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot
    func updateLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot
    func deleteLog(id: UUID) async throws -> DeleteLogReceipt
}

extension ActivityAPI {
    func fetchReviews(itemID: String?, universeID: String?) async throws -> ActivitySnapshot { try await fetchActivity() }
    func fetchActivityPage(query: DiaryQuery, after: String?) async throws -> ActivitySnapshot { try await fetchActivity() }
    func exportActivity() async throws -> ActivitySnapshot { try await fetchActivity() }
}

struct ActivitySummary: Codable, Sendable {
    let total: Int
    let reviewCount: Int
    let averageRating: Double
    let years: [Int]
    let recentReviews: [ActivityReview]
    let latestEntries: [DiaryEntry]
    let buckets: [ActivityBucket]
    let activeDays: [String]
}

struct ActivityBucket: Codable, Sendable {
    let year: Int
    let type: String
    let universe: String
    let count: Int
}

struct SaveLogInput: Codable, Sendable, Equatable {
    let itemId: String
    let loggedAt: Date
    let rating: Double
    let liked: Bool
    let rewatch: Bool
    let spoiler: Bool
    let text: String
}

struct ActivityReview: Codable, Sendable {
    let id: String
    let user: String
    let item: String
    let rating: Double
    let text: String
    let spoiler: Bool
    let createdAt: Date
    /// Private activity links reviews to their exact log; public feed responses omit this field.
    var entryId: UUID? = nil
    var interaction: InteractionSummary? = nil
    var commentCount: Int? = nil

    var display: Review {
        Review(id: id, user: user, item: item, rating: rating, text: text.isEmpty ? L10n.text("Avaliou esta obra.") : text, spoiler: spoiler, likes: 0,
               when: Date.now.timeIntervalSince(createdAt) < 60 ? L10n.text("agora") : L10n.date(createdAt, template: "d MMM yyyy"), comments: [])
    }
}

struct ActivitySnapshot: Codable, Sendable {
    let entries: [DiaryEntry]
    let reviews: [ActivityReview]
    let items: [Item]
    let universes: [Universe]
    let followerCount: Int
    var summary: ActivitySummary? = nil
    var nextCursor: String? = nil

    func validate(for userID: String) throws {
        if let summary {
            guard summary.total >= entries.count, summary.reviewCount >= 0, summary.reviewCount <= summary.total,
                  (0...5).contains(summary.averageRating),
                  summary.latestEntries.count <= summary.total,
                  summary.recentReviews.count <= 4,
                  summary.recentReviews.allSatisfy({ $0.user == userID }),
                  Set(summary.latestEntries.map(\.itemId)).count == summary.latestEntries.count,
                  summary.latestEntries.allSatisfy({ (0...5).contains($0.rating) }),
                  summary.buckets.allSatisfy({ $0.count >= 0 }),
                  nextCursor == nil || !entries.isEmpty else { throw AuthError.apiUnavailable }
        }
        let itemIDs = Set(items.map(\.id))
        let universeIDs = Set(universes.map(\.id))
        let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard followerCount >= 0, entriesByID.count == entries.count,
              Set(reviews.map(\.id)).count == reviews.count,
              itemIDs.count == items.count, universeIDs.count == universes.count,
              items.allSatisfy({ universeIDs.contains($0.uni) }),
              entries.allSatisfy({ itemIDs.contains($0.itemId) && (0...5).contains($0.rating) }),
              Set(reviews.compactMap(\.entryId)).count == reviews.count,
              reviews.allSatisfy({ review in
                  guard let id = review.entryId, let entry = entriesByID[id] else { return false }
                  return review.user == userID && entry.itemId == review.item && entry.rating == review.rating
              }) else {
            throw AuthError.apiUnavailable
        }
    }

    func validateSavedLog(id: UUID, input: SaveLogInput, userID: String) throws {
        try validate(for: userID)
        guard let entry = entries.first(where: { $0.id == id }),
              entry.itemId == input.itemId, entry.rating == input.rating,
              entry.liked == input.liked, entry.rewatch == input.rewatch,
              abs(entry.loggedAt.timeIntervalSince(input.loggedAt)) < 1 else { throw AuthError.apiUnavailable }
        let review = reviews.first { $0.entryId == id }
        if input.rating > 0 || !input.text.isEmpty {
            guard review?.text == input.text, review?.spoiler == input.spoiler else { throw AuthError.apiUnavailable }
        } else if review != nil { throw AuthError.apiUnavailable }
    }
}

struct DeleteLogReceipt: Codable, Sendable {
    let id: UUID
    let state: ActivitySnapshot

    func validate(deleting entry: DiaryEntry, userID: String) throws {
        try state.validate(for: userID)
        guard id == entry.id, !state.entries.contains(where: { $0.id == id }),
              state.items.contains(where: { $0.id == entry.itemId }) else { throw AuthError.apiUnavailable }
    }
}

enum ActivityError: LocalizedError, Equatable {
    case invalidLog, invalidDate, itemUnavailable, tooLong, timedOut, missingLog, deletedLog, itemConflict
    var errorDescription: String? {
        switch self {
        case .invalidLog: return L10n.text("Confira a nota e os dados do registro. Sua review continua aqui.")
        case .invalidDate: return L10n.text("A data do registro está no futuro. Confira a data do aparelho e tente novamente.")
        case .itemUnavailable: return L10n.text("Esta obra não está disponível para novos registros. Sua review continua aqui; você pode copiá-la antes de sair.")
        case .tooLong: return L10n.text("Sua review pode ter até 5.000 caracteres. Reduza o texto para publicar.")
        case .timedOut: return L10n.text("O servidor demorou a responder. Tente novamente; o mesmo registro não será duplicado.")
        case .missingLog: return L10n.text("Este registro não foi encontrado. Atualize o diário e tente novamente.")
        case .deletedLog: return L10n.text("Este registro já foi excluído. Seu texto continua aqui para copiar antes de sair.")
        case .itemConflict: return L10n.text("A obra de um registro existente não pode ser alterada.")
        }
    }
}
