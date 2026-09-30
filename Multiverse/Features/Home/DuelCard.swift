import SwiftUI

/// "Duelo do dia" — Home.
struct DuelCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let duel = store.currentDuel
        let a = store.item(duel.a)!, b = store.item(duel.b)!
        let percents = store.duelPercents()
        let voted = percents != nil

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DUELO DO DIA · \(store.currentDuelPosition + 1)/\(store.duels.count)")
                    .kicker(11).foregroundStyle(MV.C.card)
                Spacer()
                Text(store.duelTotalVotesLabel()).font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.card.opacity(0.85))
            }
            .padding(12)
            .background(MV.C.ink)

            VStack(alignment: .leading, spacing: 12) {
                Text(duel.question).font(MVFont.black(19)).foregroundStyle(MV.C.ink)

                ZStack {
                    HStack(spacing: 10) {
                        DuelSide(item: a, side: 0, percent: percents?[0], voted: voted, chosen: store.duelVotes[store.currentDuelPosition] == 0)
                        DuelSide(item: b, side: 1, percent: percents?[1], voted: voted, chosen: store.duelVotes[store.currentDuelPosition] == 1)
                    }
                    Text("VS")
                        .font(MVFont.black(15))
                        .foregroundStyle(MV.C.card)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(MV.C.ink))
                        .overlay(Circle().strokeBorder(MV.C.paper, lineWidth: MV.stroke))
                }

                if let note = store.duelResultNote() {
                    HStack {
                        Text(note).font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
                        Spacer()
                        Button { store.nextDuel() } label: {
                            Text("PRÓXIMO DUELO →").font(MVFont.bold(12)).foregroundStyle(MV.C.ink).underline()
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Toque num lado pra votar").font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
                }
            }
            .padding(14)
        }
        .background(MV.C.card)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.ink).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }
}

private struct DuelSide: View {
    let item: Item
    let side: Int
    let percent: Int?
    let voted: Bool
    let chosen: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        let uni = store.universe(of: item)
        VStack(spacing: 6) {
            PosterView(item: item, universe: uni, width: 170, height: 170, titleSize: 13, shadow: 0)
            if let percent {
                Text("\(percent)%").font(MVFont.black(28)).foregroundStyle(uni.color)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(voted && !chosen ? 0.55 : 1)
        .scaleEffect(chosen ? 1.02 : 1)
        .rotationEffect(.degrees(chosen ? -1.5 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: chosen)
        .burstOnTap("KRAK!", color: uni.color, when: !voted) {
            store.voteDuel(side)
        }
    }
}
