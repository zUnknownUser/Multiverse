import SwiftUI

/// Estado de carregamento inicial, enquanto `AppStore.bootstrap()` busca o catálogo
/// no `MultiverseRepository`.
struct LaunchLoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            MV.C.paper.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("MULTIVERSE")
                    .font(MVFont.display(30, width: 125))
                    .tracking(-0.4)
                    .foregroundStyle(MV.C.ink)
                HStack(spacing: 8) {
                    ForEach([MV.C.marvel, MV.C.dc, MV.C.wow], id: \.self) { c in
                        Circle().fill(c)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(MV.C.ink, lineWidth: 1.5))
                            .opacity(pulse ? 1 : 0.3)
                    }
                }
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            }
        }
        .onAppear { pulse = true }
    }
}
