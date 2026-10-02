import SwiftUI

struct CatalogSeriesSection: View {
    var universeID: String? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        let series = store.catalogSeries(in: universeID)
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("SÉRIES DE HQS")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                ForEach(series) { group in
                    Button { store.push(.catalogSeries(group.id)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.series.title).font(MVFont.bold(15))
                                Text(L10n.format("%1$@ · %2$@ edições", String(group.series.year), String(group.items.count)))
                                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.foregroundStyle(MV.C.ink).padding(14).comicCard()
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct CatalogSeriesView: View {
    let seriesID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                if let group = store.catalogSeries().first(where: { $0.id == seriesID }) {
                    Text(L10n.text("SÉRIE DE HQS")).kicker()
                    Text(group.series.title).font(MVFont.display(28, width: 118))
                    Text(L10n.format("%1$@ · %2$@ edições", String(group.series.year), String(group.items.count)))
                        .font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted)
                    Text(L10n.text("Edições em ordem de publicação. Registre a leitura de cada uma no diário para acompanhar seu progresso."))
                        .font(MVFont.body(13, weight: 500))
                    if let error = store.activityRefreshError { AuthErrorBanner(message: error) }
                    if store.activityLoadError == nil {
                        let read = store.registeredIssueCount(in: group)
                        Text(L10n.format("%1$@ de %2$@ edições registradas", String(read), String(group.items.count))).font(MVFont.bold(13))
                        ComicProgress(value: Double(read) / Double(group.items.count), fill: MV.C.marvel, height: 10)
                    }
                    ForEach(group.items) { item in
                        Button { store.push(.item(item.id)) } label: {
                            HStack(spacing: 12) {
                                PosterView(item: item, universe: store.universe(of: item), width: 42, height: 63, titleSize: 7)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(MVFont.bold(14))
                                    Text(store.myDiaryEntry(for: item.id) == nil ? L10n.text("Ainda não registrada") : L10n.text("Registrada no diário"))
                                        .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.foregroundStyle(MV.C.ink).padding(12).comicCard()
                        }.buttonStyle(.plain)
                    }
                } else {
                    Text(L10n.text("Esta série não está disponível no catálogo."))
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }
        .task { await store.refreshActivity() }
        .refreshable { await store.refreshActivity() }
    }
}
