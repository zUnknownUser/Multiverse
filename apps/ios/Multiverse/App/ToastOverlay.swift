import SwiftUI

/// Cápsula ink flutuante, 104pt acima da base. Aparece e some em 2.4s, subindo 10pt ao entrar.
struct ToastOverlay: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack {
            Spacer()
            if let message = store.toast {
                Text(message)
                    .font(MVFont.bold(13))
                    .foregroundStyle(MV.C.paper)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Capsule().fill(MV.C.ink))
                    .padding(.bottom, 104)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .id(message)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: store.toast)
        .allowsHitTesting(false)
    }
}
