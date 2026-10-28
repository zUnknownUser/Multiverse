import Foundation
import Testing
@testable import Multiverse

@MainActor private final class PagedActivityStub: ActivityAPI {
    var snapshot: ActivitySnapshot
    var failure = false
    var pending: CheckedContinuation<ActivitySnapshot, any Error>?
    var hold = false
    var cursors: [String?] = []
    init(_ snapshot: ActivitySnapshot) { self.snapshot = snapshot }
    func fetchActivity() async throws -> ActivitySnapshot { snapshot }
    func fetchActivityPage(query: DiaryQuery, after: String?) async throws -> ActivitySnapshot {
        cursors.append(after)
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        if failure { throw AuthError.networkUnavailable }
        return snapshot
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot { snapshot }
    func updateLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot { snapshot }
    func deleteLog(id: UUID) async throws -> DeleteLogReceipt { .init(id: id, state: snapshot) }
}

@MainActor struct DiaryStoreTests {
    private func page(_ entries: [DiaryEntry], latest: [DiaryEntry], cursor: String? = nil) -> ActivitySnapshot {
        let sample = SampleData.load()
        return .init(entries: entries, reviews: [], items: sample.items, universes: sample.universes, followerCount: 2,
                     summary: .init(total: 80, reviewCount: 0, averageRating: 0, years: [2025], recentReviews: [], latestEntries: latest,
                                    buckets: [.init(year: 2025, type: "HQ", universe: "marvel", count: 80)], activeDays: []), nextCursor: cursor)
    }

    @Test func pageDoesNotTruncateCountsProgressOrLatestEntryAndRetriesKeepHistory() async throws {
        let first = DiaryEntry(itemId: "m-civil", loggedAt: .now, rating: 4)
        let old = DiaryEntry(itemId: "d-watch", loggedAt: .distantPast, rating: 5, liked: true)
        // Use a catalog item that exists, independently of seed naming changes.
        let other = SampleData.load().items.first { $0.id != first.itemId }!
        let latest = DiaryEntry(id: old.id, itemId: other.id, loggedAt: old.loggedAt, rating: 5, liked: true)
        let api = PagedActivityStub(page([first], latest: [first, latest], cursor: "next"))
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        #expect(store.diary.count == 1 && store.diaryCount == 80)
        #expect(store.isSeen(other.id))
        #expect(store.myDiaryEntry(for: other.id)?.id == latest.id)
        #expect(store.profileData(for: store.meID).stats.first?.0 == "80")
        api.failure = true
        await store.loadDiaryPage(query: .init(), more: true)
        #expect(store.diary.count == 1 && store.diaryStore.nextCursor == "next")
        #expect(store.diaryStore.pageError != nil && !store.diaryStore.isLoadingPage)
        api.failure = false
        api.snapshot = page([first, latest], latest: [first, latest])
        await store.loadDiaryPage(query: .init(), more: true)
        #expect(store.diary.map(\.id) == [first.id, latest.id])
        #expect(store.diaryCount == 80 && store.diaryStore.nextCursor == nil)
        #expect(store.diaryStore.pageError == nil)
        #expect(api.cursors.compactMap { $0 } == ["next", "next"])
    }

    @Test func repeatedCursorCannotTrapPaginationAndFailedFilterKeepsConfirmedData() async {
        let entry = DiaryEntry(itemId: "m-civil", loggedAt: .now, rating: 4)
        let api = PagedActivityStub(page([entry], latest: [entry], cursor: "repeat"))
        let store = AppStore(activityAPI: api)
        await store.bootstrap()
        await store.loadDiaryPage(query: .init(), more: true)
        #expect(store.diaryStore.pageError != nil && store.diary.count == 1)
        api.failure = true
        await store.loadDiaryPage(query: .init(text: "no match"))
        #expect(store.diaryStore.query == DiaryQuery())
        #expect(store.diaryStore.pageError != nil && store.diaryCount == 80)
    }

    @Test func pageStartedBeforeMutationCannotRestoreDeletedEntries() async throws {
        let entry = DiaryEntry(itemId: "m-civil", loggedAt: .now, rating: 4)
        let api = PagedActivityStub(page([entry], latest: [entry]))
        let store = DiaryStore(api: api, ownerID: "duda")
        api.hold = true
        let read = Task { await store.loadPage(query: .init()) }
        for _ in 0..<100 where api.pending == nil { await Task.yield() }
        let pending = try #require(api.pending)
        store.revision += 1
        pending.resume(returning: api.snapshot)
        #expect(await read.value == nil)
        #expect(store.entries.isEmpty)
    }
}
