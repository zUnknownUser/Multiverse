import SwiftUI

struct NewPasswordView: View {
    @Environment(AuthStore.self) private var auth
    private let signOutOtherDevices = true

    var body: some View {
        @Bindable var auth = auth
        let requirements = PasswordRequirements(auth.newPassword)
        let matches = !auth.newPasswordConfirm.isEmpty && auth.newPassword == auth.newPasswordConfirm

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOVA SENHA").font(MVFont.display(34, width: 122)).foregroundStyle(MV.C.ink)
                Text("Escolha uma senha que nem a TVA consiga podar.")
                    .font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                AuthField(label: "Nova senha", text: $auth.newPassword, isSecure: true)
                PasswordStrengthMeter(password: auth.newPassword)
            }

            AuthField(label: "Repetir senha", text: $auth.newPasswordConfirm, isSecure: true) {
                if matches {
                    Text("✓ IGUAIS")
                        .font(MVFont.black(11)).tracking(0.3)
                        .foregroundStyle(MV.C.card)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(MV.C.dc)
                        .overlay(RoundedRectangle(cornerRadius: MV.R.sm).strokeBorder(MV.C.ink, lineWidth: MV.stroke))
                        .clipShape(RoundedRectangle(cornerRadius: MV.R.sm))
                }
            }

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(signOutOtherDevices ? MV.C.ink : Color.clear)
                    RoundedRectangle(cornerRadius: 4).strokeBorder(MV.C.ink, lineWidth: MV.stroke)
                    if signOutOtherDevices { Text("✓").font(MVFont.black(12)).foregroundStyle(MV.C.paper) }
                }
                .frame(width: 26, height: 26)
                Text("Sair de todos os outros aparelhos").font(MVFont.body(14, weight: 500)).foregroundStyle(MV.C.ink)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("A redefinição de senha invalida as sessões anteriores")

            if let error = auth.errorMessage {
                AuthErrorBanner(message: error)
            }

            Spacer(minLength: 12)

            PrimaryAuthButton(title: "SALVAR E ENTRAR", isLoading: auth.isLoading, enabled: requirements.allMet && matches) {
                Task { await auth.submitNewPassword() }
            }
        }
        .padding(.horizontal, MV.pad)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(MV.C.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
