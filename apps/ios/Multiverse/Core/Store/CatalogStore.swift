import Foundation
import Observation

@MainActor @Observable final class CatalogPageState<Value: Sendable> {
    var values: [Value] = []
    var total = 0
    var nextCursor: String?
    var loading = false
    var loaded = false
    var error: String?
    var revision = 0
}

/// Catalog ownership stays separate from account activity and navigation.
@MainActor @Observable final class CatalogStore {
    private let api: (any CatalogAPI)?
    var paginated: Bool { api?.usesPagination == true }
    var universes: [Universe] = []
    var items: [Item] = [] // Bootstrap selection; not an index of the entire catalog.
    var upcoming: [UpcomingUniverse] = []
    var itemsByID: [String: Item] = [:]
    var universesByID: [String: Universe] = [:]
    private(set) var discoveryIDs: [String]?
    private(set) var onboardingIDs: [String]?
    private(set) var topRatedIDs: [String]?
    private(set) var aggregateAverage: Double?
    private(set) var references: [String: CatalogReference] = [:]
    private(set) var missingIDs: Set<String> = []
    private(set) var resolvingIDs: Set<String> = []
    private(set) var itemErrors: [String: String] = [:]
    @ObservationIgnored private var pages: [CatalogQuery: CatalogPageState<Item>] = [:]
    @ObservationIgnored private var seriesPages: [String: CatalogPageState<CatalogSeriesRecord>] = [:]
    private(set) var seriesByID: [String: CatalogSeriesRecord] = [:]
    private var publishedIDs: Set<String> = []
    private var epoch = 0
    var generation: Int { epoch }
    init(api: (any CatalogAPI)? = nil) { self.api = api }

