import Foundation
import Observation

/// Owns diary state independently of navigation, catalog and social features.
@MainActor @Observable
final class DiaryStore {
    private let api: (any ActivityAPI)?
    private let ownerID: String
    init(api: (any ActivityAPI)? = nil, ownerID: String = "") {
        self.api = api
        self.ownerID = ownerID
    }
    var loadError: String?
    var refreshError: String?
    var isRefreshing = false
    var revision = 0
    var saveError: String?
    var isSaving = false
    var isDeleting = false
    var pendingDeletion: DiaryEntry?
    var deleteError: String?
    var reviews: [UUID: ActivityReview] = [:]
    var followerCount = 0
    var entries: [DiaryEntry] = []
    var summary: ActivitySummary?
    var nextCursor: String?
    var query = DiaryQuery()
    var isLoadingPage = false
    var pageError: String?

    var totalCount: Int { summary?.total ?? entries.count }
    var latestEntries: [DiaryEntry] { summary?.latestEntries ?? entries }

    /// A newer query or mutation invalidates a pending page, including its errors.
    func loadPage(query requestedQuery: DiaryQuery, more: Bool = false) async -> ActivitySnapshot? {
        guard let api, !isSaving, !isDeleting else { return nil }
        if more && (isLoadingPage || nextCursor == nil || requestedQuery != query) { return nil }
        revision += 1
        let requestRevision = revision
        let cursor = more ? nextCursor : nil
        isLoadingPage = true
        pageError = nil
        defer { if requestRevision == revision { isLoadingPage = false } }
        do {
            let snapshot = try await api.fetchActivityPage(query: requestedQuery, after: cursor)
            try Task.checkCancellation()
            guard requestRevision == revision else { return nil }
            try snapshot.validate(for: ownerID)
            guard cursor == nil || snapshot.nextCursor != cursor else { throw AuthError.apiUnavailable }
            query = requestedQuery
            return snapshot
        } catch is CancellationError { return nil
        } catch {
            if requestRevision == revision { pageError = error.localizedDescription }
            return nil
        }
    }

    func fetchReviews(itemID: String? = nil, universeID: String? = nil) async throws -> [Review] {
        guard let api else { return [] }
        let snapshot = try await api.fetchReviews(itemID: itemID, universeID: universeID)
        try Task.checkCancellation()
        try snapshot.validate(for: ownerID)
        return snapshot.reviews.filter { review in
            (itemID == nil || review.item == itemID) &&
            (universeID == nil || snapshot.items.first(where: { $0.id == review.item })?.uni == universeID)
        }.prefix(5).map(\.display)
    }

    func apply(_ snapshot: ActivitySnapshot, appending: Bool = false) {
        let known = Set(entries.map(\.id))
        entries = appending ? entries + snapshot.entries.filter { !known.contains($0.id) } : snapshot.entries
        let incoming = Dictionary(uniqueKeysWithValues: snapshot.reviews.compactMap { review in review.entryId.map { ($0, review) } })
        reviews = appending ? reviews.merging(incoming) { _, new in new } : incoming
        followerCount = snapshot.followerCount
        summary = snapshot.summary
        nextCursor = snapshot.nextCursor
        pageError = nil
    }
}
