import Foundation

struct CommunityPost: Codable, Identifiable, Sendable {
    let id: String; let user: String; let universeID: String; let itemID: String?
    let title: String; let text: String; let spoiler: Bool; let createdAt: Date
    let commentCount: Int; let interaction: InteractionSummary
    var segment: Int? = nil; var kind: String? = nil; var clubID: String? = nil; var scheduleID: String? = nil
    var version: Int? = nil; var editedAt: Date? = nil
    var images: [PostImage]? = nil; var mentions: [PostMention]? = nil; var votes: PostVotes? = nil
    var optionA: String? = nil; var optionB: String? = nil; var closesAt: Date? = nil
    var resolution: String? = nil; var resolutionNote: String? = nil
    var dailyDay: String? = nil
}
struct CommunityPage: Codable, Sendable {
    let posts: [CommunityPost]; let users: [User]; let nextCursor: String?
    func validate() throws {
        guard posts.count <= 30, Set(posts.map(\.id)).count == posts.count,
              Set(users.map(\.id)).count == users.count,
              posts.allSatisfy({ post in UUID(uuidString: post.id) != nil && users.contains(where: { $0.id == post.user }) && post.commentCount >= 0 }),
              nextCursor == nil || (!posts.isEmpty && !(nextCursor?.isEmpty ?? true)) else { throw SocialError.invalid }
        for post in posts {
            try post.interaction.validate(target: post.id)
            guard (post.images?.count ?? 0) <= 4, post.images?.allSatisfy({ UUID(uuidString: $0.id) != nil && (1...1600).contains($0.width) && (1...1600).contains($0.height) }) ?? true,
                  post.votes.map({ $0.counts.count == 2 && $0.counts.allSatisfy { $0 >= 0 } && ($0.mine == nil || (0...1).contains($0.mine!)) }) ?? true else { throw SocialError.invalid }
        }
    }
}
struct PostInput: Encodable, Sendable {
    let universeID: String; let itemID: String?; let title: String; let text: String; let spoiler: Bool
    var segment = 0; var imageIDs: [String] = []; var kind = "discussion"; var clubID: String? = nil; var scheduleID: String? = nil
    var optionA: String? = nil; var optionB: String? = nil; var closesAt: String? = nil
    enum CodingKeys: String, CodingKey { case universeID, itemID, title, text, spoiler, segment, imageIDs, kind, clubID, scheduleID, optionA, optionB, closesAt }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(universeID, forKey: .universeID); try c.encode(itemID, forKey: .itemID)
        try c.encode(title, forKey: .title); try c.encode(text, forKey: .text); try c.encode(spoiler, forKey: .spoiler)
        try c.encode(segment, forKey: .segment); try c.encode(imageIDs, forKey: .imageIDs); try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(clubID, forKey: .clubID); try c.encodeIfPresent(scheduleID, forKey: .scheduleID)
        try c.encodeIfPresent(optionA, forKey: .optionA); try c.encodeIfPresent(optionB, forKey: .optionB); try c.encodeIfPresent(closesAt, forKey: .closesAt)
    }
}
struct SavedReceipt: Codable, Sendable { let saved: Bool }
struct PostReceipt: Codable, Sendable { let id: String; let saved: Bool }
struct PostDeletion: Codable, Sendable { let id: String; let deleted: Bool }
@MainActor protocol CommunityAPI: Sendable {
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage
    func editPost(_ id: String, input: PostEdit) async throws -> PostReceipt
    func uploadPostImage(post: String, id: String, data: Data) async throws -> PostImage
    func fetchPostImage(post: String, id: String) async throws -> PostImageData
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt
    func votePost(_ id: String, choice: Int) async throws -> PostReceipt
    func resolveTheory(_ id: String, status: String, note: String, version: Int) async throws -> PostReceipt
    func mentionPeople(query: String) async throws -> [User]
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
