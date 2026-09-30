import SwiftUI

/// Passo 1 de 4 da criação de conta: e-mail + senha.
struct CreateAccountView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        let requirements = PasswordRequirements(auth.draft.password)

        ScreenScaffold(showBack: true, onBack: { auth.pop() }, backTrailing: {
            AnyView(Text("1 DE 4").font(MVFont.bold(12)).foregroundStyle(MV.C.muted))
        }) {
            VStack(alignment: .leading, spacing: 20) {
                AuthProgressBars(filled: 1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("CRIE SUA CONTA").font(MVFont.display(32, width: 122)).foregroundStyle(MV.C.ink)
                    Text("Seu diário, suas notas e seus votos ficam salvos aqui.")
                        .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                }

                AuthField(label: "E-mail", text: $auth.draft.email, placeholder: "seu@email.com", keyboardType: .emailAddress, autocapitalization: .never)

                VStack(alignment: .leading, spacing: 10) {
                    AuthField(label: "Senha", text: $auth.draft.password, isSecure: true)
                    PasswordStrengthMeter(password: auth.draft.password, trailingHint: requirements.allMet ? nil : "Quase lá")
                    PasswordRequirementsList(requirements: requirements)
                }

                if let error = auth.errorMessage {
                    AuthErrorBanner(message: error)
                }

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    PrimaryAuthButton(title: "CRIAR CONTA", isLoading: auth.isLoading, enabled: requirements.allMet && !auth.draft.email.isEmpty) {
                        Task { await auth.submitSignUpEmail() }
                    }
                    Text("Enviaremos um código pra confirmar seu e-mail.")
                        .font(MVFont.body(12, weight: 500)).foregroundStyle(MV.C.muted)
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }
}

/// Botão principal (54pt, vermelho, sombra dura) usado em todo o fluxo de auth.
struct PrimaryAuthButton: View {
    let title: String
    var isLoading = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView().tint(MV.C.paper)
            } else {
                Text(title).font(MVFont.bold(15))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .foregroundStyle(enabled ? MV.C.paper : MV.C.muted)
        .background(enabled ? MV.C.marvel : MV.C.desk)
        .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
        .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
        .background(RoundedRectangle(cornerRadius: MV.R.md).fill(enabled ? MV.C.ink : .clear).offset(x: MV.Shadow.m, y: MV.Shadow.m))
        .contentShape(Rectangle())
        .onTapGesture { if enabled && !isLoading { action() } }
    }
}
