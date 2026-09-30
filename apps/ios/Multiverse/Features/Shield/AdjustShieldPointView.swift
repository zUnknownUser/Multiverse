import SwiftUI

/// "Onde você está?" — ajusta o ponto do Escudo de Spoiler por universo (recurso 1b).
struct AdjustShieldPointView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedUniverse: String
    @State private var pendingIndex: Int
    @State private var advanceAutomatically: Bool

    init() {
        _selectedUniverse = State(initialValue: "wow")
        _pendingIndex = State(initialValue: 0)
        _advanceAutomatically = State(initialValue: true)
    }

    var body: some View {
        ScreenScaffold(showBack: true, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("ONDE VOCÊ\nESTÁ?")).font(MVFont.display(32, width: 122)).lineSpacing(-6).foregroundStyle(MV.C.ink)
                    Text(L10n.text("Tudo que vem depois desse ponto fica escondido no app inteiro: feed, reviews, comentários e busca."))
                        .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                }

                universePicker

                if let uni = store.universe(selectedUniverse) {
                    timeline(uni: uni)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("Avançar sozinho")).font(MVFont.bold(15)).foregroundStyle(MV.C.ink)
                            Text(L10n.text("Move o ponto quando você registrar algo")).font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $advanceAutomatically).labelsHidden().tint(uni.color)
                    }
                    .padding(16)
                    .comicCard(shadow: MV.Shadow.s)

                    Text(L10n.text("SALVAR PONTO"))
                        .font(MVFont.bold(15))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .foregroundStyle(uni.inkColor)
                        .background(uni.color)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
                        .background(RoundedRectangle(cornerRadius: MV.R.md).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.setShieldPoint(universeID: selectedUniverse, index: pendingIndex)
                            store.setShieldAdvanceAutomatically(advanceAutomatically)
                            dismiss()
                        }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .onAppear {
            advanceAutomatically = store.shieldAdvanceAutomatically
            if let firstWithPoint = store.universes.first(where: { store.shieldPoints[$0.id] != nil }) {
                selectedUniverse = firstWithPoint.id
            }
            pendingIndex = store.shieldPoints[selectedUniverse] ?? 0
        }
        .onChange(of: selectedUniverse) { _, newValue in
            pendingIndex = store.shieldPoints[newValue] ?? 0
        }
    }

    private var universePicker: some View {
        HStack(spacing: 8) {
            ForEach(store.universes) { uni in
                let selected = selectedUniverse == uni.id
                Text(uni.name.uppercased())
                    .font(MVFont.bold(12))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(selected ? uni.inkColor : MV.C.ink)
                    .background(selected ? uni.color : MV.C.card)
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { selectedUniverse = uni.id }
            }
        }
    }

    @ViewBuilder
    private func timeline(uni: Universe) -> some View {
        let entries = store.timelines[uni.id] ?? []
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                row(uni: uni, entries: entries, index: index, entry: entry)
            }
        }
    }

    @ViewBuilder
    private func row(uni: Universe, entries: [TimelineEntry], index: Int, entry: TimelineEntry) -> some View {
        let item = store.item(entry.itemId)
        let isPastOrCurrent = index <= pendingIndex
        let isCurrent = index == pendingIndex

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(isPastOrCurrent ? uni.color : Color.clear)
                        if isCurrent { Text("✓").font(MVFont.black(11)).foregroundStyle(uni.inkColor) }
                    }
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(isPastOrCurrent ? MV.C.ink : MV.C.ink.opacity(0.3), lineWidth: MV.stroke, antialiased: true))
                    if index < entries.count - 1 {
                        Rectangle().fill(isPastOrCurrent ? MV.C.ink : MV.C.ink.opacity(0.2)).frame(width: 2).frame(minHeight: 28)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.era.uppercased()).font(MVFont.black(10)).tracking(0.3).foregroundStyle(MV.C.muted)
                    HStack {
                        Text(item?.title ?? "—").font(MVFont.bold(15)).foregroundStyle(isPastOrCurrent ? MV.C.ink : MV.C.muted)
                        Spacer()
                        if !isPastOrCurrent {
                            Text(L10n.text("ESCONDIDO"))
                                .font(MVFont.black(9)).tracking(0.3)
                                .foregroundStyle(MV.C.muted)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .overlay(Capsule().strokeBorder(MV.C.muted, lineWidth: 1.5))
                        }
                    }
                    if isCurrent {
                        HStack(spacing: 4) {
                            Text(L10n.text("▼ VOCÊ ESTÁ AQUI")).font(MVFont.bold(11))
                            Text(L10n.text("toque nos itens acima/abaixo")).font(MVFont.body(10, weight: 500)).opacity(0.8)
                        }
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(MV.C.dc)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                        .background(RoundedRectangle(cornerRadius: MV.R.sm).fill(MV.C.shadow).offset(x: 3, y: 3))
                        .padding(.top, 6).padding(.bottom, 10)
                    }
                }
                .padding(.bottom, isCurrent ? 0 : 14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pendingIndex = index }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("%1$@, %2$@%3$@", String(describing: entry.era), String(describing: item?.title ?? ""), String(describing: isCurrent ? L10n.text(", você está aqui") : (isPastOrCurrent ? L10n.text(", já visto") : L10n.text(", escondido")))))
        .accessibilityAddTraits(.isButton)
    }
}
