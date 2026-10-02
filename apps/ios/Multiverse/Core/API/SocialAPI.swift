import Foundation

@MainActor protocol SocialAPI: Sendable {
    func fetchFeed(after: String?) async throws -> SocialPage
    func fetchReview(id: String) async throws -> SocialPage
    func fetchPrivacy() async throws -> DiaryPrivacy
    func savePrivacy(publicDiary: Bool) async throws -> DiaryPrivacy
    func fetchBlocks() async throws -> SocialBlocks
    func setBlock(id: String, blocked: Bool) async throws -> BlockReceipt
    func reportReview(id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt
    func fetchComments(reviewID: String, after: String?) async throws -> CommentsPage
    func postComment(reviewID: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt
    func setReaction(reviewID: String, commentID: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary
    func saveCommentPermission(_ permission: String) async throws -> DiaryPrivacy
    func reportComment(reviewID: String, id: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt
}
struct DiaryPrivacy: Codable, Sendable { let publicDiary: Bool; var commentPermission: String? = nil }
struct InteractionSummary: Codable, Sendable {
    let id: String
    let likes: Int
    let liked: Bool
    let myReaction: String?
    let reactions: [String: Int]
    func validate(target: String) throws {
        guard id == target, likes >= 0, !liked || likes > 0,
              myReaction == nil || ReactionType(rawValue: myReaction!) != nil,
              Set(reactions.keys) == Set(ReactionType.allCases.map(\.rawValue)), reactions.values.allSatisfy({ $0 >= 0 }),
              myReaction == nil || (reactions[myReaction!] ?? 0) > 0 else { throw SocialError.invalid }
    }
}
struct RemoteComment: Codable, Identifiable, Sendable {
    let id: String; let user: String; let text: String; let spoiler: Bool; let createdAt: Date
    let interaction: InteractionSummary
    var parentID: String? = nil; var isReply: Bool? = nil; var mentions: [PostMention]? = nil
}
struct CommentsPage: Codable, Sendable {
    let reviewID: String; let canComment: Bool; let comments: [RemoteComment]; let users: [User]; let nextCursor: String?
    func validate(review: String) throws {
        let authors = Set(users.map(\.id))
        guard reviewID == review, comments.count <= 30, Set(comments.map(\.id)).count == comments.count,
              authors.count == users.count, comments.allSatisfy({ UUID(uuidString: $0.id) != nil && authors.contains($0.user) }),
              nextCursor == nil || (!comments.isEmpty && !(nextCursor?.isEmpty ?? true) && (nextCursor?.count ?? 0) <= 300)
        else { throw SocialError.invalid }
        for comment in comments { try comment.interaction.validate(target: comment.id) }
    }
}
struct CommentReceipt: Codable, Sendable { let reviewID: String; let commentID: String; let saved: Bool }
struct CommentReportReceipt: Codable, Sendable { let reported: Bool; let reviewID: String; let commentID: String; let blockedUserID: String? }
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
        for review in reviews {
            if let interaction = review.interaction { try interaction.validate(target: review.id) }
            if let count = review.commentCount, count < 0 { throw SocialError.invalid }
        }
    }
}
enum SocialError: LocalizedError, Equatable {
    case unavailable, invalid, reportLimit, publicationLimit, commentsRestricted, commentUnavailable, commentLimit, commentConflict, reactionLimit
    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("Esta review não está mais disponível para você. Atualize o feed.")
        case .invalid: return L10n.text("Não foi possível confirmar esta ação. Tente novamente.")
        case .reportLimit: return L10n.text("Você atingiu o limite de denúncias por hoje. Tente novamente mais tarde.")
        case .publicationLimit: return L10n.text("Você publicou muitas reviews nesta hora. Aguarde um pouco; seu rascunho continua aqui.")
        case .commentsRestricted: return L10n.text("O autor limitou quem pode comentar. Seu rascunho continua aqui.")
        case .commentUnavailable: return L10n.text("Este comentário não está mais disponível. Atualize a conversa.")
        case .commentLimit: return L10n.text("Você comentou muitas vezes nesta hora. Aguarde um pouco; seu rascunho continua aqui.")
        case .commentConflict: return L10n.text("Este envio já foi usado para outro comentário. Atualize a conversa antes de tentar novamente.")
        case .reactionLimit: return L10n.text("Você reagiu muitas vezes. Aguarde um minuto e tente novamente.")
        }
    }
}
extension CommentPermission {
    var apiValue: String { switch self { case .everyone: "everyone"; case .following: "following"; case .nobody: "nobody" } }
    init?(apiValue: String) {
        switch apiValue { case "everyone": self = .everyone; case "following": self = .following; case "nobody": self = .nobody; default: return nil }
    }
}
extension ReportReason {
    var apiValue: String {
        switch self { case .spoiler: "spoiler"; case .offensive: "offensive"; case .spam: "spam"; case .wrongCanon: "wrong_canon"; case .other: "other" }
    }
}
