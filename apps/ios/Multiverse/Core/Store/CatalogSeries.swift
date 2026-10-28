import Foundation

struct CatalogSeriesSummary: Identifiable {
    let series: ItemSeries
    let items: [Item]
    var total: Int? = nil
    var itemCount: Int { total ?? items.count }
    var id: String { series.id }
}

extension AppStore {
    /// Only currently published catalog items appear; archived diary references stay in the diary.
    func catalogSeries(in universeID: String? = nil) -> [CatalogSeriesSummary] {
        if catalogStore.paginated {
            return catalogStore.seriesPage(universeID).values.map { catalogSeriesSummary($0) }
        }
        let eligible = items.filter { $0.series?.isValid == true && (universeID == nil || $0.uni == universeID) }
        return Dictionary(grouping: eligible, by: { $0.series!.id }).values.map { members in
            let sorted = members.sorted {
                if $0.series!.position == $1.series!.position { return $0.id < $1.id }
                return $0.series!.position < $1.series!.position
            }
            return CatalogSeriesSummary(series: sorted[0].series!, items: sorted)
        }.sorted { $0.series.title.localizedStandardCompare($1.series.title) == .orderedAscending }
    }

    private func catalogSeriesSummary(_ record: CatalogSeriesRecord) -> CatalogSeriesSummary {
        .init(series: .init(id: record.id, title: record.title, year: record.year, number: "1", position: 1),
              items: catalogStore.page(.init(series: record.id)).values, total: record.total)
    }
    func catalogSeriesSummary(id: String) -> CatalogSeriesSummary? {
        if catalogStore.paginated { return catalogStore.seriesByID[id].map { catalogSeriesSummary($0) } }
        return catalogSeries().first { $0.id == id }
    }

    func registeredIssueCount(in series: CatalogSeriesSummary) -> Int {
        let registered = registeredItemIDs
        if catalogStore.paginated { return registered.filter { catalogStore.reference($0)?.seriesID == series.id }.count }
        return series.items.filter { registered.contains($0.id) }.count
    }
}
