import Foundation
import UIKit
import Testing
@testable import Multiverse

@MainActor private final class CommunityStub: CommunityAPI {
    let id = UUID().uuidString.lowercased()
    let user = User(id: "alice", name: "Alice", handle: "@alice", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")
    var unavailable = false
    var failWrites = false
    var writes: [String] = []
    var commentRows: [RemoteComment] = []
    var heldQueries: [String: CheckedContinuation<CommunityPage, any Error>] = [:]
    var holdQueries = false
    var replyParents: [String?] = []
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage {
        if holdQueries { return try await withCheckedThrowingContinuation { heldQueries[filter.search] = $0 } }
        return try page()
    }
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt {
        replyParents.append(parent)
        return try await postReply(post: post, id: id, text: text, spoiler: spoiler)
    }
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

    @Test func changingDiscoveryFilterRejectsLateResultsAndClearsPriorScope() async throws {
        let api = CommunityStub(), timeline = CommunityTimeline(); api.holdQueries = true
        let first = Task { await timeline.load(api: api, filter: .init(search: "first")) }
        for _ in 0..<100 { if api.heldQueries["first"] != nil { break }; await Task.yield() }
        let second = Task { await timeline.load(api: api, filter: .init(search: "second")) }
        for _ in 0..<100 { if api.heldQueries["second"] != nil { break }; await Task.yield() }
        let empty = CommunityPage(posts: [], users: [], nextCursor: nil)
        let secondReply = api.heldQueries.removeValue(forKey: "second")
        try #require(secondReply).resume(returning: empty)
        await second.value
        let firstReply = api.heldQueries.removeValue(forKey: "first")
        try #require(firstReply).resume(returning: api.page())
        await first.value
        #expect(timeline.posts.isEmpty && !timeline.busy && timeline.error == nil)
    }
    @Test func ambiguousThreadReplyKeepsItsParentAcrossRetry() async {
        let api = CommunityStub(), parent = UUID().uuidString.lowercased(), comment = UUID().uuidString.lowercased()
        let thread = CommunityThread(api: api, id: api.id); await thread.load(); api.failWrites = true
        #expect(await thread.reply(id: comment, text: "Reply @alice", spoiler: true, parent: parent) == false)
        api.failWrites = false
        #expect(await thread.reply(id: comment, text: "Reply @alice", spoiler: true, parent: parent))
        #expect(api.replyParents == [parent, parent] && thread.comments.count == 1)
    }
    @Test func photoPreparationRejectsNonImagesAndBoundsDecodedPixels() throws {
        #expect(throws: (any Error).self) { try CommunityPhoto.prepare(Data("not a picture".utf8)) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200))
        let source = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200)) }
        let photo = try CommunityPhoto.prepare(#require(source.pngData()))
        #expect(photo.preview.size.width <= 1600 && photo.preview.size.height <= 1600)
        #expect(photo.data.count <= 2_000_000 && UUID(uuidString: photo.id) != nil)
    }
    @Test func realCommunityRoutesDoNotEnableLegacyDemoModules() {
        let store = AppStore(accountAPI: AccountAPIClient())
        let id = UUID().uuidString.lowercased()
        for route in [Route.liveClubs(nil), .liveClub(id), .liveRooms("marvel"), .liveRoom("m-civil"), .communityFeed(.init(kind: "duel"))] { store.push(route) }
        #expect(store.homePath.count == 5 && !store.showsDemoFeatures)
        store.push(.club("demo")); store.push(.theories); #expect(store.homePath.count == 5)
    }
    @Test func newNotificationKindsValidateAndRemainTiedToPostTargets() throws {
        let api = CommunityStub()
        for kind in ["mention", "reply"] {
            let entry = ActivityNotification(id: UUID().uuidString.lowercased(), kind: kind, targetType: "post", targetID: api.id, commentID: nil, createdAt: .now, readAt: nil, user: api.user.id)
            try NotificationsPage(notifications: [entry], users: [api.user], unreadCount: 1, nextCursor: nil).validate()
            #expect(!entry.label.isEmpty)
        }
    }
}
