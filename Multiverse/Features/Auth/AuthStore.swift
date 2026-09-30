import Foundation

/// Destinos empilháveis do fluxo de autenticação. "Boas-vindas" é sempre a raiz da
/// `NavigationStack` (ver `AuthFlowView`), então não tem caso aqui.
enum AuthRoute: Hashable {
    case signIn
    case createAccount, verifyCode, chooseUsername, avatarAndBio
    case forgotPassword, linkSent, newPassword
}

/// Estado e navegação do fluxo de autenticação (telas 01–10 do handoff de login).
/// Isolado do `AppStore` — autenticação é identidade, não conteúdo do app.
@MainActor
@Observable
final class AuthStore {
    private let repository: AuthRepository

    var session: AuthSession?
    var isBootstrapping = true

    /// Pilha de navegação do fluxo (a raiz, Boas-vindas, não entra aqui — ver `AuthFlowView`).
    var path: [AuthRoute] = []
    var isLoading = false
    var errorMessage: String?
    var fieldError: String?

    // Entrar
    var signInIdentifier = ""
    var signInPassword = ""

    // Criar conta
    var draft = NewAccountDraft()
    var verificationCode = ""
    var usernameAvailable: Bool?
    var resendCooldown = 0

    // Esqueci a senha
    var resetEmail = "duda.kaminski@gmail.com"
    var newPassword = ""
    var newPasswordConfirm = ""

    init(repository: AuthRepository = MockAuthRepository()) {
        self.repository = repository
    }

    func bootstrap() async {
        session = await repository.currentSession()
        isBootstrapping = false
    }

    func push(_ route: AuthRoute) {
        path.append(route)
        errorMessage = nil
        fieldError = nil
    }

    func pop() {
        if !path.isEmpty { path.removeLast() }
        errorMessage = nil
        fieldError = nil
    }

    // MARK: - Entrar

    func signIn() async {
        errorMessage = nil
        fieldError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await repository.signIn(identifier: signInIdentifier, password: signInPassword)
        } catch {
            errorMessage = error.localizedDescription
            fieldError = "A senha não confere com esse usuário."
        }
    }

    func continueWithApple() async { await socialSignIn(repository.signInWithApple) }
    func continueWithGoogle() async { await socialSignIn(repository.signInWithGoogle) }

    private func socialSignIn(_ perform: () async throws -> AuthSession) async {
        isLoading = true
        defer { isLoading = false }
        do { session = try await perform() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Criar conta

    func submitSignUpEmail() async {
        errorMessage = nil
        guard PasswordRequirements(draft.password).allMet else {
            errorMessage = "Sua senha ainda não atende aos requisitos."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.startSignUp(email: draft.email, password: draft.password)
            startResendCooldown()
            push(.verifyCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resendCode() async {
        guard resendCooldown == 0 else { return }
        try? await repository.resendVerificationCode()
        startResendCooldown()
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Task { [weak self] in
            while let self, self.resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                self.resendCooldown = max(0, self.resendCooldown - 1)
            }
        }
    }

    func submitCode() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.verifyCode(verificationCode)
            push(.chooseUsername)
        } catch {
            errorMessage = error.localizedDescription
            verificationCode = ""
        }
    }

    func checkUsername() async {
        guard !draft.username.isEmpty else { usernameAvailable = nil; return }
        usernameAvailable = await repository.checkUsernameAvailable(draft.username)
    }

    func finishSignUp() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await repository.completeSignUp(name: draft.name, username: draft.username, avatarColor: draft.avatarColor, bio: draft.bio)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Esqueci a senha

    func requestPasswordReset() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.requestPasswordReset(email: resetEmail)
            startResendCooldown()
            push(.linkSent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Numa conta de verdade isso viria de um universal link; aqui simulamos o toque no e-mail.
    func simulateEmailLinkTapped() {
        push(.newPassword)
    }

    func submitNewPassword() async {
        errorMessage = nil
        guard newPassword == newPasswordConfirm else {
            errorMessage = "As senhas precisam ser iguais."
            return
        }
        guard PasswordRequirements(newPassword).allMet else {
            errorMessage = "Sua senha ainda não atende aos requisitos."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await repository.resetPassword(newPassword)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Conta (chamado a partir de Ajustes)

    func signOut() async {
        await repository.signOut()
        reset()
    }

    func deleteAccount() async throws {
        try await repository.deleteAccount()
        reset()
    }

    private func reset() {
        session = nil
        path = []
        signInIdentifier = ""; signInPassword = ""
        draft = NewAccountDraft()
        verificationCode = ""; usernameAvailable = nil
        newPassword = ""; newPasswordConfirm = ""
    }

    // MARK: - Ajustes / bloqueados

    func loadAccountSettings() async -> AccountSettings { await repository.fetchAccountSettings() }
    func saveAccountSettings(_ settings: AccountSettings) async { await repository.updateAccountSettings(settings) }
    func loadBlockedUsers() async -> [BlockedUser] { await repository.fetchBlockedUsers() }
    func unblock(_ id: String) async { await repository.unblockUser(id) }
    func blockUser(handle: String) async { await repository.blockUser(handle: handle) }
}
