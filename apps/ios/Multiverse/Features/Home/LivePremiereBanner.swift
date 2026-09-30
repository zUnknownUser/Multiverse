import SwiftUI

/// Faixa vermelha na Home enquanto a "Estreia ao vivo" (recurso 5f) está no ar.
struct LivePremiereBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let event = store.liveEvent, let item = store.item(event.itemID) {
            Button { store.push(.livePremiere) } label: {
                HStack(spacing: 10) {
                    Text(L10n.text("● AO VIVO")).font(MVFont.black(11)).foregroundStyle(MV.C.paper)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.format("Estreia de %1$@", String(describing: item.title))).font(MVFont.bold(13)).foregroundStyle(MV.C.paper)
                        Text(L10n.format("%1$@ assistindo agora", String(describing: Logic.fmt(event.viewerCount)))).font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.paper.opacity(0.8))
                    }
                    Spacer()
                    Text(L10n.text("ENTRAR →")).font(MVFont.bold(11)).foregroundStyle(MV.C.paper)
                }
                .padding(12)
                .background(MV.C.marvel)
                .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            }
            .buttonStyle(.plain)
        }
    }
}
