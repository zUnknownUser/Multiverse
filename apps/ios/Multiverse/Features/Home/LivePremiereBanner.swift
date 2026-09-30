import SwiftUI

/// Faixa vermelha na Home enquanto a "Estreia ao vivo" (recurso 5f) está no ar.
struct LivePremiereBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let event = store.liveEvent, let item = store.item(event.itemID) {
            Button { store.push(.livePremiere) } label: {
                HStack(spacing: 10) {
                    Text("● AO VIVO").font(MVFont.black(11)).foregroundStyle(MV.C.paper)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Estreia de \(item.title)").font(MVFont.bold(13)).foregroundStyle(MV.C.paper)
                        Text("\(Logic.fmt(event.viewerCount)) assistindo agora").font(MVFont.body(10, weight: 600)).foregroundStyle(MV.C.paper.opacity(0.8))
                    }
                    Spacer()
                    Text("ENTRAR →").font(MVFont.bold(11)).foregroundStyle(MV.C.paper)
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
