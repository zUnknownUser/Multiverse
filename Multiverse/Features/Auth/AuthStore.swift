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
    private var pendingEmailLink: URL?

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
    var resetEmail = ""
    var infoMessage: String?
    @ObservationIgnored private var cooldownTask: Task<Void, Never>?
    var newPassword = ""
    var newPasswordConfirm = ""

    init(repository: AuthRepository = FirebaseAuthRepository()) {
        self.repository = repository
    }

    func bootstrap() async {
        session = await repository.currentSession()
        if session == nil, let pending = await repository.pendingSignUpEmail() {
            draft.email = pending
            path = await repository.pendingEmailIsVerified() ? [.chooseUsername] : [.createAccount, .verifyCode]
        }
        isBootstrapping = false
        if let url = pendingEmailLink {
            pendingEmailLink = nil
            await handleEmailLink(url)
        }
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
        guard !isLoading else { return }
        errorMessage = nil
        fieldError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await repository.signIn(identifier: signInIdentifier, password: signInPassword)
        } catch {
            errorMessage = error.localizedDescription
            if error as? AuthError == .emailNotVerified || error as? AuthError == .profileIncomplete {
                draft.email = signInIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                path = error as? AuthError == .profileIncomplete ? [.chooseUsername] : [.verifyCode]
                errorMessage = nil
                if error as? AuthError == .emailNotVerified {
                    do {
                        try await repository.resendVerificationCode()
                        startResendCooldown()
                    } catch { errorMessage = error.localizedDescription }
                }
            } else if error as? AuthError == .emailCredentialsInvalid {
                fieldError = error.localizedDescription
            }
        }
    }

    func continueWithApple() async { await socialSignIn(repository.signInWithApple) }
    func continueWithGoogle() async { await socialSignIn(repository.signInWithGoogle) }

    private func socialSignIn(_ perform: () async throws -> AuthSession) async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await perform()
        } catch AuthError.cancelled {
            // Closing the Google sheet is not a failed login.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Criar conta

    func submitSignUpEmail() async {
        guard !isLoading else { return }
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
            draft.password = ""
            push(.verifyCode)
        } catch {
            if let pending = await repository.pendingSignUpEmail() {
                draft.email = pending
                draft.password = ""
                path = [.createAccount, .verifyCode]
            }
            errorMessage = error.localizedDescription
        }
    }

    func resendCode() async {
        guard resendCooldown == 0, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await repository.resendVerificationCode()
            startResendCooldown()
        } catch { errorMessage = error.localizedDescription }
    }

    private func startResendCooldown() {
        cooldownTask?.cancel()
        resendCooldown = 60
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.resendCooldown = max(0, self.resendCooldown - 1)
                if self.resendCooldown == 0 { return }
            }
        }
    }

    func submitCode() async {
        guard !isLoading, verificationCode.count == 6 else { return }
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
        let username = draft.username
        let available = await repository.checkUsernameAvailable(username)
        if draft.username == username { usernameAvailable = available }
    }

    func finishSignUp() async {
        guard !isLoading else { return }
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
        guard !isLoading, path.last != .linkSent || resendCooldown == 0 else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.requestPasswordReset(email: resetEmail)
            startResendCooldown()
            if path.last != .linkSent { push(.linkSent) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleEmailLink(_ url: URL) async {
        if isBootstrapping { pendingEmailLink = url; return }
        guard session == nil else {
            infoMessage = "Saia da conta antes de abrir o link de recuperação."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        newPassword = ""
        newPasswordConfirm = ""
        defer { isLoading = false }
        do {
            switch try await repository.prepareEmailAction(url) {
            case .resetPassword(let email):
                resetEmail = email
                path = [.signIn, .forgotPassword, .linkSent, .newPassword]
            case .emailVerified:
                path = [.chooseUsername]
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func returnToLogin() {
        path = [.signIn]
        errorMessage = nil
        newPassword = ""
        newPasswordConfirm = ""
    }

    func submitNewPassword() async {
        guard !isLoading else { return }
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
            let password = newPassword
            try await repository.resetPassword(password)
            newPassword = ""
            newPasswordConfirm = ""
            do {
                session = try await repository.signIn(identifier: resetEmail, password: password)
                path = []
            } catch {
                // The code is consumed: a failed subsequent login must not retry the reset.
                signInIdentifier = resetEmail
                signInPassword = ""
                returnToLogin()
                infoMessage = "Senha alterada. Entre com sua nova senha."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Conta (chamado a partir de Ajustes)

    func signOut() async {
        do {
            try await repository.signOut()
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async throws {
        try await repository.deleteAccount()
        reset()
    }

    private func reset() {
        cooldownTask?.cancel()
        resendCooldown = 0
        resetEmail = ""
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
