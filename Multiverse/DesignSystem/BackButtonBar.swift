import SwiftUI

/// Pílula "← VOLTAR" usada no topo de toda tela empilhada (a navigation bar nativa fica escondida).
struct BackButtonBar: View {
    var action: () -> Void
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack {
            Button(action: action) {
                Text("← VOLTAR")
                    .font(MVFont.bold(12))
                    .tracking(0.4)
                    .foregroundStyle(MV.C.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(MV.C.card))
                    .overlay(Capsule().strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                    .background(Capsule().fill(MV.C.ink).offset(x: MV.Shadow.s, y: MV.Shadow.s))
            }
            .buttonStyle(.plain)
            Spacer()
            if let trailing { trailing() }
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}
