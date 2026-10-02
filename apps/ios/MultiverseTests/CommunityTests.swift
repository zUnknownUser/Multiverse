import Foundation
import Testing
@testable import Multiverse

@MainActor private final class CommunityStub: CommunityAPI {
    let id = UUID().uuidString.lowercased()
    let user = User(id: "alice", name: "Alice", handle: "@alice", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")
    var unavailable = false
    var failWrites = false
    var writes: [String] = []
    var commentRows: [RemoteComment] = []
    func summary(_ id: String) -> InteractionSummary { .init(id: id, likes: 0, liked: false, myReaction: nil, reactions: ["POW!": 0, "ZAP!": 0, "KRAK!": 0, "HEH": 0]) }
    func page() throws -> CommunityPage {
        if unavailable { throw CommunityError.unavailable }
        return .init(posts: [.init(id: id, user: "alice", universeID: "wow", itemID: nil, title: "Title", text: "Text", spoiler: false, createdAt: .now, commentCount: commentRows.count, interaction: summary(id))], users: [user], nextCursor: nil)
    }
    func fetchPosts(universe: String?, item: String?, after: String?) async throws -> CommunityPage { try page() }
    func fetchPost(_ id: String) async throws -> CommunityPage { try page() }
    func publishPost(id: String, input: PostInput) async throws -> PostReceipt { .init(id: id, saved: true) }
    func deletePost(_ id: String) async throws -> PostDeletion { if failWrites { throw AuthError.networkUnavailable }; return .init(id: id, deleted: true) }
    func fetchPostComments(_ id: String, after: String?) async throws -> CommentsPage { .init(reviewID: id, canComment: true, comments: commentRows, users: [user], nextCursor: nil) }
    func postReply(post: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt {
        writes.append(id)
        if !commentRows.contains(where: { $0.id == id }) { commentRows.append(.init(id: id, user: "alice", text: text, spoiler: spoiler, createdAt: .now, interaction: summary(id))) }
        if failWrites { throw AuthError.networkUnavailable } // Server saved; response lost.
        return .init(reviewID: post, commentID: id, saved: true)
    }
    func reactToPost(_ id: String, comment: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary { if failWrites { throw AuthError.networkUnavailable }; return summary(comment ?? id) }
    func reportPost(_ id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt { .init(reported: true, reviewID: id, blockedUserID: alsoBlock ? "alice" : nil) }
    func reportPostComment(_ id: String, comment: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt { .init(reported: true, reviewID: id, commentID: comment, blockedUserID: alsoBlock ? "alice" : nil) }
}
@Suite(.serialized) @MainActor struct CommunityTests {
    @Test func losingAccessClearsCachedPostAndReplies() async {
        let api = CommunityStub(), id = UUID().uuidString.lowercased()
        _ = try? await api.postReply(post: api.id, id: id, text: "Hello", spoiler: false)
        let thread = CommunityThread(api: api, id: api.id); await thread.load()
        #expect(thread.post != nil && thread.comments.count == 1)
        api.unavailable = true; await thread.load()
        #expect(thread.post == nil && thread.comments.isEmpty && !thread.canComment)
    }
    @Test func ambiguousCommentRetryUsesSameIdentityAndDoesNotAppendOptimistically() async {
        let api = CommunityStub(), id = UUID().uuidString.lowercased()
        let thread = CommunityThread(api: api, id: api.id); await thread.load()
        api.failWrites = true
        #expect(await thread.reply(id: id, text: "Hello", spoiler: false) == false)
        #expect(thread.comments.isEmpty)
        api.failWrites = false
        #expect(await thread.reply(id: id, text: "Hello", spoiler: false))
        #expect(api.writes == [id, id] && thread.comments.count == 1)
    }
    @Test func failedReactionKeepsConfirmedCountsAndReportClearsContent() async {
        let api = CommunityStub(), thread = CommunityThread(api: CommunityStub(), id: UUID().uuidString.lowercased())
        await thread.load(); #expect(thread.post == nil)
        let loaded = CommunityThread(api: api, id: api.id); await loaded.load()
        api.failWrites = true; await loaded.react(comment: nil, reaction: "POW!", liked: true)
        #expect(loaded.interactions[api.id]?.likes == 0 && loaded.error != nil)
        #expect(await loaded.report(comment: nil, author: "alice", reason: .spam, block: true))
        #expect(loaded.post == nil && loaded.comments.isEmpty)
    }
    @Test func timelineRejectsAnotherUniverseAndNeverFallsBackToSamples() async {
        let api = CommunityStub(), timeline = CommunityTimeline()
        await timeline.load(api: api, universe: "marvel", item: nil)
        #expect(timeline.posts.isEmpty && timeline.error != nil)
        await timeline.load(api: api, universe: "wow", item: nil)
        #expect(timeline.posts.count == 1 && timeline.error == nil)
    }
}
