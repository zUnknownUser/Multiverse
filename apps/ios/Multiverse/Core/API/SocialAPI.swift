import Foundation

@MainActor protocol SocialAPI: Sendable {
    func fetchFeed(after: String?) async throws -> SocialPage
    func fetchReview(id: String) async throws -> SocialPage
    func fetchPrivacy() async throws -> DiaryPrivacy
    func savePrivacy(publicDiary: Bool) async throws -> DiaryPrivacy
    func fetchBlocks() async throws -> SocialBlocks
    func setBlock(id: String, blocked: Bool) async throws -> BlockReceipt
    func reportReview(id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt
}
struct DiaryPrivacy: Codable, Sendable { let publicDiary: Bool }
struct SocialBlock: Codable, Identifiable, Sendable {
    let id: String
    let handle: String
    let createdAt: Date
    var display: BlockedUser { BlockedUser(id: id, handle: handle, blockedOn: L10n.date(createdAt, template: "d MMM yyyy")) }
}
struct SocialBlocks: Codable, Sendable { let users: [SocialBlock] }
struct BlockReceipt: Codable, Sendable { let userID: String; let blocked: Bool }
struct ReportReceipt: Codable, Sendable { let reported: Bool; let reviewID: String; let blockedUserID: String? }
struct SocialPage: Codable, Sendable {
    let reviews: [ActivityReview]
    let users: [User]
    let items: [Item]
    let universes: [Universe]
    let nextCursor: String?
    func validate() throws {
        let authors = Set(users.map(\.id)), works = Set(items.map(\.id)), worlds = Set(universes.map(\.id))
        guard reviews.count <= 50, Set(reviews.map(\.id)).count == reviews.count,
              authors.count == users.count, works.count == items.count, worlds.count == universes.count,
              items.allSatisfy({ worlds.contains($0.uni) }),
              reviews.allSatisfy({ UUID(uuidString: $0.id) != nil && authors.contains($0.user) && works.contains($0.item) && (0...5).contains($0.rating) }),
              nextCursor == nil || (!reviews.isEmpty && !(nextCursor?.isEmpty ?? true) && (nextCursor?.count ?? 0) <= 300)
        else { throw AuthError.apiUnavailable }
    }
}
enum SocialError: LocalizedError, Equatable {
    case unavailable, invalid, reportLimit, publicationLimit
    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("Esta review não está mais disponível para você. Atualize o feed.")
        case .invalid: return L10n.text("Não foi possível confirmar esta ação. Tente novamente.")
        case .reportLimit: return L10n.text("Você atingiu o limite de denúncias por hoje. Tente novamente mais tarde.")
        case .publicationLimit: return L10n.text("Você publicou muitas reviews nesta hora. Aguarde um pouco; seu rascunho continua aqui.")
        }
    }
}
extension ReportReason {
    var apiValue: String {
        switch self { case .spoiler: "spoiler"; case .offensive: "offensive"; case .spam: "spam"; case .wrongCanon: "wrong_canon"; case .other: "other" }
    }
}
