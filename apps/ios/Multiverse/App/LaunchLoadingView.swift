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

/// Uses the existing product typography and buttons for recoverable catalog states.
/// An empty catalog is informational, not a connectivity failure.
struct CatalogStatusView: View {
    let issue: CatalogError
    let isSigningOut: Bool
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        ZStack {
            MV.C.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("MULTIVERSE")
                        .font(MVFont.display(30, width: 125)).tracking(-0.4)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(issue.title).font(MVFont.display(26, width: 115))
                        Text(issue.errorDescription ?? "")
                            .font(MVFont.body(14)).foregroundStyle(MV.C.muted)
                    }
                    PrimaryAuthButton(title: issue == .empty ? L10n.text("VERIFICAR NOVAMENTE") : L10n.text("TENTAR DE NOVO"), enabled: !isSigningOut, action: retry)
                        .accessibilityAddTraits(.isButton)
                    Button(L10n.text("SAIR"), action: signOut)
                        .font(MVFont.bold(13)).underline().buttonStyle(.plain)
                        .disabled(isSigningOut)
                }
                .foregroundStyle(MV.C.ink)
                .padding(.horizontal, MV.pad)
                .padding(.vertical, 48)
            }
        }
    }
}
