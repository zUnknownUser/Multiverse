import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        ScreenScaffold(showBack: true, onBack: { auth.pop() }) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DE VOLTA AO\nCÂNONE").font(MVFont.display(32, width: 122)).lineSpacing(-6).foregroundStyle(MV.C.ink)
                    Text("Seu feed tem 14 reviews novas desde a última visita.")
                        .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                }

                if let error = auth.errorMessage {
                    AuthErrorBanner(message: error)
                }

                AuthField(label: "E-mail", text: $auth.signInIdentifier, placeholder: "seu@email.com", keyboardType: .emailAddress, autocapitalization: .never)

                VStack(alignment: .leading, spacing: 6) {
                    AuthField(label: "Senha", text: $auth.signInPassword, isSecure: true, errored: auth.fieldError != nil)
                    if let fieldError = auth.fieldError {
                        Text(fieldError).font(MVFont.bold(12)).foregroundStyle(MV.C.marvel)
                    }
                }

                HStack {
                    Spacer()
                    Button("Esqueci a senha") { auth.push(.forgotPassword) }
                        .font(MVFont.bold(13)).underline().foregroundStyle(MV.C.ink)
                        .buttonStyle(.plain)
                }

                PrimaryAuthButton(title: auth.errorMessage != nil ? "TENTAR DE NOVO" : "ENTRAR", isLoading: auth.isLoading, enabled: !auth.signInIdentifier.isEmpty && !auth.signInPassword.isEmpty) {
                    Task { await auth.signIn() }
                }

                dividerRow

                HStack(spacing: 10) {
                    socialButton("Apple", bg: MV.C.ink, fg: MV.C.paper) { Task { await auth.continueWithApple() } }
                    socialButton("Google", bg: MV.C.card, fg: MV.C.ink) { Task { await auth.continueWithGoogle() } }
                }

                Spacer(minLength: 12)

                HStack {
                    Spacer()
                    Button {
                        auth.pop()
                        auth.push(.createAccount)
                    } label: {
                        (Text("Novo por aqui? ").foregroundStyle(MV.C.ink)
                            + Text("Criar conta").underline().bold().foregroundStyle(MV.C.ink))
                            .font(MVFont.body(15, weight: 600))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }

    private var dividerRow: some View {
        HStack(spacing: 12) {
            Rectangle().fill(MV.C.ink).frame(height: 1.5)
            Text("OU").font(MVFont.bold(12)).foregroundStyle(MV.C.muted)
            Rectangle().fill(MV.C.ink).frame(height: 1.5)
        }
    }

    private func socialButton(_ title: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(MVFont.bold(14))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: MV.R.md).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
            .clipShape(RoundedRectangle(cornerRadius: MV.R.md))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
