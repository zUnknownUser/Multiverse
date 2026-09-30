import SwiftUI

/// Passo 2 de 4: código de 6 dígitos enviado por e-mail.
struct VerifyCodeView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        ScreenScaffold(showBack: true, onBack: { auth.pop() }, backTrailing: {
            AnyView(Text("2 DE 4").font(MVFont.bold(12)).foregroundStyle(MV.C.muted))
        }) {
            VStack(alignment: .leading, spacing: 20) {
                AuthProgressBars(filled: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CONFIRME O CÓDIGO").font(MVFont.display(30, width: 120)).foregroundStyle(MV.C.ink)
                    (Text("Mandamos um código de 6 dígitos pra\n").font(MVFont.body(14, weight: 500))
                        + Text(auth.draft.email).font(MVFont.body(14, weight: 800)))
                        .foregroundStyle(MV.C.ink)
                }

                CodeInputBoxes(code: $auth.verificationCode, errored: auth.errorMessage != nil)

                if let error = auth.errorMessage {
                    Text(error).font(MVFont.bold(12)).foregroundStyle(MV.C.marvel)
                }

                HStack {
                    Text("Não chegou? Olhe o spam.").font(MVFont.body(13, weight: 500)).foregroundStyle(MV.C.ink)
                    Spacer()
                    if auth.resendCooldown > 0 {
                        Text("Reenviar em 0:\(String(format: "%02d", auth.resendCooldown))")
                            .font(MVFont.bold(13)).foregroundStyle(MV.C.muted)
                    } else {
                        Button("Reenviar código") { Task { await auth.resendCode() } }
                            .font(MVFont.bold(13)).foregroundStyle(MV.C.ink)
                            .buttonStyle(.plain)
                    }
                }

                Button("Trocar e-mail") { auth.pop() }
                    .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                    .buttonStyle(.plain)

                Spacer(minLength: 12)

                PrimaryAuthButton(title: "CONFIRMAR", isLoading: auth.isLoading, enabled: auth.verificationCode.count == 6) {
                    Task { await auth.submitCode() }
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
        .onChange(of: auth.verificationCode) { _, code in
            guard code.count == 6 else { return }
            Task { await auth.submitCode() }
        }
    }
}
