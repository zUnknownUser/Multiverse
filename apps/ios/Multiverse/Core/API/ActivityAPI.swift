import Foundation

@MainActor
protocol ActivityAPI: Sendable {
    func fetchActivity() async throws -> ActivitySnapshot
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot
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

    func validate(for userID: String) throws {
        let itemIDs = Set(items.map(\.id))
        let universeIDs = Set(universes.map(\.id))
        guard followerCount >= 0, Set(entries.map(\.id)).count == entries.count,
              Set(reviews.map(\.id)).count == reviews.count,
              itemIDs.count == items.count, universeIDs.count == universes.count,
              items.allSatisfy({ universeIDs.contains($0.uni) }),
              entries.allSatisfy({ itemIDs.contains($0.itemId) && (0...5).contains($0.rating) }),
              reviews.allSatisfy({ $0.user == userID && itemIDs.contains($0.item) }) else {
            throw AuthError.apiUnavailable
        }
    }
}

enum ActivityError: LocalizedError, Equatable {
    case invalidLog, invalidDate, itemUnavailable, tooLong, timedOut
    var errorDescription: String? {
        switch self {
        case .invalidLog: return L10n.text("Confira a nota e os dados do registro. Sua review continua aqui.")
        case .invalidDate: return L10n.text("A data do registro está no futuro. Confira a data do aparelho e tente novamente.")
        case .itemUnavailable: return L10n.text("Esta obra não está disponível para novos registros. Sua review continua aqui; você pode copiá-la antes de sair.")
        case .tooLong: return L10n.text("Sua review pode ter até 5.000 caracteres. Reduza o texto para publicar.")
        case .timedOut: return L10n.text("O servidor demorou a responder. Tente novamente; o mesmo registro não será duplicado.")
        }
    }
}
