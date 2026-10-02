import Foundation

struct CatalogSeriesSummary: Identifiable {
    let series: ItemSeries
    let items: [Item]
    var id: String { series.id }
}

extension AppStore {
    /// Only currently published catalog items appear; archived diary references stay in the diary.
    func catalogSeries(in universeID: String? = nil) -> [CatalogSeriesSummary] {
        let eligible = items.filter { $0.series?.isValid == true && (universeID == nil || $0.uni == universeID) }
        return Dictionary(grouping: eligible, by: { $0.series!.id }).values.map { members in
            let sorted = members.sorted {
                if $0.series!.position == $1.series!.position { return $0.id < $1.id }
                return $0.series!.position < $1.series!.position
            }
            return CatalogSeriesSummary(series: sorted[0].series!, items: sorted)
        }.sorted { $0.series.title.localizedStandardCompare($1.series.title) == .orderedAscending }
    }

    func registeredIssueCount(in series: CatalogSeriesSummary) -> Int {
        let registered = Set(diary.map(\.itemId))
        return series.items.filter { registered.contains($0.id) }.count
    }
}
