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
    private let resendCooldowns: EmailResendCooldown

    var session: AuthSession? {
        didSet {
            if let session, session.needsProfile {
                draft.name = session.displayName ?? ""
                draft.email = session.email
                path = [.chooseUsername]
            }
        }
    }
    var bootstrapFailed = false
    var isBootstrapping = true
    private var pendingEmailLink: URL?
    @ObservationIgnored private var sessionLifecycleID = UUID()

    /// Pilha de navegação do fluxo (a raiz, Boas-vindas, não entra aqui — ver `AuthFlowView`).
    var path: [AuthRoute] = []
    var isLoading = false {
        didSet {
            guard !isLoading, pendingEmailLink != nil else { return }
            Task { [weak self] in await self?.processPendingEmailLink() }
        }
    }
    var errorMessage: String?
    var fieldError: String?

    // Entrar
    var signInIdentifier = ""
    var signInPassword = ""

    // Criar conta
    var draft = NewAccountDraft() {
        didSet {
            if draft.username != oldValue.username { invalidateUsernameCheck() }
        }
    }
    @ObservationIgnored private var usernameRequestID = UUID()
    var verificationCode = ""
    var usernameAvailable: Bool?
    var verificationResendCooldown: Int { resendCooldowns.remaining(for: .verification, email: draft.email) }
    var passwordResetResendCooldown: Int { resendCooldowns.remaining(for: .passwordReset, email: resetEmail) }

    // Esqueci a senha
    var resetEmail = ""
    var infoMessage: String?
    var newPassword = ""
    var newPasswordConfirm = ""

    init(repository: AuthRepository = FirebaseAuthRepository(), resendCooldowns: EmailResendCooldown = EmailResendCooldown()) {
        self.repository = repository
        self.resendCooldowns = resendCooldowns
    }

    func bootstrap() async {
        isBootstrapping = true
        bootstrapFailed = false
        errorMessage = nil
        do { session = try await repository.currentSession() }
        catch { bootstrapFailed = true; errorMessage = error.localizedDescription }
        if session == nil, let pending = await repository.pendingSignUpEmail() {
            draft.email = pending
            path = [.createAccount, .verifyCode]
        }
        isBootstrapping = false
        await processPendingEmailLink()
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
                if error as? AuthError == .emailNotVerified, verificationResendCooldown == 0 {
                    let email = draft.email
                    do {
                        try await repository.resendVerificationCode()
                        resendCooldowns.recordSend(for: .verification, email: email)
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
            errorMessage = L10n.text("Sua senha ainda não atende aos requisitos.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = draft.password
            let pending = await repository.pendingSignUpEmail()
            if resendCooldowns.remaining(for: .verification, email: email) == 0 || pending?.lowercased() != email.lowercased() {
                try await repository.startSignUp(email: email, password: password)
                resendCooldowns.recordSend(for: .verification, email: email)
            }
            draft.email = email
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
        guard verificationResendCooldown == 0, !isLoading else { return }
        let email = draft.email
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await repository.resendVerificationCode()
            resendCooldowns.recordSend(for: .verification, email: email)
        } catch { errorMessage = error.localizedDescription }
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

    private func invalidateUsernameCheck() {
        usernameRequestID = UUID()
        usernameAvailable = nil
    }

    func checkUsername() async {
        guard !Task.isCancelled else { return }
        invalidateUsernameCheck()
        let requestID = usernameRequestID
        let username = draft.username
        guard !username.isEmpty else { return }
        do {
            let available = try await repository.checkUsernameAvailable(username)
            guard !Task.isCancelled, requestID == usernameRequestID, draft.username == username else { return }
            usernameAvailable = available
        } catch {
            guard !Task.isCancelled, requestID == usernameRequestID, draft.username == username else { return }
            errorMessage = error.localizedDescription
        }
    }

    func finishSignUp() async {
        guard !isLoading else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await repository.completeSignUp(name: draft.name, username: draft.username, avatarColor: draft.avatarColor, bio: draft.bio)
        } catch {
            if error as? AuthError == .usernameTaken {
                usernameAvailable = false
                path = [.chooseUsername]
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Esqueci a senha

    func requestPasswordReset() async {
        guard !isLoading else { return }
        if passwordResetResendCooldown > 0 {
            if path.last != .linkSent { push(.linkSent) }
            return
        }
        let email = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = sessionLifecycleID
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.requestPasswordReset(email: email)
            guard requestID == sessionLifecycleID else { return }
            resetEmail = email
            resendCooldowns.recordSend(for: .passwordReset, email: email)
            if path.last != .linkSent { push(.linkSent) }
        } catch {
            guard requestID == sessionLifecycleID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func handleEmailLink(_ url: URL) async {
        // Keep only the latest link while another authentication operation is in flight.
        pendingEmailLink = url
        await processPendingEmailLink()
    }

    private func processPendingEmailLink() async {
        guard !isBootstrapping, !isLoading, let url = pendingEmailLink else { return }
        pendingEmailLink = nil
        let requestID = sessionLifecycleID
        guard session == nil else {
            infoMessage = L10n.text("Saia da conta antes de abrir o link de recuperação.")
            return
        }
        isLoading = true
        errorMessage = nil
        newPassword = ""
        newPasswordConfirm = ""
        defer { isLoading = false }
        do {
            let result = try await repository.prepareEmailAction(url)
            guard requestID == sessionLifecycleID else { return }
            switch result {
            case .resetPassword(let email):
                resetEmail = email
                path = [.signIn, .forgotPassword, .linkSent, .newPassword]
            }
        } catch {
            guard requestID == sessionLifecycleID else { return }
            errorMessage = error.localizedDescription
        }
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
            errorMessage = L10n.text("As senhas precisam ser iguais.")
            return
        }
        guard PasswordRequirements(newPassword).allMet else {
            errorMessage = L10n.text("Sua senha ainda não atende aos requisitos.")
            return
        }
        let requestID = sessionLifecycleID
        let email = resetEmail
        isLoading = true
        defer { isLoading = false }
        do {
            let password = newPassword
            try await repository.resetPassword(password)
            guard requestID == sessionLifecycleID else { return }
            newPassword = ""
            newPasswordConfirm = ""
            do {
                let restored = try await repository.signIn(identifier: email, password: password)
                guard requestID == sessionLifecycleID else { return }
                session = restored
                path = session?.needsProfile == true ? [.chooseUsername] : []
            } catch {
                guard requestID == sessionLifecycleID else { return }
                // The code is consumed: a failed subsequent login must not retry the reset.
                signInIdentifier = email
                signInPassword = ""
                returnToLogin()
                infoMessage = L10n.text("Senha alterada. Entre com sua nova senha.")
            }
        } catch {
            guard requestID == sessionLifecycleID else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Conta (chamado a partir de Ajustes)

    func signOut() async {
        await PushCoordinator.shared.disconnect()
        do {
            try await repository.signOut()
            reset()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAccount() async throws {
        await PushCoordinator.shared.disconnect()
        try await repository.deleteAccount()
        reset()
    }

    private func reset() {
        pendingEmailLink = nil
        sessionLifecycleID = UUID()
        invalidateUsernameCheck()
        resendCooldowns.clear()
        resetEmail = ""
        bootstrapFailed = false
        errorMessage = nil
        infoMessage = nil
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
