import SwiftUI

/// Raiz da aba Clubes.
struct ClubsHomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CLUBES").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Text("Maratone junto com sua turma, no seu ritmo.")
                        .font(MVFont.body(13, weight: 600)).foregroundStyle(MV.C.muted)
                }

                if store.clubs.isEmpty {
                    Text("Você ainda não entrou em nenhum clube.")
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .comicCard(shadow: 0, dashed: true)
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.clubs) { club in
                            ClubSummaryRow(club: club)
                        }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
}

private struct ClubSummaryRow: View {
    let club: Club
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let uni = store.universe(club.uni), let week = store.currentClubWeek(club), let item = store.item(week.itemID) else {
            return AnyView(EmptyView())
        }
        let units = store.clubUnitsCompleted(clubID: club.id, userID: store.meID)

        return AnyView(
            Button { store.push(.club(club.id)) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CLUBE · \(uni.name.uppercased())").kicker(10).foregroundStyle(uni.inkColor.opacity(0.85))
                        Spacer()
                        Text("SEMANA \(club.currentWeek)/\(club.weeks.count)").font(MVFont.bold(10)).foregroundStyle(uni.inkColor.opacity(0.85))
                    }
                    Text(club.name).font(MVFont.display(20, width: 118)).foregroundStyle(uni.inkColor)
                    HStack(spacing: 10) {
                        PosterView(item: item, universe: uni, width: 40, height: 60, titleSize: 7, showLabel: false, shadow: 0)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(MVFont.bold(13)).foregroundStyle(uni.inkColor)
                            ComicProgress(value: week.totalUnits > 0 ? Double(units) / Double(week.totalUnits) : 0, fill: uni.inkColor, height: 8)
                        }
                    }
                    Text("\(club.memberIDs.count) membros · 1 item por semana")
                        .font(MVFont.body(11, weight: 600)).foregroundStyle(uni.inkColor.opacity(0.85))
                }
                .padding(14)
                .background(uni.color)
                .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
                .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.s, y: MV.Shadow.s))
            }
            .buttonStyle(.plain)
        )
    }
}
