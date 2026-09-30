import SwiftUI

/// "Seus números" — recurso 4b. Bloqueado atrás do Pro.
struct ProStatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            if proStore.isPro {
                unlockedContent
            } else {
                lockedContent
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("SEUS\nNÚMEROS").font(MVFont.display(30, width: 118)).lineSpacing(-6).foregroundStyle(MV.C.ink)
            Spacer()
            Text("PRO")
                .font(MVFont.display(14))
                .foregroundStyle(MV.C.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .rotationEffect(.degrees(-4))
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Text("Assine o Pro pra ver horas por universo, frequência, sequência de dias e mais.")
                .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.muted)
            Button { store.push(.pro) } label: {
                Text("VER MULTIVERSE PRO")
                    .font(MVFont.bold(14))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(MV.C.paper)
                    .background(MV.C.marvel)
                    .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                    .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MV.pad)
        .padding(.bottom, 24)
    }

    private var unlockedContent: some View {
        let breakdown = hoursByUniverse
        let totalHours = breakdown.reduce(0) { $0 + $1.hours }
        let frequency = frequencyGrid
        let streak = currentStreak(frequency: frequency)

        return VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                Text("HORAS DE LORE EM 2026").kicker(11).foregroundStyle(MV.C.muted)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(totalHours)").font(MVFont.black(48)).foregroundStyle(MV.C.ink)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("≈ \(max(1, totalHours / 24)) dias").font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                        Text("fora da realidade").font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                    }
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(breakdown, id: \.universe.id) { entry in
                            entry.universe.color.frame(width: totalHours > 0 ? geo.size.width * CGFloat(entry.hours) / CGFloat(totalHours) : 0)
                        }
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                HStack(spacing: 14) {
                    ForEach(breakdown, id: \.universe.id) { entry in
                        HStack(spacing: 4) {
                            Circle().fill(entry.universe.color).frame(width: 8, height: 8)
                            Text("\(entry.universe.name) \(entry.hours)h").font(MVFont.bold(11)).foregroundStyle(MV.C.ink)
                        }
                    }
                }
            }
            .padding(14)
            .comicCard(shadow: MV.Shadow.s)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FREQUÊNCIA").kicker(11).foregroundStyle(MV.C.muted)
                    Spacer()
                    Text("últimas 15 semanas").font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 15)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<frequency.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(frequency[i] ? MV.C.wow : MV.C.card)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(MV.C.ink, lineWidth: 1))
                    }
                }
                Text("Sequência atual: \(streak) dias").font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
            }
            .padding(14)
            .comicCard(shadow: MV.Shadow.s)

            HStack(spacing: 10) {
                statCard(title: "SUA NOTA MÉDIA", value: myAverageRating, note: communityDeltaNote)
                statCard(title: "TIPO FAVORITO", value: favoriteType, note: nil)
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.bottom, 24)
    }

    private func statCard(title: String, value: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).kicker(10).foregroundStyle(MV.C.muted)
            Text(value).font(MVFont.black(26)).foregroundStyle(MV.C.ink)
            if let note { Text(note).font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .comicCard(shadow: MV.Shadow.s)
    }

    // MARK: - Números derivados do diário real do usuário

    private var hoursByUniverse: [(universe: Universe, hours: Int)] {
        var totals: [String: Double] = [:]
        for entry in store.diary {
            guard let item = store.item(entry.itemId) else { continue }
            totals[item.uni, default: 0] += Logic.loreHours(item.type)
        }
        return store.universes.compactMap { u in totals[u.id].map { (u, Int($0.rounded())) } }
    }

    private var frequencyGrid: [Bool] {
        let diaryDays = Set(store.diary.map { "\($0.month)-\($0.day)" })
        return (0..<105).map { i in Logic.seed("freq-\(i)") % 3 == 0 || diaryDays.count > i }
    }

    private func currentStreak(frequency: [Bool]) -> Int {
        var streak = 0
        for value in frequency.reversed() {
            if value { streak += 1 } else { break }
        }
        return streak
    }

    private var myAverageRating: String {
        let mine = store.reviews.filter { $0.user == store.meID }
        guard !mine.isEmpty else { return "—" }
        let avg = mine.reduce(0.0) { $0 + $1.rating } / Double(mine.count)
        return String(format: "%.1f", avg).replacingOccurrences(of: ".", with: ",")
    }

    private var communityDeltaNote: String {
        let communityAvg = store.items.reduce(0.0) { $0 + $1.avg } / Double(max(1, store.items.count))
        return "comunidade: \(String(format: "%.1f", communityAvg).replacingOccurrences(of: ".", with: ","))"
    }

    private var favoriteType: String {
        var counts: [String: Int] = [:]
        for entry in store.diary {
            guard let item = store.item(entry.itemId) else { continue }
            counts[item.type, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? "—"
    }
}
