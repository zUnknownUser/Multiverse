import Foundation
import Testing
@testable import Multiverse

@MainActor private final class SocialStub: SocialAPI {
    var page: SocialPage
    var publicDiary = false
    var failure = false
    var acknowledge = true
    var blocks: [SocialBlock] = []
    var holdFeed = false
    var pendingFeed: CheckedContinuation<SocialPage, any Error>?
    var holdPrivacy = false
    var pendingPrivacy: CheckedContinuation<DiaryPrivacy, any Error>?
    var cursors: [String?] = []
    var writes = 0
    var commentPermission = "following"
    var savedComments: [String] = []
    var commentFailure = false
    var commentItems: [RemoteComment] = []
    var holdComments = false
    var pendingComments: CheckedContinuation<CommentsPage, any Error>?
    func fetchComments(reviewID: String, after: String?) async throws -> CommentsPage {
        if commentFailure { throw AuthError.networkUnavailable }
        if holdComments { return try await withCheckedThrowingContinuation { pendingComments = $0 } }
        return CommentsPage(reviewID: reviewID, canComment: commentPermission != "nobody", comments: commentItems, users: page.users, nextCursor: nil)
    }
    func postComment(reviewID: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt {
        savedComments.append(id)
        if failure { throw AuthError.networkUnavailable }
        return CommentReceipt(reviewID: reviewID, commentID: id, saved: acknowledge)
    }
    func setReaction(reviewID: String, commentID: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary {
        if failure { throw AuthError.networkUnavailable }
        return InteractionSummary(id: commentID ?? reviewID, likes: liked ? 1 : 0, liked: acknowledge ? liked : !liked, myReaction: reaction,
            reactions: Dictionary(uniqueKeysWithValues: ReactionType.allCases.map { ($0.rawValue, $0.rawValue == reaction ? 1 : 0) }))
    }
    func saveCommentPermission(_ permission: String) async throws -> DiaryPrivacy {
        if failure { throw AuthError.networkUnavailable }
        commentPermission = permission
        return DiaryPrivacy(publicDiary: publicDiary, commentPermission: acknowledge ? permission : "invalid")
    }
    func reportComment(reviewID: String, id: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt {
        if failure { throw AuthError.networkUnavailable }
        return CommentReportReceipt(reported: acknowledge, reviewID: reviewID, commentID: id, blockedUserID: alsoBlock ? "alice" : nil)
    }
    init() {
        let sample = SampleData.load()
        let item = sample.items[0]
        page = SocialPage(reviews: [ActivityReview(id: UUID().uuidString, user: "alice", item: item.id, rating: 4.5, text: "Real review", spoiler: true, createdAt: .now)],
            users: [User(id: "alice", name: "Alice", handle: "@alice", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")],
            items: [item], universes: sample.universes.filter { $0.id == item.uni }, nextCursor: nil)
    }
    func fetchFeed(after: String?) async throws -> SocialPage {
        cursors.append(after)
        if failure { throw AuthError.networkUnavailable }
        if holdFeed { return try await withCheckedThrowingContinuation { pendingFeed = $0 } }
        return page
    }
    func fetchReview(id: String) async throws -> SocialPage {
        if failure { throw SocialError.unavailable }
        return page
    }
    func fetchPrivacy() async throws -> DiaryPrivacy {
        if failure { throw AuthError.networkUnavailable }
        if holdPrivacy { return try await withCheckedThrowingContinuation { pendingPrivacy = $0 } }
        return DiaryPrivacy(publicDiary: publicDiary, commentPermission: commentPermission)
    }
    func savePrivacy(publicDiary: Bool) async throws -> DiaryPrivacy {
        writes += 1
        if failure { throw AuthError.networkUnavailable }
        self.publicDiary = publicDiary
        return DiaryPrivacy(publicDiary: acknowledge ? publicDiary : !publicDiary)
    }
    func fetchBlocks() async throws -> SocialBlocks {
        if failure { throw AuthError.networkUnavailable }
        return SocialBlocks(users: blocks)
    }
    func setBlock(id: String, blocked: Bool) async throws -> BlockReceipt {
        writes += 1
        if failure { throw AuthError.networkUnavailable }
        return BlockReceipt(userID: id, blocked: acknowledge ? blocked : !blocked)
    }
    func reportReview(id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt {
        writes += 1
        if failure { throw AuthError.networkUnavailable }
        return ReportReceipt(reported: acknowledge, reviewID: id, blockedUserID: alsoBlock ? "alice" : nil)
    }
}

@MainActor struct SocialStoreTests {
    @Test func remoteCommentsRequireAcknowledgementAndRetryKeepsTheSameIdentity() async {
        let api = SocialStub(), id = api.page.reviews[0].id, commentID = UUID().uuidString
        let store = SocialStore(api: api)
        await store.loadComments(id)
        api.failure = true
        #expect(!(await store.postComment(reviewID: id, id: commentID, text: "Draft", spoiler: true)))
        #expect(store.commentErrors[id] != nil)
        api.failure = false
        #expect(await store.postComment(reviewID: id, id: commentID, text: "Draft", spoiler: true))
        #expect(api.savedComments == [commentID, commentID])
        api.acknowledge = false
        #expect(!(await store.postComment(reviewID: id, id: commentID, text: "Draft", spoiler: true)))
    }
    @Test func confirmedReactionSurvivesFailedMutationAndStaleFeed() async throws {
        let api = SocialStub(), id = api.page.reviews[0].id
        let store = SocialStore(api: api)
        await store.loadFeed()
        api.holdFeed = true
        let stale = Task { await store.loadFeed() }
        try await settle { api.pendingFeed != nil }
        #expect(await store.setReaction(reviewID: id, reaction: "POW!", liked: true))
        api.pendingFeed?.resume(returning: api.page)
        await stale.value
        #expect(store.interactions[id]?.myReaction == "POW!")
        api.failure = true
        #expect(!(await store.setReaction(reviewID: id, reaction: nil, liked: false)))
        #expect(store.interactions[id]?.liked == true && store.actionError != nil)
        api.failure = false
        #expect(await store.setReaction(reviewID: id, reaction: nil, liked: false))
        #expect(store.interactions[id]?.myReaction == nil && store.interactions[id]?.likes == 0)
    }
    @Test func lateCommentReadCannotRestoreReportedOrBlockedContent() async throws {
        let api = SocialStub(), id = api.page.reviews[0].id
        let store = SocialStore(api: api)
        api.holdComments = true
        let stale = Task { await store.loadComments(id) }
        try await settle { api.pendingComments != nil }
        #expect(await store.setBlock("alice", blocked: true))
        api.pendingComments?.resume(returning: CommentsPage(reviewID: id, canComment: true, comments: [], users: [], nextCursor: nil))
        await stale.value
        #expect(store.canComment[id] == nil && store.comments[id] == nil)
    }
    @Test func permissionOnlyChangesAfterAcknowledgementAndIsAccountScoped() async {
        let api = SocialStub(), store = SocialStore(api: SocialStub())
        #expect(store.commentPermission == nil)
        let actual = SocialStore(api: api)
        await actual.loadPrivacy()
        #expect(actual.commentPermission == .following)
        api.failure = true
        #expect(!(await actual.setCommentPermission(.everyone)))
        #expect(actual.commentPermission == .following)
        api.failure = false
        #expect(await actual.setCommentPermission(.nobody))
        #expect(actual.commentPermission == .nobody && store.commentPermission == nil)
        api.acknowledge = false
        #expect(!(await actual.setCommentPermission(.everyone)))
        #expect(actual.commentPermission == .nobody)
    }
    @Test func commentPayloadRejectsForeignReferencesAndInvalidReactionCounts() throws {
        let id = UUID().uuidString
        let bad = InteractionSummary(id: id, likes: 0, liked: true, myReaction: nil, reactions: [:])
        #expect(throws: (any Error).self) { try bad.validate(target: id) }
        let page = CommentsPage(reviewID: id, canComment: true, comments: [], users: [], nextCursor: "loop")
        #expect(throws: (any Error).self) { try page.validate(review: id) }
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
    @Test func feedLoadsRealReferencesAndDoesNotConfuseErrorsWithEmptyContent() async {
        let api = SocialStub(), store = SocialStore(api: SocialStub())
        #expect(!store.hasLoadedFeed)
        let actual = SocialStore(api: api)
        await actual.loadFeed()
        #expect(actual.feed.first?.text == "Real review")
        #expect(actual.users["alice"]?.name == "Alice")
        api.failure = true
        await actual.loadFeed()
        #expect(actual.feedError != nil)
        #expect(actual.feed.count == 1)
        api.failure = false
        api.page = SocialPage(reviews: [], users: [], items: [], universes: [], nextCursor: nil)
        await actual.loadFeed()
        #expect(actual.feed.isEmpty && actual.hasLoadedFeed && actual.feedError == nil)
    }
    @Test func paginationDeduplicatesAndRejectsRepeatedCursorWithoutLosingContent() async {
        let api = SocialStub(), empty = SocialStore(api: SocialStub())
        await empty.loadFeed(more: true)
        #expect(!empty.hasLoadedFeed)
        let p = api.page
        api.page = SocialPage(reviews: p.reviews, users: p.users, items: p.items, universes: p.universes, nextCursor: "page2")
        let store = SocialStore(api: api)
        await store.loadFeed()
        await store.loadFeed(more: true)
        #expect(store.feedError != nil)
        #expect(store.feed.count == 1)
        api.page = p
        await store.loadFeed(more: true)
        #expect(store.feed.count == 1 && store.nextCursor == nil)
        #expect(api.cursors.count == 3)
    }
    @Test func privacyRequiresConfirmationAndOldReadsCannotUndoNewChoice() async throws {
        let api = SocialStub(), store = SocialStore(api: SocialStub())
        #expect(!(await store.setPublicDiary(true)))
        let actual = SocialStore(api: api)
        await actual.loadPrivacy()
        #expect(actual.publicDiary == false)
        api.failure = true
        #expect(!(await actual.setPublicDiary(true)))
        #expect(actual.publicDiary == false && actual.privacyError != nil)
        api.failure = false; api.holdPrivacy = true
        let old = Task { await actual.loadPrivacy() }
        try await settle { api.pendingPrivacy != nil }
        #expect(await actual.setPublicDiary(true))
        api.pendingPrivacy?.resume(returning: DiaryPrivacy(publicDiary: false))
        await old.value
        #expect(actual.publicDiary == true)
        api.acknowledge = false
        #expect(!(await actual.setPublicDiary(false)))
        #expect(actual.publicDiary == true)
    }
    @Test func reportFailureKeepsContentAndSuccessfulReportInvalidatesLateFeed() async throws {
        let api = SocialStub(), store = SocialStore(api: SocialStub())
        #expect(store.feed.isEmpty)
        let actual = SocialStore(api: api)
        await actual.loadFeed()
        let id = api.page.reviews[0].id
        api.failure = true
        #expect(!(await actual.report(id, authorID: "alice", reason: .spam, alsoBlock: true)))
        #expect(actual.feed.count == 1 && actual.actionError != nil)
        api.failure = false; api.holdFeed = true
        let read = Task { await actual.loadFeed() }
        try await settle { api.pendingFeed != nil }
        #expect(await actual.report(id, authorID: "alice", reason: .spam, alsoBlock: true))
        api.pendingFeed?.resume(returning: api.page)
        await read.value
        #expect(actual.feed.isEmpty && actual.reviews.isEmpty)
    }
    @Test func blockAndUnblockOnlyApplyAfterAcknowledgementAndRemainAccountScoped() async {
        let api = SocialStub(), store = SocialStore(api: SocialStub())
        #expect(store.blocks.isEmpty)
        let actual = SocialStore(api: api)
        api.blocks = [SocialBlock(id: "alice", handle: "@alice", createdAt: .now)]
        await actual.loadBlocks(); await actual.loadFeed()
        api.acknowledge = false
        #expect(!(await actual.setBlock("alice", blocked: false)))
        #expect(actual.blocks.count == 1 && actual.feed.count == 1)
        api.acknowledge = true
        #expect(await actual.setBlock("alice", blocked: false))
        #expect(actual.blocks.isEmpty && actual.feed.isEmpty)
        #expect(store.publicDiary == nil && store.users.isEmpty)
    }
    @Test func unavailableDetailRemovesCachedReviewAndInvalidReferencesAreRejected() async throws {
        let api = SocialStub(), actual = SocialStore(api: SocialStub())
        #expect(actual.reviews.isEmpty)
        let store = SocialStore(api: api)
        await store.loadFeed()
        let id = api.page.reviews[0].id
        api.failure = true
        await store.loadReview(id)
        #expect(store.reviews[id] == nil && store.detailErrors[id] != nil)
        #expect(store.feed.isEmpty)
        let p = api.page
        let malformed = SocialPage(reviews: p.reviews, users: [], items: p.items, universes: p.universes, nextCursor: nil)
        #expect(throws: AuthError.apiUnavailable) { try malformed.validate() }
    }
    @Test func appFeedUsesConfirmedReviewsWithoutMockReactionCounts() async {
        let api = SocialStub()
        let app = AppStore(socialAPI: api)
        await app.bootstrap()
        await app.social?.loadFeed()
        let review = api.page.reviews[0]
        #expect(app.homeFeed().map(\.id) == [review.id])
        #expect(app.user(review.user)?.name == "Alice")
        #expect(app.review(review.id)?.text == "Real review")
        #expect(app.reactionCounts(for: review.id).isEmpty)
        app.setReaction(.pow, for: review.id)
        #expect(app.userReaction(for: review.id) == nil)
        #expect(app.isSpoilerHidden(app.homeFeed()[0]))
    }
}