    func install(_ snapshot: CatalogSnapshot) {
        epoch += 1
        universes = snapshot.universes; items = snapshot.items; upcoming = snapshot.comingSoon
        universesByID = Dictionary(uniqueKeysWithValues: universes.map { ($0.id, $0) })
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        publishedIDs = Set(items.map(\.id))
        references = [:]; missingIDs = []; resolvingIDs = []; itemErrors = [:]
        pages = [:]; seriesPages = [:]; seriesByID = [:]
        discoveryIDs = snapshot.discoveryIDs; onboardingIDs = snapshot.onboardingIDs
        topRatedIDs = snapshot.topRatedIDs; aggregateAverage = snapshot.aggregateAverage
    }
    func merge(_ incoming: [Item]) { for item in incoming { publishedIDs.insert(item.id); itemsByID[item.id] = item; missingIDs.remove(item.id); itemErrors[item.id] = nil } }
    func applyReferences(_ values: [CatalogReference]) { publishedIDs.subtract(Set(references.keys).subtracting(values.map(\.id))); references = Dictionary(values.map { ($0.id,$0) }, uniquingKeysWith: { _, new in new }) }
    func reference(_ id: String) -> CatalogReference? {
        guard !missingIDs.contains(id) else { return nil }
        if let value = references[id] { return value }
        guard publishedIDs.contains(id), let item = itemsByID[id] else { return nil }
        return .init(id: id, uni: item.uni, type: item.type, seriesID: item.series?.id)
    }
    func page(_ query: CatalogQuery) -> CatalogPageState<Item> {
        _ = epoch
        if let page = pages[query] { return page }
        let page = CatalogPageState<Item>(); pages[query] = page; return page
    }
    func seriesPage(_ universe: String?) -> CatalogPageState<CatalogSeriesRecord> {
        _ = epoch
        let key = universe ?? "all"
        if let page = seriesPages[key] { return page }
        let page = CatalogPageState<CatalogSeriesRecord>(); seriesPages[key] = page; return page
    }
    private func validate(_ items: [Item], locale: String) throws {
        guard locale == L10n.language() else { throw CatalogError.changed }
        try CatalogSnapshot(version: 1, locale: locale, universes: universes, comingSoon: [], items: items).validate()
    }
    func load(_ query: CatalogQuery, more: Bool = false, refresh: Bool = false) async {
        guard let api, paginated else { return }
        let state = page(query)
        guard more ? (!state.loading && state.nextCursor != nil) : (!state.loaded || refresh) else { return }
        state.loading = true; state.error = nil; state.revision += 1
        let revision = state.revision, epoch = epoch, cursor = more ? state.nextCursor : nil
        defer { if state.revision == revision { state.loading = false } }
        do {
            let result = try await api.fetchItems(query: query, after: cursor)
            try Task.checkCancellation()
            guard epoch == self.epoch, state.revision == revision else { return }
            try validate(result.items, locale: result.locale)
            guard result.total >= result.items.count, result.items.count <= 30,
                  result.nextCursor == nil || !result.items.isEmpty,
                  cursor == nil || result.nextCursor != cursor,
                  result.items.allSatisfy({ (query.universe == nil || $0.uni == query.universe) && (query.series == nil || $0.series?.id == query.series) }) else { throw CatalogError.unavailable }
            let known = Set(state.values.map(\.id))
            state.values = more ? state.values + result.items.filter { !known.contains($0.id) } : result.items
            state.total = result.total; state.nextCursor = result.nextCursor; state.loaded = true
            merge(result.items)
        } catch is CancellationError { }
        catch { if epoch == self.epoch, state.revision == revision { state.error = error.localizedDescription } }
    }
    private func validSeries(_ series: CatalogSeriesRecord) -> Bool {
        !series.id.isEmpty && !series.title.isEmpty && series.total > 0 && universesByID[series.universe] != nil && (1900...2100).contains(series.year)
    }
    func loadSeries(universe: String? = nil, more: Bool = false, refresh: Bool = false) async {
        guard let api, paginated else { return }
        let state = seriesPage(universe)
        guard more ? (!state.loading && state.nextCursor != nil) : (!state.loaded || refresh) else { return }
        state.loading = true; state.error = nil; state.revision += 1
        let revision = state.revision, epoch = epoch, cursor = more ? state.nextCursor : nil
        defer { if state.revision == revision { state.loading = false } }
        do {
            let result = try await api.fetchSeries(universe: universe, after: cursor)
            try Task.checkCancellation()
            guard epoch == self.epoch, state.revision == revision else { return }
            guard result.locale == L10n.language(), result.total >= result.series.count, result.series.count <= 20,
                  Set(result.series.map(\.id)).count == result.series.count,
                  result.series.allSatisfy({ validSeries($0) && (universe == nil || $0.universe == universe) }),
                  result.nextCursor == nil || !result.series.isEmpty,
                  cursor == nil || result.nextCursor != cursor else { throw CatalogError.unavailable }
            let known = Set(state.values.map(\.id))
            state.values = more ? state.values + result.series.filter { !known.contains($0.id) } : result.series
            state.total = result.total; state.nextCursor = result.nextCursor; state.loaded = true
            for series in result.series { seriesByID[series.id] = series }
        } catch is CancellationError { }
        catch { if epoch == self.epoch, state.revision == revision { state.error = error.localizedDescription } }
    }
    func loadSeries(id: String) async throws {
        guard let api, paginated else { return }
        let epoch = epoch
        let result = try await api.fetchSeries(id: id)
        try Task.checkCancellation()
        guard epoch == self.epoch else { throw CancellationError() }
        guard result.id == id, validSeries(result) else { throw CatalogError.unavailable }
        seriesByID[id] = result
    }
    /// Exact references are resolved in bounded batches, never by traversing the global catalog.
    func resolve(_ ids: [String], refresh: Bool = false) async {
        guard let api, paginated else { return }
        let pending = Set(ids).filter { !resolvingIDs.contains($0) && (refresh || (itemsByID[$0] == nil && !missingIDs.contains($0))) }.sorted()
        let epoch = epoch
        resolvingIDs.formUnion(pending)
        defer { if epoch == self.epoch { resolvingIDs.subtract(pending) } }
        for start in stride(from: 0, to: pending.count, by: 50) {
            let batch = Array(pending[start..<min(start+50,pending.count)])
            for id in batch { itemErrors[id] = nil }
            do {
                // Shared reference reads outlive the originating screen so another
                // consumer never inherits an abandoned loading state.
                let result = try await Task { try await api.resolveItems(ids: batch) }.value
                guard epoch == self.epoch else { return }
                try validate(result.items, locale: result.locale)
                let found = Set(result.items.map(\.id)), missing = Set(result.missingIDs)
                guard missing.count == result.missingIDs.count, found.isDisjoint(with: missing), found.union(missing) == Set(batch) else { throw CatalogError.unavailable }
                merge(result.items)
                missingIDs.formUnion(missing)
                for id in missing { itemsByID[id] = nil }
            } catch is CancellationError { return }
            catch {
                guard epoch == self.epoch else { return }
                for id in batch { itemErrors[id] = error.localizedDescription }
            }
        }
    }
}
