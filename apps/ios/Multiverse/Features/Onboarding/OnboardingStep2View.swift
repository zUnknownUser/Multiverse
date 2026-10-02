import SwiftUI

struct OnboardingStep2View: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let picks = store.onboardingConsumablePicks()
        let n = picks.filter { store.isSeen($0.id) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format("%1$@ de %2$@", "2", String(store.onboardingStepCount))).kicker(11).foregroundStyle(MV.C.muted)
                    Text(L10n.text("O que você já consumiu?"))
                        .font(MVFont.display(28, width: 120))
                        .lineSpacing(-4)
                        .foregroundStyle(MV.C.ink)
                    Text(picks.isEmpty ? L10n.text("Ainda não há obras para marcar nos universos escolhidos. Você pode continuar e registrar depois.") : (n > 0 ? L10n.format("%1$@ marcados. Sem nota por enquanto, dá pra avaliar depois.", String(describing: n)) : L10n.text("Marque em lote tudo que você já viu, leu ou jogou.")))
                        .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(picks) { item in
                        ConsumedPosterCell(item: item)
                    }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ConsumedPosterCell: View {
    let item: Item
    @Environment(AppStore.self) private var store

    var body: some View {
        let uni = store.universe(of: item)
        let marked = store.isSeen(item.id)
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PosterView(item: item, universe: uni, width: geo.size.width, height: geo.size.width * 1.5, titleSize: 11)
                if marked {
                    RoundedRectangle(cornerRadius: MV.R.md)
                        .fill(MV.C.ink.opacity(0.55))
                    Circle()
                        .fill(MV.C.card)
                        .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .frame(width: 36, height: 36)
                        .overlay(Text("✓").font(MVFont.black(18)).foregroundStyle(MV.C.ink))
                        .position(x: geo.size.width / 2, y: geo.size.width * 1.5 / 2)
                }
            }
            .scaleEffect(marked ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: marked)
            .contentShape(Rectangle())
            .onTapGesture { store.toggleSeen(item.id) }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}
