import SwiftUI

/// Raiz do fluxo de autenticação: Boas-vindas + toda a pilha de criar conta / entrar /
/// esqueci a senha. Mostrado pela `RootView` enquanto não há sessão.
struct AuthFlowView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        NavigationStack(path: $auth.path) {
            WelcomeView()
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signIn: SignInView()
                    case .createAccount: CreateAccountView()
                    case .verifyCode: VerifyCodeView()
                    case .chooseUsername: ChooseUsernameView()
                    case .avatarAndBio: AvatarAndBioView()
                    case .forgotPassword: ForgotPasswordView()
                    case .linkSent: LinkSentView()
                    case .newPassword: NewPasswordView()
                    }
                }
        }
    }
}
