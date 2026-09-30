import SwiftUI

/// Card de afinidade no perfil de outra pessoa.
struct AffinityCard: View {
    let percent: Int
    let line: String
    let byUniverse: [(universe: Universe, pct: Int)]
    let agree: String
    let disagree: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                MV.C.wow
                Halftone(color: MV.C.ink.opacity(0.15))
                VStack(spacing: 2) {
                    Text("\(percent)%").font(MVFont.black(44)).foregroundStyle(MV.C.ink)
                    Text("AFINIDADE COM VOCÊ").kicker(11).foregroundStyle(MV.C.ink.opacity(0.8))
                    Text(line).font(MVFont.body(12, weight: 700)).foregroundStyle(MV.C.ink)
                }
                .padding(.vertical, 18)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(byUniverse, id: \.universe.id) { entry in
                    HStack {
                        Text(entry.universe.name).font(MVFont.bold(12)).foregroundStyle(MV.C.ink).frame(width: 60, alignment: .leading)
                        ComicProgress(value: Double(entry.pct) / 100, fill: entry.universe.color, height: 14)
                        Text("\(entry.pct)%").font(MVFont.black(11)).foregroundStyle(MV.C.ink).frame(width: 32, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Concordam em: \(agree)").font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink)
                    Text("Brigam por: \(disagree)").font(MVFont.body(12, weight: 600)).foregroundStyle(MV.C.ink)
                }
            }
            .padding(14)
            .background(MV.C.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
        .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }
}
