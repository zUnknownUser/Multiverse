import Foundation

struct CommunityPost: Codable, Identifiable, Sendable {
    let id: String; let user: String; let universeID: String; let itemID: String?
    let title: String; let text: String; let spoiler: Bool; let createdAt: Date
    let commentCount: Int; let interaction: InteractionSummary
}
struct CommunityPage: Codable, Sendable {
    let posts: [CommunityPost]; let users: [User]; let nextCursor: String?
    func validate() throws {
        guard posts.count <= 30, Set(posts.map(\.id)).count == posts.count,
              Set(users.map(\.id)).count == users.count,
              posts.allSatisfy({ post in UUID(uuidString: post.id) != nil && users.contains(where: { $0.id == post.user }) && post.commentCount >= 0 }),
              nextCursor == nil || (!posts.isEmpty && !(nextCursor?.isEmpty ?? true)) else { throw SocialError.invalid }
        for post in posts { try post.interaction.validate(target: post.id) }
    }
}
struct PostInput: Encodable, Sendable {
    let universeID: String; let itemID: String?; let title: String; let text: String; let spoiler: Bool
    enum CodingKeys: String, CodingKey { case universeID, itemID, title, text, spoiler }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(universeID, forKey: .universeID); try c.encode(itemID, forKey: .itemID)
        try c.encode(title, forKey: .title); try c.encode(text, forKey: .text); try c.encode(spoiler, forKey: .spoiler)
    }
}
struct SavedReceipt: Codable, Sendable { let saved: Bool }
struct PostReceipt: Codable, Sendable { let id: String; let saved: Bool }
struct PostDeletion: Codable, Sendable { let id: String; let deleted: Bool }
@MainActor protocol CommunityAPI: Sendable {
    func fetchPosts(universe: String?, item: String?, after: String?) async throws -> CommunityPage
    func fetchPost(_ id: String) async throws -> CommunityPage
    func publishPost(id: String, input: PostInput) async throws -> PostReceipt
    func deletePost(_ id: String) async throws -> PostDeletion
    func fetchPostComments(_ id: String, after: String?) async throws -> CommentsPage
    func postReply(post: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt
    func reactToPost(_ id: String, comment: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary
    func reportPost(_ id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt
    func reportPostComment(_ id: String, comment: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt
}
