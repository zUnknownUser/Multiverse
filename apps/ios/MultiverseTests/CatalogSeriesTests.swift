import Foundation
import Testing
@testable import Multiverse

@MainActor private final class SeriesCatalogStub: CatalogAPI {
    let snapshot: CatalogSnapshot
    init(_ items: [Item]) {
        snapshot = .init(version: 1, locale: "pt-BR", universes: SampleData.load().universes.filter { $0.id == "marvel" }, comingSoon: [], items: items)
    }
    func fetchCatalog() async throws -> CatalogSnapshot { snapshot }
}
@MainActor private final class SeriesActivityStub: ActivityAPI {
    var snapshot = ActivitySnapshot(entries: [], reviews: [], items: [], universes: [], followerCount: 0)
    var failure = false
    func fetchActivity() async throws -> ActivitySnapshot {
        if failure { throw AuthError.networkUnavailable }
        return snapshot
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot { throw AuthError.apiUnavailable }
}

@Suite(.serialized) @MainActor struct CatalogSeriesTests {
    private func issue(_ number: Int) -> Item {
        Item(id: "issue-\(number)", uni: "marvel", type: "HQ", title: "Guerra Civil #\(number)", year: SampleData.load().items[0].year,
             avg: 0, canon: "—", desc: "", logCount: 0, reviewCount: 0,
             series: ItemSeries(id: "metron-402", title: "Guerra Civil", year: 2006, number: String(number), position: number))
    }
    @Test func seriesOrderIsNumericAndRevisitsCountOnlyOnce() {
        let store = AppStore()
        store.items = [issue(10), issue(2), issue(1)]
        store.diary = [DiaryEntry(id: UUID(), itemId: "issue-2", loggedAt: .now, rating: 4), DiaryEntry(id: UUID(), itemId: "issue-2", loggedAt: .now, rating: 5)]
        let series = store.catalogSeries()
        #expect(series.count == 1)
        #expect(series[0].items.map(\.id) == ["issue-1", "issue-2", "issue-10"])
        #expect(store.registeredIssueCount(in: series[0]) == 1)
        #expect(store.catalogSeries(in: "dc").isEmpty)
        store.diary.append(.init(id: UUID(), itemId: "issue-1", loggedAt: .now, rating: 3))
        #expect(store.registeredIssueCount(in: series[0]) == 2)
    }
    @Test func oldCatalogsDecodeAndInvalidSeriesMetadataIsRejected() throws {
        let json = "{\"id\":\"old\",\"uni\":\"marvel\",\"type\":\"HQ\",\"title\":\"Old\",\"year\":\"2006\",\"avg\":0,\"canon\":\"—\",\"desc\":\"\"}"
        #expect(try JSONDecoder().decode(Item.self, from: Data(json.utf8)).series == nil)
        var invalid = issue(1)
        invalid.series = ItemSeries(id: "metron-402", title: "Guerra Civil", year: 2006, number: "1", position: 0)
        #expect(throws: CatalogError.unavailable) { try SeriesCatalogStub([invalid]).snapshot.validate() }
        #expect(try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(issue(1))).series == issue(1).series)
    }
    @Test func diaryRefreshRetainsSeriesAndConfirmedProgressAcrossFailureAndReopening() async {
        let first = issue(1), second = issue(2)
        let activity = SeriesActivityStub()
        activity.snapshot = .init(entries: [.init(id: UUID(), itemId: first.id, loggedAt: .now, rating: 4)], reviews: [], items: [first], universes: SampleData.load().universes.filter { $0.id == "marvel" }, followerCount: 0)
        for _ in 0..<2 {
            activity.failure = false
            let store = AppStore(catalogAPI: SeriesCatalogStub([second, first]), activityAPI: activity)
            await store.bootstrap()
            #expect(store.item(first.id)?.series == first.series)
            #expect(store.registeredIssueCount(in: store.catalogSeries()[0]) == 1)
            #expect(store.searchResults(query: "guerra civil #2", filter: .works).rows.map(\.id) == [second.id])
            activity.failure = true
            await store.refreshActivity()
            #expect(store.activityRefreshError != nil)
            #expect(store.registeredIssueCount(in: store.catalogSeries()[0]) == 1)
            store.push(.catalogSeries("metron-402"))
            #expect(store.homePath == [.catalogSeries("metron-402")])
        }
    }
}
