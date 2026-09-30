import SwiftUI

/// "Debate da semana" — Home. Sempre sobre O Cataclismo (Warcraft), como no protótipo.
struct DebateCard: View {
    @Environment(AppStore.self) private var store
    private let options = StaticContent.weeklyDebateOptions

    var body: some View {
        let item = store.item("e-cataclismo")!
        let uni = store.universe(of: item)
        let percents = store.weeklyPollPercents()

        VStack(alignment: .leading, spacing: 0) {
            Button { store.push(.item(item.id)) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEBATE DA SEMANA · \(uni.name.uppercased())").kicker(11).foregroundStyle(MV.C.ink)
                    Text(item.title.uppercased()).font(MVFont.display(26, width: 118)).foregroundStyle(MV.C.ink)
                    Text(item.desc).font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink.opacity(0.85))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MV.C.wow)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    DebateOptionRow(label: options[i], index: i, percent: percents?[i], chosen: store.pollVote == i)
                }
                HStack {
                    Text(store.weeklyPollTotalLabel()).font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                    Spacer()
                    Text(StaticContent.weeklyDebateComments).font(MVFont.body(11, weight: 700)).foregroundStyle(MV.C.muted)
                }
            }
            .padding(14)
        }
        .background(MV.C.card)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }
}

private struct DebateOptionRow: View {
    let label: String
    let index: Int
    let percent: Int?
    let chosen: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                MV.C.ink.opacity(0.12)
                Rectangle().fill(chosen ? MV.C.wow : MV.C.ink.opacity(0.12))
                    .frame(width: geo.size.width * Double(percent ?? 0) / 100)
                    .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5), value: percent)
                HStack {
                    Text(label).font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                    Spacer()
                    if let percent { Text("\(percent)%").font(MVFont.black(13)).foregroundStyle(MV.C.ink) }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(height: 36)
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .burstOnTap("BAM!", color: MV.C.wow, when: store.pollVote == nil) {
            store.voteWeekly(index)
        }
    }
}
