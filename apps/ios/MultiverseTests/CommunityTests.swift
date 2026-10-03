import Foundation
import UIKit
import Testing
@testable import Multiverse

@MainActor private final class CommunityStub: CommunityAPI {
    let id = UUID().uuidString.lowercased()
    let user = User(id: "alice", name: "Alice", handle: "@alice", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")
    var roomPage: CommunityPage?
    var unavailable = false
    var failWrites = false
    var writes: [String] = []
    var commentRows: [RemoteComment] = []
    var heldQueries: [String: CheckedContinuation<CommunityPage, any Error>] = [:]
    var holdQueries = false
    var replyParents: [String?] = []
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage {
        if holdQueries { return try await withCheckedThrowingContinuation { heldQueries[filter.search] = $0 } }
        return try roomPage ?? page()
    }
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt {
        replyParents.append(parent)
        return try await postReply(post: post, id: id, text: text, spoiler: spoiler)
    }
    func summary(_ id: String) -> InteractionSummary { .init(id: id, likes: 0, liked: false, myReaction: nil, reactions: ["POW!": 0, "ZAP!": 0, "KRAK!": 0, "HEH": 0]) }
    func page() throws -> CommunityPage {
        if unavailable { throw CommunityError.unavailable }
        return .init(posts: [.init(id: id, user: "alice", universeID: "marvel", itemID: nil, title: "Title", text: "Text", spoiler: false, createdAt: .now, commentCount: commentRows.count, interaction: summary(id))], users: [user], nextCursor: nil)
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
    private func roomPost(_ api: CommunityStub, at time: Double, text: String = "Message", segment: Int = 0) -> CommunityPost {
        let id = UUID().uuidString.lowercased()
        return .init(id: id, user: api.user.id, universeID: "marvel", itemID: "room-work", title: "Room", text: text, spoiler: false, createdAt: Date(timeIntervalSince1970: time), commentCount: 0, interaction: api.summary(id), segment: segment, kind: "room")
    }
    @Test func roomBuffersNewMessagesWithoutMovingHistoryAndShowsLatestOnRequest() async {
        let api = CommunityStub(), room = RoomTimeline()
        let filter = CommunityFilter(item: "room-work", kind: "room", segment: 0)
        let first = roomPost(api, at: 1), second = roomPost(api, at: 2), third = roomPost(api, at: 3)
        api.roomPage = .init(posts: [second, first], users: [api.user], nextCursor: "older")
        #expect(await room.load(api: api, filter: filter))
        #expect(room.posts.map(\.id) == [first.id, second.id])
        api.roomPage = .init(posts: [third, second, first], users: [api.user], nextCursor: "older")
        #expect(await room.load(api: api, filter: filter, following: { false }))
        #expect(room.hasNewMessages)
        #expect(room.posts.map(\.id) == [first.id, second.id])
        room.showBuffered()
        #expect(room.posts.map(\.id) == [first.id, second.id, third.id])
        #expect(!room.hasNewMessages)
        // A deletion updates the visible range without a false new-message badge.
        api.roomPage = .init(posts: [third, first], users: [api.user], nextCursor: nil)
        #expect(await room.load(api: api, filter: filter, following: { false }))
        #expect(room.posts.map(\.id) == [first.id, third.id])
        #expect(!room.hasNewMessages)
    }
    @Test func roomHistoryDeduplicatesAndResetDiscardsAnInFlightSpoilerPage() async {
        let api = CommunityStub(), room = RoomTimeline()
        let filter = CommunityFilter(item: "room-work", kind: "room", segment: 0)
        let first = roomPost(api, at: 1), second = roomPost(api, at: 2)
        api.roomPage = .init(posts: [second], users: [api.user], nextCursor: "older")
        await room.load(api: api, filter: filter)
        api.roomPage = .init(posts: [second, first], users: [api.user], nextCursor: nil)
        await room.load(api: api, filter: filter, more: true, following: { false })
        #expect(room.posts.map(\.id) == [first.id, second.id])
        api.holdQueries = true
        let work = Task { await room.load(api: api, filter: filter) }
        while api.heldQueries[""] == nil { await Task.yield() }
        room.reset()
        api.heldQueries.removeValue(forKey: "")?.resume(returning: .init(posts: [second], users: [api.user], nextCursor: nil))
        #expect(await work.value == false)
        #expect(room.posts.isEmpty)
        #expect(!room.busy)
    }
    @Test func roomDoesNotJumpIfReaderScrollsAwayDuringFetch() async {
        let api = CommunityStub(), room = RoomTimeline()
        let filter = CommunityFilter(item: "room-work", kind: "room", segment: 0)
        let first = roomPost(api, at: 1), second = roomPost(api, at: 2)
        api.roomPage = .init(posts: [first], users: [api.user], nextCursor: nil)
        await room.load(api: api, filter: filter)
        api.holdQueries = true
        var following = true
        let work = Task { await room.load(api: api, filter: filter, following: { following }) }
        while api.heldQueries[""] == nil { await Task.yield() }
        following = false
        api.heldQueries.removeValue(forKey: "")?.resume(returning: .init(posts: [second, first], users: [api.user], nextCursor: nil))
        #expect(await work.value)
        #expect(room.posts.map(\.id) == [first.id])
        #expect(room.hasNewMessages)
    }

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
        await timeline.load(api: api, universe: "dc", item: nil)
        #expect(timeline.posts.isEmpty && timeline.error != nil)
        await timeline.load(api: api, universe: "marvel", item: nil)
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
