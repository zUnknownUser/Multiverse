import SwiftUI

/// "Seus clubes" — card compacto na Home, abre o clube direto.
struct MyClubsCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Seus clubes", trailing: "VER TUDO") { store.goToTab(.clubs) }
            VStack(spacing: 10) {
                ForEach(store.clubs) { club in
                    row(club: club)
                }
            }
        }
    }

    @ViewBuilder
    private func row(club: Club) -> some View {
        guard let uni = store.universe(club.uni), let week = store.currentClubWeek(club), let item = store.item(week.itemID) else {
            return AnyView(EmptyView())
        }
        let units = store.clubUnitsCompleted(clubID: club.id, userID: store.meID)

        return AnyView(
            Button { store.push(.club(club.id)) } label: {
                HStack(spacing: 12) {
                    PosterView(item: item, universe: uni, width: 44, height: 66, titleSize: 8, showLabel: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(club.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        Text("Semana \(club.currentWeek) de \(club.weeks.count) · \(item.title)")
                            .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                        ComicProgress(value: week.totalUnits > 0 ? Double(units) / Double(week.totalUnits) : 0, fill: uni.color, height: 8)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .comicCard(shadow: MV.Shadow.s)
        )
    }
}
