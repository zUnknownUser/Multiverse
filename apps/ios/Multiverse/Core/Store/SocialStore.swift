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
    init(api: any SocialAPI) { self.api = api }
    var feed: [Review] { feedIDs.compactMap { reviews[$0] } }
    private func merge(_ page: SocialPage) {
        for review in page.reviews { reviews[review.id] = review.display }
        for user in page.users { users[user.id] = user }
        for item in page.items { items[item.id] = item }
        for universe in page.universes { universes[universe.id] = universe }
    }
    func invalidateFeed() {
        generation += 1
        feedIDs = []; reviews = [:]; nextCursor = nil
        loadingDetails = []; detailErrors = [:]
        hasLoadedFeed = false; isLoadingFeed = false; feedError = nil
    }
    func loadFeed(more: Bool = false) async {
        guard !isLoadingFeed, !more || nextCursor != nil else { return }
        let epoch = generation, cursor = more ? nextCursor : nil
        isLoadingFeed = true; feedError = nil
        defer { if epoch == generation { isLoadingFeed = false } }
        do {
            let page = try await api.fetchFeed(after: cursor)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            try page.validate()
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw AuthError.apiUnavailable }
            merge(page)
            let old = more ? feedIDs : []
            feedIDs = old + page.reviews.map(\.id).filter { !old.contains($0) }
            nextCursor = page.nextCursor; hasLoadedFeed = true
        } catch is CancellationError { return }
        catch { if epoch == generation { feedError = error.localizedDescription } }
    }
    func loadReview(_ id: String) async {
        guard !loadingDetails.contains(id) else { return }
        loadingDetails.insert(id); detailErrors[id] = nil
        let epoch = generation
        defer { if epoch == generation { loadingDetails.remove(id) } }
        do {
            let page = try await api.fetchReview(id: id)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            try page.validate()
            guard page.reviews.count == 1, page.reviews.first?.id == id else { throw SocialError.unavailable }
            merge(page)
        } catch is CancellationError { return }
        catch {
            if epoch == generation {
                // A denied detail must not leave readable cached text behind.
                reviews[id] = nil; feedIDs.removeAll { $0 == id }
                detailErrors[id] = error.localizedDescription
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
            if revision == privacyRevision { publicDiary = privacy.publicDiary }
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
}
