import SwiftUI

struct CatalogSeriesSection: View {
    var universeID: String? = nil
    @Environment(AppStore.self) private var store
    var body: some View {
        let series = store.catalogSeries(in: universeID)
        if !series.isEmpty || store.catalogStore.paginated {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("SÉRIES DE HQS")).font(MVFont.section(17)).foregroundStyle(MV.C.ink)
                ForEach(series) { group in
                    Button { store.push(.catalogSeries(group.id)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.series.title).font(MVFont.bold(15))
                                Text(L10n.format("%1$@ · %2$@ edições", String(group.series.year), String(group.itemCount)))
                                    .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.foregroundStyle(MV.C.ink).padding(14).comicCard()
                    }.buttonStyle(.plain)
                }
                if store.catalogStore.paginated {
                    CatalogPageControls(state: store.catalogStore.seriesPage(universeID)) { more in await store.catalogStore.loadSeries(universe: universeID, more: more) }
                }
            }.task(id: "\(universeID ?? "all")|\(store.catalogStore.generation)") { await store.catalogStore.loadSeries(universe: universeID) }
        }
    }
}

struct CatalogSeriesView: View {
    let seriesID: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 16) {
                if loading && store.catalogStore.paginated { ProgressView() }
                if let error { AuthErrorBanner(message: error); Button(L10n.text("TENTAR DE NOVO")) { Task { await load() } } }
                if let group = store.catalogSeriesSummary(id: seriesID) {
                    Text(L10n.text("SÉRIE DE HQS")).kicker()
                    Text(group.series.title).font(MVFont.display(28, width: 118))
                    Text(L10n.format("%1$@ · %2$@ edições", String(group.series.year), String(group.itemCount)))
                        .font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.muted)
                    Text(L10n.text("Edições em ordem de publicação. Registre a leitura de cada uma no diário para acompanhar seu progresso."))
                        .font(MVFont.body(13, weight: 500))
                    if let error = store.activityRefreshError { AuthErrorBanner(message: error) }
                    if store.activityLoadError == nil {
                        let read = store.registeredIssueCount(in: group)
                        Text(L10n.format("%1$@ de %2$@ edições registradas", String(read), String(group.itemCount))).font(MVFont.bold(13))
                        ComicProgress(value: Double(read) / Double(max(1, group.itemCount)), fill: MV.C.marvel, height: 10)
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
                    if store.catalogStore.paginated {
                        CatalogPageControls(state: store.catalogStore.page(.init(series: seriesID))) { more in await store.catalogStore.load(.init(series: seriesID), more: more) }
                    }
                } else if !loading && error == nil {
                    Text(L10n.text("Esta série não está disponível no catálogo."))
                }
            }.foregroundStyle(MV.C.ink).padding(MV.pad)
        }
        .task(id: "\(seriesID)|\(store.catalogStore.generation)") { await load() }
        .refreshable { await load(refresh: true) }
    }

    private func load(refresh: Bool = false) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            try await store.catalogStore.loadSeries(id: seriesID)
            await store.catalogStore.load(.init(series: seriesID), refresh: refresh)
            await store.refreshActivity()
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
