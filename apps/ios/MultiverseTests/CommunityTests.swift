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
    var postFetches = 0
    var commentRequests: [String?] = []
    var commentPage: CommentsPage?
    var receiptOverride: CommentReceipt?
    var hiddenReceipt = false
    var contextPages: [String: CommentContextPage] = [:]
    var contextRequests: [String] = []
    var contextError: (any Error)?
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage {
        if holdQueries { return try await withCheckedThrowingContinuation { heldQueries[filter.search] = $0 } }
        return try roomPage ?? page()
    }
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt {
        replyParents.append(parent)
        return try saveReply(post: post, id: id, text: text, spoiler: spoiler, parent: parent)
    }
    func summary(_ id: String) -> InteractionSummary { .init(id: id, likes: 0, liked: false, myReaction: nil, reactions: ["POW!": 0, "ZAP!": 0, "KRAK!": 0, "HEH": 0]) }
    func page() throws -> CommunityPage {
        if unavailable { throw CommunityError.unavailable }
        return .init(posts: [.init(id: id, user: "alice", universeID: "marvel", itemID: nil, title: "Title", text: "Text", spoiler: false, createdAt: .now, commentCount: commentRows.count, interaction: summary(id))], users: [user], nextCursor: nil)
    }
    func fetchPosts(universe: String?, item: String?, after: String?) async throws -> CommunityPage { try page() }
    func fetchPost(_ id: String) async throws -> CommunityPage { postFetches += 1; return try page() }
    func publishPost(id: String, input: PostInput) async throws -> PostReceipt { .init(id: id, saved: true) }
    func deletePost(_ id: String) async throws -> PostDeletion { if failWrites { throw AuthError.networkUnavailable }; return .init(id: id, deleted: true) }
    func fetchPostComments(_ id: String, after: String?) async throws -> CommentsPage {
        commentRequests.append(after)
        return commentPage ?? .init(reviewID: id, canComment: true, comments: commentRows, users: [user], nextCursor: nil)
    }
    func fetchCommentContext(post: String, comment: String) async throws -> CommentContextPage {
        contextRequests.append(comment)
        if let contextError { throw contextError }
        guard let page = contextPages[comment] else { throw SocialError.commentUnavailable }
        return page
    }
    func postReply(post: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt {
        try saveReply(post: post, id: id, text: text, spoiler: spoiler, parent: nil)
    }
    private func saveReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) throws -> CommentReceipt {
        writes.append(id)
        if !commentRows.contains(where: { $0.id == id }) {
            commentRows.append(.init(id: id, user: "alice", text: text, spoiler: spoiler, createdAt: .now, interaction: summary(id), parentID: parent, isReply: parent != nil))
        }
        if failWrites { throw AuthError.networkUnavailable } // Server saved; response lost.
        if let receiptOverride { return receiptOverride }
        if hiddenReceipt { return .init(reviewID: post, commentID: id, saved: true) }
        return .init(reviewID: post, commentID: id, saved: true, comment: commentRows.first { $0.id == id }, user: user)
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
    private func comment(_ api: CommunityStub, at time: Double, parent: String? = nil) -> RemoteComment {
        let id = UUID().uuidString.lowercased()
        return .init(id: id, user: api.user.id, text: "Comment", spoiler: false, createdAt: Date(timeIntervalSince1970: time), interaction: api.summary(id), parentID: parent, isReply: parent != nil)
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
    @Test func unansweredFeedRejectsAnsweredPostsWithoutLosingRegularDiscovery() async throws {
        let api = CommunityStub(), timeline = CommunityTimeline()
        await timeline.load(api: api, filter: .init(feed: "unanswered"))
        #expect(timeline.posts.count == 1 && timeline.posts.first?.itemID == nil)
        _ = try await api.postReply(post: api.id, id: UUID().uuidString.lowercased(), text: "Reply", spoiler: false)
        let unanswered = CommunityTimeline()
        await unanswered.load(api: api, filter: .init(feed: "unanswered"))
        #expect(unanswered.posts.isEmpty && unanswered.error != nil)
        await unanswered.load(api: api, filter: .init())
        #expect(unanswered.posts.count == 1 && unanswered.error == nil)
    }
    @Test func homeCommunityDoesNotSharePostsBetweenAccounts() async {
        let first = AppStore(communityAPI: CommunityStub()), second = AppStore(communityAPI: CommunityStub())
        if let api = first.communityAPI { await first.homeCommunity.load(api: api, filter: .init()) }
        #expect(first.homeCommunity.posts.count == 1)
        #expect(second.homeCommunity.posts.isEmpty)
    }
    @Test func refreshingTimelineReleasesAuthorsFromPreviousPages() async {
        let api = CommunityStub(), timeline = CommunityTimeline()
        await timeline.load(api: api, filter: .init())
        #expect(timeline.users.count == 1)
        api.roomPage = .init(posts: [], users: [], nextCursor: nil)
        await timeline.load(api: api, filter: .init())
        #expect(timeline.posts.isEmpty && timeline.users.isEmpty)
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
        #expect(thread.comments.first?.parentID == parent && thread.comments.first?.spoiler == true)
        #expect(api.postFetches == 1 && api.commentRequests.count == 1)
    }
    @Test func confirmedReplyPreservesLoadedPagesAndCursorWithoutReloading() async throws {
        let api = CommunityStub()
        let first = comment(api, at: 1), second = comment(api, at: 2)
        api.commentRows = [first, second]
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [first], users: [api.user], nextCursor: "page-2")
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load()
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [second], users: [api.user], nextCursor: "page-3")
        await thread.load(more: true)
        let replyID = UUID().uuidString.lowercased()
        #expect(await thread.reply(id: replyID, text: "Saved reply", spoiler: false, parent: first.id))
        #expect(thread.comments.map(\.id) == [first.id, second.id, replyID])
        #expect(thread.cursor == "page-3" && thread.post?.commentCount == 3)
        #expect(api.postFetches == 1 && api.commentRequests == [nil, "page-2"])
        #expect(await thread.reply(id: replyID, text: "Saved reply", spoiler: false, parent: first.id))
        #expect(thread.comments.count == 3 && thread.post?.commentCount == 3)
        let saved = try #require(api.commentRows.first { $0.id == replyID })
        let third = comment(api, at: 3)
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [second, third, saved], users: [api.user], nextCursor: nil)
        await thread.load(more: true)
        #expect(thread.comments.map(\.id) == [first.id, second.id, third.id, replyID])
        #expect(thread.cursor == nil && api.commentRequests == [nil, "page-2", "page-3"])
        #expect(thread.interactions[replyID]?.id == replyID && thread.users[saved.user]?.id == api.user.id)
    }
    @Test func hiddenReplyReceiptNeverResurrectsCachedContent() async {
        let api = CommunityStub(), replyID = UUID().uuidString.lowercased()
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load()
        #expect(await thread.reply(id: replyID, text: "Saved reply", spoiler: false))
        #expect(thread.comments.count == 1)
        thread.toggleConversation(replyID)
        api.hiddenReceipt = true
        #expect(await thread.reply(id: replyID, text: "Saved reply", spoiler: false))
        #expect(thread.comments.isEmpty && thread.interactions[replyID] == nil)
        #expect(thread.collapsed.isEmpty && thread.post?.commentCount == 0)
        #expect(thread.error != nil && api.postFetches == 1 && api.commentRequests.count == 1)
    }
    @Test func malformedReplyReceiptsLeaveConfirmedConversationUntouched() async {
        let api = CommunityStub(), replyID = UUID().uuidString.lowercased()
        let existing = comment(api, at: 1)
        api.commentRows = [existing]
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [existing], users: [api.user], nextCursor: "next")
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load()
        thread.toggleConversation(existing.id)
        let wrongText = RemoteComment(id: replyID, user: api.user.id, text: "Unrelated receipt", spoiler: false, createdAt: .now, interaction: api.summary(replyID))
        let malformed: [CommentReceipt] = [
            .init(reviewID: UUID().uuidString.lowercased(), commentID: replyID, saved: true),
            .init(reviewID: api.id, commentID: replyID, saved: true, comment: wrongText, user: api.user),
            .init(reviewID: api.id, commentID: replyID, saved: true, user: api.user),
            .init(reviewID: api.id, commentID: replyID, saved: true, commentCount: -1),
        ]
        for receipt in malformed {
            api.receiptOverride = receipt
            #expect(await thread.reply(id: replyID, text: "Actual reply", spoiler: false) == false)
            #expect(thread.comments.map(\.id) == [existing.id] && thread.cursor == "next")
            #expect(thread.collapsed == [existing.id] && thread.post?.commentCount == 1)
            #expect(thread.interactions[replyID] == nil && thread.error != nil && !thread.busy)
        }
        #expect(api.postFetches == 1 && api.commentRequests.count == 1)
    }
    @Test func collapsedBranchesHideLaterPagesAndRestoreNestedState() async {
        let api = CommunityStub()
        let root = comment(api, at: 1), sibling = comment(api, at: 2)
        let child = comment(api, at: 3, parent: root.id)
        let grandchild = comment(api, at: 4, parent: child.id)
        let siblingReply = comment(api, at: 5, parent: sibling.id)
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [root, sibling, child], users: [api.user], nextCursor: "children")
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load()
        thread.toggleConversation(child.id)
        thread.toggleConversation(root.id)
        #expect(thread.conversation.visible.map(\.id) == [root.id, sibling.id])
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [grandchild, siblingReply], users: [api.user], nextCursor: nil)
        await thread.load(more: true)
        #expect(thread.conversation.visible.map(\.id) == [root.id, sibling.id, siblingReply.id])
        thread.toggleConversation(root.id)
        #expect(thread.conversation.visible.map(\.id) == [root.id, sibling.id, child.id, siblingReply.id])
        thread.toggleConversation(child.id)
        #expect(thread.conversation.visible.map(\.id) == [root.id, sibling.id, child.id, grandchild.id, siblingReply.id])
        #expect(thread.conversation.ancestors(of: grandchild.id) == [root.id, child.id, grandchild.id])
    }
    @Test func replyingReopensOnlyTheSavedRepliesAncestors() async {
        let api = CommunityStub()
        let root = comment(api, at: 1), sibling = comment(api, at: 2)
        let child = comment(api, at: 3, parent: root.id)
        api.commentRows = [root, sibling, child]
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load()
        for id in [root.id, sibling.id, child.id] { thread.toggleConversation(id) }
        let replyID = UUID().uuidString.lowercased()
        #expect(await thread.reply(id: replyID, text: "Following up", spoiler: false, parent: child.id))
        #expect(thread.collapsed == [sibling.id])
        #expect(thread.conversation.visible.map(\.id) == [root.id, sibling.id, child.id, replyID])
    }
    @Test func contextRejectsUnrelatedOrOversizedChains() throws {
        let api = CommunityStub()
        let root = comment(api, at: 1), unrelated = comment(api, at: 2)
        let reply = comment(api, at: 3, parent: root.id)
        let valid = CommentContextPage(reviewID: api.id, targetID: reply.id, comments: [root, reply], users: [api.user], canComment: true, truncated: false)
        try valid.validate(post: api.id, target: reply.id)
        let malformed: [CommentContextPage] = [
            .init(reviewID: api.id, targetID: reply.id, comments: [unrelated, reply], users: [api.user], canComment: true, truncated: false),
            .init(reviewID: api.id, targetID: root.id, comments: [root, reply], users: [api.user], canComment: true, truncated: false),
            .init(reviewID: api.id, targetID: reply.id, comments: [root, reply], users: [], canComment: true, truncated: false),
            .init(reviewID: api.id, targetID: reply.id, comments: [root, reply], users: [api.user], canComment: true, truncated: true),
        ]
        for page in malformed { #expect(throws: (any Error).self) { try page.validate(post: api.id, target: reply.id) } }
        var chain = [root]
        for index in 1...30 { chain.append(comment(api, at: Double(index + 1), parent: chain.last!.id)) }
        let oversized = CommentContextPage(reviewID: api.id, targetID: chain.last!.id, comments: chain, users: [api.user], canComment: true, truncated: false)
        #expect(throws: (any Error).self) { try oversized.validate(post: api.id, target: chain.last!.id) }
    }
    @Test func contextLoadsBoundedEarlierPagesWithoutReplacingDiscussion() async {
        let api = CommunityStub()
        let root = comment(api, at: 1)
        let middle = comment(api, at: 2, parent: root.id)
        let target = comment(api, at: 3, parent: middle.id)
        api.commentPage = .init(reviewID: api.id, canComment: true, comments: [target], users: [api.user], nextCursor: "discussion-next")
        let thread = CommunityThread(api: api, id: api.id)
        await thread.load(); thread.toggleConversation(target.id)
        api.contextPages[target.id] = .init(reviewID: api.id, targetID: target.id, comments: [middle, target], users: [api.user], canComment: true, truncated: true)
        api.contextPages[root.id] = .init(reviewID: api.id, targetID: root.id, comments: [root], users: [api.user], canComment: true, truncated: false)
        let context = CommentContext(api: api, post: api.id, target: target.id)
        await context.load()
        #expect(context.comments.map(\.id) == [middle.id, target.id] && context.earlierID == root.id)
        await context.load(earlier: true)
        #expect(context.comments.map(\.id) == [root.id, middle.id, target.id] && context.earlierID == nil)
        await context.load(earlier: true)
        #expect(api.contextRequests == [target.id, root.id])
        #expect(thread.comments.map(\.id) == [target.id] && thread.cursor == "discussion-next")
        #expect(thread.collapsed == [target.id] && api.commentRequests.count == 1)
    }
    @Test func earlierContextRejectsAChainThatLoopsBackToLoadedReplies() async {
        let api = CommunityStub()
        let rootID = UUID().uuidString.lowercased()
        let target = comment(api, at: 3, parent: rootID)
        let older = comment(api, at: 1, parent: target.id)
        let root = RemoteComment(id: rootID, user: api.user.id, text: "Earlier reply", spoiler: false, createdAt: Date(timeIntervalSince1970: 2), interaction: api.summary(rootID), parentID: older.id, isReply: true)
        api.contextPages[target.id] = .init(reviewID: api.id, targetID: target.id, comments: [target], users: [api.user], canComment: true, truncated: true)
        api.contextPages[rootID] = .init(reviewID: api.id, targetID: rootID, comments: [older, root], users: [api.user], canComment: true, truncated: true)
        let context = CommentContext(api: api, post: api.id, target: target.id)
        await context.load()
        await context.load(earlier: true)
        #expect(context.comments.map(\.id) == [target.id] && context.earlierID == rootID)
        #expect(context.error != nil && !context.busy)
    }
    @Test func contextKeepsLoadedPagesOnNetworkFailureAndClearsRevokedAccess() async {
        let api = CommunityStub()
        let root = comment(api, at: 1)
        let target = comment(api, at: 2, parent: root.id)
        api.contextPages[target.id] = .init(reviewID: api.id, targetID: target.id, comments: [target], users: [api.user], canComment: true, truncated: true)
        let context = CommentContext(api: api, post: api.id, target: target.id)
        await context.load()
        api.contextError = AuthError.networkUnavailable
        await context.load(earlier: true)
        #expect(context.comments.map(\.id) == [target.id] && context.earlierID == root.id)
        #expect(context.error != nil && !context.busy)
        api.contextError = SocialError.commentUnavailable
        await context.load(earlier: true)
        #expect(context.comments.isEmpty && context.users.isEmpty && context.earlierID == nil)
        #expect(context.error != nil && !context.busy)
    }
    @Test func photoPreparationRejectsNonImagesAndBoundsDecodedPixels() throws {
        #expect(throws: (any Error).self) { try PhotoPreparation.prepare(Data("not a picture".utf8)) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200))
        let source = renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200)) }
        let photo = try PhotoPreparation.prepare(#require(source.pngData()))
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
