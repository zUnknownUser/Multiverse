import SwiftUI

/// As 4 barrinhas de progresso do topo do fluxo de criação de conta.
struct AuthProgressBars: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i <= filled ? MV.C.ink : Color.clear)
                    .frame(height: 6)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(MV.C.ink, lineWidth: 1.5))
            }
        }
    }
}
