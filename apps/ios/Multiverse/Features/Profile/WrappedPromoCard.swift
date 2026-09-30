import SwiftUI

/// Card vermelho com retícula no Perfil, abre o Wrapped.
struct WrappedPromoCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button { store.push(.wrapped) } label: {
            ZStack(alignment: .leading) {
                MV.C.marvel
                Halftone(color: MV.C.paper.opacity(0.16))
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MULTIVERSE WRAPPED").kicker(11).foregroundStyle(MV.C.paper.opacity(0.85))
                        Text("SEU SETEMBRO").font(MVFont.display(24, width: 120)).foregroundStyle(MV.C.paper)
                    }
                    Spacer()
                    Text("→").font(MVFont.black(22)).foregroundStyle(MV.C.paper)
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: MV.R.xxl))
            .overlay(RoundedRectangle(cornerRadius: MV.R.xxl).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .background(RoundedRectangle(cornerRadius: MV.R.xxl).fill(MV.C.shadow).offset(x: MV.Shadow.m, y: MV.Shadow.m))
        }
        .buttonStyle(.plain)
    }
}
