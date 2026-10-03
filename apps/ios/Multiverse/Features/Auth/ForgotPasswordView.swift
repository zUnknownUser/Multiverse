import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        ScreenScaffold(showBack: true, onBack: { auth.pop() }) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("ESQUECEU A\nSENHA?")).font(MVFont.display(32, width: 122)).lineSpacing(-6).foregroundStyle(MV.C.ink)
                    Text(L10n.text("Acontece até com os heróis. Informe seu e-mail e mandamos um link pra criar uma senha nova."))
                        .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
                }

                AuthField(label: L10n.text("E-mail da conta"), text: $auth.resetEmail, keyboardType: .emailAddress, autocapitalization: .never)

                if let error = auth.errorMessage {
                    AuthErrorBanner(message: error)
                }

                PrimaryAuthButton(title: L10n.text("ENVIAR LINK"), isLoading: auth.isLoading, enabled: !auth.resetEmail.isEmpty) {
                    Task { await auth.requestPasswordReset() }
                }

                Spacer(minLength: 12)

                Text(L10n.text("Entrou com Apple ou Google? Você não tem senha no Multiverse. Volte e use o mesmo botão de antes."))
                    .font(MVFont.body(13, weight: 500))
                    .foregroundStyle(MV.C.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .comicCard(shadow: 0, dashed: true)
            }
            .padding(.horizontal, MV.pad)
            .padding(.bottom, 24)
        }
    }
}
