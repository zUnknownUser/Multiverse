import SwiftUI

/// Feed de teorias — recurso 1e.
struct TheoriesFeedView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var filter: TheoryFeedFilter = .open

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TEORIAS").font(MVFont.display(30, width: 122)).foregroundStyle(MV.C.ink)
                    Spacer()
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(TheoryFeedFilter.allCases, id: \.self) { f in
                            PillButton(title: f.rawValue, active: filter == f, size: 13) { filter = f }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                let rows = store.theoriesFiltered(filter)
                if rows.isEmpty {
                    Text("Nada por aqui ainda.").font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                        .frame(maxWidth: .infinity).padding(24)
                } else {
                    VStack(spacing: 14) {
                        ForEach(rows) { theory in
                            TheoryCard(theory: theory)
                        }
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }
}

struct TheoryCard: View {
    let theory: Theory
    @Environment(AppStore.self) private var store

    var body: some View {
        guard let user = store.user(theory.userID), let uni = store.universe(theory.uni) else { return AnyView(EmptyView()) }
        let percents = store.theoryPercents(theory)
        let voted = store.isTheoryVoted(theory.id)

        return AnyView(
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        AvatarView(user: user, size: 30)
                        Text(user.name).font(MVFont.bold(14)).foregroundStyle(MV.C.ink)
                        Text(store.theoryAccuracyLabel(user.id))
                            .font(MVFont.black(10)).tracking(0.2)
                            .foregroundStyle(MV.C.ink)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(MV.C.wow)
                            .overlay(RoundedRectangle(cornerRadius: MV.R.xs).strokeBorder(MV.C.ink, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: MV.R.xs))
                        Spacer()
                    }

                    Text(theory.text.uppercased())
                        .font(MVFont.black(17))
                        .foregroundStyle(MV.C.ink)

                    VStack(spacing: 6) {
                        voteRow(label: "Plausível", pct: percents.plausible, isPlausible: true, color: MV.C.dc)
                        voteRow(label: "Viajou", pct: percents.travel, isPlausible: false, color: MV.C.marvel)
                    }

                    footerNote
                }
                .padding(14)
                .comicCard(shadow: MV.Shadow.s)
                .contentShape(Rectangle())
                .onTapGesture { if theory.status != .open { store.push(.theoryDetail(theory.id)) } }

                if theory.status == .confirmed {
                    stamp("CONFIRMADA", color: MV.C.dc)
                } else if theory.status == .refuted {
                    stamp("REFUTADA", color: MV.C.marvel)
                }
            }
        )
    }

    private func voteRow(label: String, pct: Int, isPlausible: Bool, color: Color) -> some View {
        HStack {
            Text(label).font(MVFont.bold(13)).foregroundStyle(MV.C.ink).frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    MV.C.ink.opacity(0.08)
                    Rectangle().fill(color).frame(width: geo.size.width * Double(pct) / 100)
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            Text("\(pct)%").font(MVFont.black(13)).foregroundStyle(MV.C.ink).frame(width: 36, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.voteTheory(theory.id, plausible: isPlausible) }
    }

    @ViewBuilder
    private var footerNote: some View {
        switch theory.status {
        case .open:
            if let item = theory.resolvesAtItemID.flatMap({ store.item($0) }) {
                Text("Resolve em: \(item.title) · \(store.theoryTotalVotesLabel(theory)) votos")
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
        case .confirmed:
            if let title = theory.resolutionTitle {
                Text("Confirmada por: \(title)" + (theory.resolutionNote.map { " · \($0)" } ?? ""))
                    .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
            }
        case .refuted:
            Text("Refutada \(theory.resolutionTitle.map { "pelo \($0)" } ?? "") · \(store.theoryTotalVotesLabel(theory)) votos")
                .font(MVFont.body(11, weight: 600)).foregroundStyle(MV.C.muted)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(MVFont.display(15))
            .foregroundStyle(MV.C.paper)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color)
            .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
            .background(RoundedRectangle(cornerRadius: MV.R.sm).fill(MV.C.shadow).offset(x: 3, y: 3))
            .rotationEffect(.degrees(8))
            .offset(x: 10, y: -10)
    }
}
