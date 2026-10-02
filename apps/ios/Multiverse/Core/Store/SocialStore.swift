import Foundation
import Observation

/// Account-scoped feed and safety state; never falls back to prototype content.
@MainActor @Observable final class SocialStore {
    private let api: any SocialAPI
    private(set) var feedIDs: [String] = []
    private(set) var reviews: [String: Review] = [:]
    private(set) var users: [String: User] = [:]
    private(set) var items: [String: Item] = [:]
    private(set) var universes: [String: Universe] = [:]
    private(set) var nextCursor: String?
    private(set) var feedError: String?
    private(set) var isLoadingFeed = false
    private(set) var hasLoadedFeed = false
    private(set) var detailErrors: [String: String] = [:]
    private(set) var loadingDetails: Set<String> = []
    private(set) var publicDiary: Bool?
    private(set) var privacyError: String?
    private(set) var blocks: [SocialBlock] = []
    private(set) var blocksError: String?
    private(set) var actionError: String?
    private(set) var isMutating = false
    private var generation = 0
    private var privacyRevision = 0
    private var blocksRevision = 0
    private var loadingPrivacy = false
    private var loadingBlocks = false
    private(set) var commentPermission: CommentPermission?
    private(set) var interactions: [String: InteractionSummary] = [:]
    private(set) var commentCounts: [String: Int] = [:]
    private(set) var comments: [String: [RemoteComment]] = [:]
    private(set) var commentCursors: [String: String] = [:]
    private(set) var canComment: [String: Bool] = [:]
    private(set) var commentErrors: [String: String] = [:]
    private(set) var loadingComments: Set<String> = []
    private(set) var sendingComments: Set<String> = []
    private(set) var reacting: Set<String> = []
    private var interactionRevision = 0
    private var commentRevisions: [String: Int] = [:]
    init(api: any SocialAPI) { self.api = api }
    var feed: [Review] { feedIDs.compactMap { reviews[$0] } }
    private func merge(_ page: SocialPage) {
        for review in page.reviews {
            reviews[review.id] = review.display
            if let interaction = review.interaction { interactions[review.id] = interaction }
            if let count = review.commentCount { commentCounts[review.id] = count }
        }
        for user in page.users { users[user.id] = user }
        for item in page.items { items[item.id] = item }
        for universe in page.universes { universes[universe.id] = universe }
    }
    func invalidateFeed() {
        generation += 1
        feedIDs = []; reviews = [:]; nextCursor = nil
        loadingDetails = []; detailErrors = [:]
        hasLoadedFeed = false; isLoadingFeed = false; feedError = nil
        comments = [:]; commentCursors = [:]; canComment = [:]; commentErrors = [:]
        loadingComments = []; interactions = [:]; commentCounts = [:]
        interactionRevision += 1
    }
    func loadFeed(more: Bool = false) async {
        guard !isLoadingFeed, !more || nextCursor != nil else { return }
        let epoch = generation, cursor = more ? nextCursor : nil, revision = interactionRevision
        isLoadingFeed = true; feedError = nil
        defer { if epoch == generation { isLoadingFeed = false } }
        do {
            let page = try await api.fetchFeed(after: cursor)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            try page.validate()
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw AuthError.apiUnavailable }
            let confirmed = interactions
            merge(page)
            if revision != interactionRevision { interactions.merge(confirmed) { _, newer in newer } }
            let old = more ? feedIDs : []
            feedIDs = old + page.reviews.map(\.id).filter { !old.contains($0) }
            nextCursor = page.nextCursor; hasLoadedFeed = true
        } catch is CancellationError { return }
        catch { if epoch == generation { feedError = error.localizedDescription } }
    }
    func loadReview(_ id: String) async {
        guard !loadingDetails.contains(id) else { return }
        loadingDetails.insert(id); detailErrors[id] = nil
        let epoch = generation, revision = interactionRevision
        defer { if epoch == generation { loadingDetails.remove(id) } }
        do {
            let page = try await api.fetchReview(id: id)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            try page.validate()
            guard page.reviews.count == 1, page.reviews.first?.id == id else { throw SocialError.unavailable }
            let confirmed = interactions
            merge(page)
            if revision != interactionRevision { interactions.merge(confirmed) { _, newer in newer } }
        } catch is CancellationError { return }
        catch {
            if epoch == generation {
                // A denied detail must not leave readable cached text behind.
                reviews[id] = nil; feedIDs.removeAll { $0 == id }
                detailErrors[id] = error.localizedDescription
                comments[id] = nil; canComment[id] = nil; commentCursors[id] = nil
                commentRevisions[id, default: 0] += 1; loadingComments.remove(id)
            }
        }
    }
    func loadPrivacy() async {
        guard !loadingPrivacy else { return }
        loadingPrivacy = true; privacyError = nil
        let revision = privacyRevision
        defer { loadingPrivacy = false }
        do {
            let privacy = try await api.fetchPrivacy()
            try Task.checkCancellation()
            if revision == privacyRevision {
                publicDiary = privacy.publicDiary
                commentPermission = privacy.commentPermission.flatMap(CommentPermission.init(apiValue:))
            }
        } catch is CancellationError { return }
        catch { if revision == privacyRevision { privacyError = error.localizedDescription } }
    }
    func setPublicDiary(_ value: Bool) async -> Bool {
        guard !isMutating, publicDiary != nil else { return false }
        isMutating = true; privacyError = nil; privacyRevision += 1
        defer { isMutating = false }
        do {
            let receipt = try await api.savePrivacy(publicDiary: value)
            guard receipt.publicDiary == value else { throw SocialError.invalid }
            publicDiary = value
            commentPermission = receipt.commentPermission.flatMap(CommentPermission.init(apiValue:))
            invalidateFeed()
            return true
        } catch { privacyError = error.localizedDescription; return false }
    }
    func loadBlocks() async {
        guard !loadingBlocks else { return }
        loadingBlocks = true; blocksError = nil
        let revision = blocksRevision
        defer { if revision == blocksRevision { loadingBlocks = false } }
        do {
            let result = try await api.fetchBlocks()
            try Task.checkCancellation()
            guard revision == blocksRevision else { return }
            guard Set(result.users.map(\.id)).count == result.users.count else { throw SocialError.invalid }
            blocks = result.users
        } catch is CancellationError { return }
        catch { if revision == blocksRevision { blocksError = error.localizedDescription } }
    }
    func setBlock(_ id: String, blocked: Bool) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true; actionError = nil
        defer { isMutating = false }
        do {
            let receipt = try await api.setBlock(id: id, blocked: blocked)
            guard receipt.userID == id, receipt.blocked == blocked else { throw SocialError.invalid }
            blocksRevision += 1; loadingBlocks = false
            invalidateFeed()
            if !blocked { blocks.removeAll { $0.id == id } }
            return true
        } catch { actionError = error.localizedDescription; return false }
    }
    func report(_ id: String, authorID: String, reason: ReportReason, alsoBlock: Bool) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true; actionError = nil
        defer { isMutating = false }
        do {
            let receipt = try await api.reportReview(id: id, reason: reason.apiValue, alsoBlock: alsoBlock)
            guard receipt.reported, receipt.reviewID == id, receipt.blockedUserID == (alsoBlock ? authorID : nil) else { throw SocialError.invalid }
            blocksRevision += 1; loadingBlocks = false
            invalidateFeed()
            return true
        } catch { actionError = error.localizedDescription; return false }
    }

    func setCommentPermission(_ value: CommentPermission) async -> Bool {
        guard !isMutating, commentPermission != nil else { return false }
        isMutating = true; privacyError = nil; privacyRevision += 1
        defer { isMutating = false }
        do {
            let result = try await api.saveCommentPermission(value.apiValue)
            guard result.commentPermission == value.apiValue else { throw SocialError.invalid }
            commentPermission = value; publicDiary = result.publicDiary
            return true
        } catch { privacyError = error.localizedDescription; return false }
    }
    func loadComments(_ id: String, more: Bool = false) async {
        guard !loadingComments.contains(id), !more || commentCursors[id] != nil else { return }
        let epoch = generation, cursor = more ? commentCursors[id] : nil, revision = interactionRevision
        let commentRevision = commentRevisions[id, default: 0]
        loadingComments.insert(id); commentErrors[id] = nil
        defer { if epoch == generation && commentRevision == commentRevisions[id, default: 0] { loadingComments.remove(id) } }
        do {
            let page = try await api.fetchComments(reviewID: id, after: cursor)
            try Task.checkCancellation()
            guard epoch == generation, commentRevision == commentRevisions[id, default: 0] else { return }
            try page.validate(review: id)
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw SocialError.invalid }
            let previous = more ? (comments[id] ?? []) : []
            let oldIDs = Set(previous.map(\.id))
            comments[id] = previous + page.comments.filter { !oldIDs.contains($0.id) }
            for user in page.users { users[user.id] = user }
            for comment in page.comments where revision == interactionRevision || interactions[comment.id] == nil { interactions[comment.id] = comment.interaction }
            canComment[id] = page.canComment; commentCursors[id] = page.nextCursor
        } catch is CancellationError { return }
        catch {
            if epoch == generation && commentRevision == commentRevisions[id, default: 0] {
                commentErrors[id] = error.localizedDescription
                if error as? SocialError == .unavailable {
                    comments[id] = nil; canComment[id] = nil; reviews[id] = nil
                    feedIDs.removeAll { $0 == id }; detailErrors[id] = error.localizedDescription
                }
            }
        }
    }
    func postComment(reviewID: String, id: String, text: String, spoiler: Bool) async -> Bool {
        guard !sendingComments.contains(reviewID), canComment[reviewID] == true else { return false }
        sendingComments.insert(reviewID); commentErrors[reviewID] = nil
        let epoch = generation
        defer { sendingComments.remove(reviewID) }
        do {
            let receipt = try await api.postComment(reviewID: reviewID, id: id, text: text, spoiler: spoiler)
            guard epoch == generation else { return false }
            guard receipt.saved, receipt.reviewID == reviewID, receipt.commentID == id else { throw SocialError.invalid }
            commentRevisions[reviewID, default: 0] += 1
            loadingComments.remove(reviewID)
            await loadComments(reviewID)
            await loadReview(reviewID)
            return true
        } catch {
            if epoch == generation { commentErrors[reviewID] = error.localizedDescription }
            return false
        }
    }
    func setReaction(reviewID: String, commentID: String? = nil, reaction: String?, liked: Bool) async -> Bool {
        let target = commentID ?? reviewID
        guard !reacting.contains(target) else { return false }
        reacting.insert(target); actionError = nil
        let epoch = generation
        defer { reacting.remove(target) }
        do {
            let result = try await api.setReaction(reviewID: reviewID, commentID: commentID, reaction: reaction, liked: liked)
            guard epoch == generation else { return false }
            try result.validate(target: target)
            guard result.myReaction == reaction, result.liked == liked else { throw SocialError.invalid }
            interactionRevision += 1; interactions[target] = result
            return true
        } catch {
            if epoch == generation { actionError = error.localizedDescription }
            return false
        }
    }
    func reportComment(reviewID: String, id: String, authorID: String, reason: ReportReason, alsoBlock: Bool) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true; actionError = nil
        defer { isMutating = false }
        do {
            let receipt = try await api.reportComment(reviewID: reviewID, id: id, reason: reason.apiValue, alsoBlock: alsoBlock)
            guard receipt.reported, receipt.reviewID == reviewID, receipt.commentID == id, receipt.blockedUserID == (alsoBlock ? authorID : nil) else { throw SocialError.invalid }
            blocksRevision += 1; loadingBlocks = false
            invalidateFeed()
            return true
        } catch { actionError = error.localizedDescription; return false }
    }
}
