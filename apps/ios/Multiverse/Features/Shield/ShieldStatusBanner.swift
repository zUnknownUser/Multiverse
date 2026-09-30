import SwiftUI

/// Banner "ESCUDO ATIVO" no topo da Home (recurso 1a).
struct ShieldStatusBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .topLeading) {
            MV.C.ink
            Halftone(color: MV.C.paper.opacity(0.1))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ESCUDO ATIVO")
                        .font(MVFont.black(12)).tracking(0.4)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(MV.C.dc)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.paper, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                        .rotationEffect(.degrees(-3))
                    Spacer()
                    Button { store.push(.adjustShieldPoint) } label: {
                        Text("Ajustar").font(MVFont.bold(13)).underline().foregroundStyle(MV.C.paper)
                    }
                    .buttonStyle(.plain)
                }

                if let status = store.shieldStatusLine() {
                    (Text(status).font(MVFont.body(14, weight: 500))
                        + Text("  \(store.shieldHiddenCount) reviews").font(MVFont.bold(14))
                        + Text(" sobre o que vem depois estão escondidas.").font(MVFont.body(14, weight: 500)))
                        .foregroundStyle(MV.C.paper)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: MV.R.lg))
        .overlay(RoundedRectangle(cornerRadius: MV.R.lg).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .background(RoundedRectangle(cornerRadius: MV.R.lg).fill(MV.C.dc).offset(x: MV.Shadow.m, y: MV.Shadow.m))
    }
}
