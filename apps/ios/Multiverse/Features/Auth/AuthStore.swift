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
    let lifecycle: SessionLifecycle
    private let defaults: UserDefaults
    private let identityObserver: (any AuthIdentityObserving)?
    private static let deletionKey = "mv-account-deletion-pending"
    private(set) var isEndingSession = false
    private(set) var deletionPending = false
    @ObservationIgnored private var bootstrapID: UUID?
    @ObservationIgnored private var operationCount = 0
    @ObservationIgnored private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    private var sessionLifecycleID: UUID { lifecycle.generation }

    struct Binding: Equatable {
        let session: AuthSession?
        let generation: UUID
        let ending: Bool
    }
    var binding: Binding { Binding(session: session, generation: sessionLifecycleID, ending: isEndingSession) }

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

    /// Pilha de navegação do fluxo (a raiz, Boas-vindas, não entra aqui — ver `AuthFlowView`).
    var path: [AuthRoute] = []
    var isLoading = false {
        didSet {
            guard !isEndingSession, !deletionPending, !isLoading, pendingEmailLink != nil else { return }
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

    init(repository: AuthRepository? = nil, resendCooldowns: EmailResendCooldown = EmailResendCooldown(),
         lifecycle: SessionLifecycle = SessionLifecycle(), defaults: UserDefaults = .standard,
         identityObserver: (any AuthIdentityObserving)? = nil) {
        self.lifecycle = lifecycle
        self.defaults = defaults
        self.repository = repository ?? FirebaseAuthRepository(accountAPI: AccountAPIClient(lifecycle: lifecycle))
        self.resendCooldowns = resendCooldowns
        self.identityObserver = identityObserver ?? (repository == nil ? FirebaseIdentityObserver() : nil)
        deletionPending = defaults.bool(forKey: Self.deletionKey)
        lifecycle.onFailure = { [weak self] error in self?.endInvalidSession(error) }
        self.identityObserver?.start { [weak self] uid in
            guard let self, let session = self.session, !self.isEndingSession,
                  self.operationCount == 0, session.userID != uid else { return }
            self.endInvalidSession(.sessionExpired)
        }
    }

    func bootstrap() async {
        guard bootstrapID == nil, !isLoading, !isEndingSession else { return }
        if deletionPending {
            endInvalidSession(.deletionPending)
            await cleanupTask?.value
            return
        }
        let requestID = sessionLifecycleID
        bootstrapID = requestID
        isBootstrapping = true
        bootstrapFailed = false
        errorMessage = nil
        defer {
            if bootstrapID == requestID { bootstrapID = nil }
            if requestID == sessionLifecycleID { isBootstrapping = false }
        }
        do {
            let restored = try await repository.currentSession()
            guard isCurrent(requestID) else { return }
            session = restored
            if restored == nil {
                let pending = await repository.pendingSignUpEmail()
                guard isCurrent(requestID) else { return }
                if let pending { draft.email = pending; path = [.createAccount, .verifyCode] }
            }
        } catch {
            guard accept(error, requestID: requestID) else { return }
            bootstrapFailed = true
            errorMessage = error.localizedDescription
        }
        guard isCurrent(requestID) else { return }
        isBootstrapping = false
        await processPendingEmailLink()
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        requestID == sessionLifecycleID && !Task.isCancelled && !isEndingSession
    }
    private func accept(_ error: any Error, requestID: UUID) -> Bool {
        guard isCurrent(requestID), !(error is CancellationError), error as? AuthError != .cancelled else { return false }
        if let failure = error as? AuthError, [.sessionExpired, .accountDisabled, .deletionPending].contains(failure) {
            endInvalidSession(failure)
            return false
        }
        return true
    }
    private func beginOperation() { operationCount += 1 }
    private func finishOperation(_ requestID: UUID) {
        operationCount -= 1
        if operationCount == 0 {
            let waiters = operationWaiters; operationWaiters = []
            waiters.forEach { $0.resume() }
        }
        if requestID == sessionLifecycleID { isLoading = false }
    }
    private func drainOperations() async {
        guard operationCount > 0 else { return }
        await withCheckedContinuation { operationWaiters.append($0) }
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
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
        errorMessage = nil
        fieldError = nil
        let requestID = sessionLifecycleID
        isLoading = true
        beginOperation()
        defer { finishOperation(requestID) }
        do {
            let restored = try await repository.signIn(identifier: signInIdentifier, password: signInPassword)
            guard isCurrent(requestID) else { return }
            session = restored
            signInPassword = ""
        } catch {
            guard accept(error, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
            if error as? AuthError == .emailNotVerified || error as? AuthError == .profileIncomplete {
                draft.email = signInIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                path = error as? AuthError == .profileIncomplete ? [.chooseUsername] : [.verifyCode]
                errorMessage = nil
                if error as? AuthError == .emailNotVerified, verificationResendCooldown == 0 {
                    let email = draft.email
                    do {
                        try await repository.resendVerificationCode()
                        guard isCurrent(requestID) else { return }
                        resendCooldowns.recordSend(for: .verification, email: email)
                    } catch { if accept(error, requestID: requestID) { errorMessage = error.localizedDescription } }
                }
            } else if error as? AuthError == .emailCredentialsInvalid {
                fieldError = error.localizedDescription
            }
        }
    }

    func continueWithApple() async { await socialSignIn(repository.signInWithApple) }
    func continueWithGoogle() async { await socialSignIn(repository.signInWithGoogle) }

    private func socialSignIn(_ perform: () async throws -> AuthSession) async {
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
        errorMessage = nil
        let requestID = sessionLifecycleID
        isLoading = true
        beginOperation()
        defer { finishOperation(requestID) }
        do {
            let restored = try await perform()
            guard isCurrent(requestID) else { return }
            session = restored
            signInPassword = ""
        } catch AuthError.cancelled {
            // Closing the Google sheet is not a failed login.
        } catch {
            guard accept(error, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Criar conta

    func submitSignUpEmail() async {
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
        errorMessage = nil
        guard PasswordRequirements(draft.password).allMet else {
            errorMessage = L10n.text("Sua senha ainda não atende aos requisitos.")
            return
        }
        let requestID = sessionLifecycleID
        isLoading = true
        beginOperation()
        defer { finishOperation(requestID) }
        do {
            let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = draft.password
            let pending = await repository.pendingSignUpEmail()
            guard isCurrent(requestID) else { return }
            if resendCooldowns.remaining(for: .verification, email: email) == 0 || pending?.lowercased() != email.lowercased() {
                try await repository.startSignUp(email: email, password: password)
                guard isCurrent(requestID) else { return }
                resendCooldowns.recordSend(for: .verification, email: email)
            }
            draft.email = email
            draft.password = ""
            push(.verifyCode)
        } catch {
            guard accept(error, requestID: requestID) else { return }
            let pending = await repository.pendingSignUpEmail()
            guard isCurrent(requestID) else { return }
            if let pending {
                draft.email = pending
                draft.password = ""
                path = [.createAccount, .verifyCode]
            }
            errorMessage = error.localizedDescription
        }
    }

    func resendCode() async {
        guard !isEndingSession, !deletionPending, verificationResendCooldown == 0, !isLoading else { return }
        let email = draft.email
        let requestID = sessionLifecycleID
        isLoading = true
        errorMessage = nil
        defer { if requestID == sessionLifecycleID { isLoading = false } }
        do {
            try await repository.resendVerificationCode()
            guard isCurrent(requestID) else { return }
            resendCooldowns.recordSend(for: .verification, email: email)
        } catch { if accept(error, requestID: requestID) { errorMessage = error.localizedDescription } }
    }

    func submitCode() async {
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading, verificationCode.count == 6 else { return }
        errorMessage = nil
        let requestID = sessionLifecycleID
        isLoading = true
        beginOperation()
        defer { finishOperation(requestID) }
        do {
            try await repository.verifyCode(verificationCode)
            guard isCurrent(requestID) else { return }
            push(.chooseUsername)
        } catch {
            guard accept(error, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
            verificationCode = ""
        }
    }

    private func invalidateUsernameCheck() {
        usernameRequestID = UUID()
        usernameAvailable = nil
    }

    func checkUsername() async {
        guard !isEndingSession, !deletionPending, !Task.isCancelled else { return }
        invalidateUsernameCheck()
        let generation = sessionLifecycleID
        let requestID = usernameRequestID
        let username = draft.username
        guard !username.isEmpty else { return }
        do {
            let available = try await repository.checkUsernameAvailable(username)
            guard isCurrent(generation), requestID == usernameRequestID, draft.username == username else { return }
            usernameAvailable = available
        } catch {
            guard accept(error, requestID: generation) else { return }
            guard isCurrent(generation), requestID == usernameRequestID, draft.username == username else { return }
            errorMessage = error.localizedDescription
        }
    }

    func finishSignUp() async {
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
        errorMessage = nil
        let requestID = sessionLifecycleID
        isLoading = true
        beginOperation()
        defer { finishOperation(requestID) }
        do {
            let restored = try await repository.completeSignUp(name: draft.name, username: draft.username, avatarColor: draft.avatarColor, bio: draft.bio, avatarID: draft.avatarID)
            guard isCurrent(requestID) else { return }
            session = restored
            signInPassword = ""
        } catch {
            guard accept(error, requestID: requestID) else { return }
            if error as? AuthError == .usernameTaken {
                usernameAvailable = false
                path = [.chooseUsername]
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Esqueci a senha

    func requestPasswordReset() async {
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
        if passwordResetResendCooldown > 0 {
            if path.last != .linkSent { push(.linkSent) }
            return
        }
        let email = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = sessionLifecycleID
        errorMessage = nil
        isLoading = true
        defer { if requestID == sessionLifecycleID { isLoading = false } }
        do {
            try await repository.requestPasswordReset(email: email)
            guard isCurrent(requestID) else { return }
            resetEmail = email
            resendCooldowns.recordSend(for: .passwordReset, email: email)
            if path.last != .linkSent { push(.linkSent) }
        } catch {
            guard accept(error, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func handleEmailLink(_ url: URL) async {
        // Keep only the latest link while another authentication operation is in flight.
        pendingEmailLink = url
        await processPendingEmailLink()
    }

    private func processPendingEmailLink() async {
        guard !isEndingSession, !deletionPending, !isBootstrapping, !isLoading, let url = pendingEmailLink else { return }
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
        defer { if requestID == sessionLifecycleID { isLoading = false } }
        do {
            let result = try await repository.prepareEmailAction(url)
            guard isCurrent(requestID) else { return }
            switch result {
            case .resetPassword(let email):
                resetEmail = email
                path = [.signIn, .forgotPassword, .linkSent, .newPassword]
            }
        } catch {
            guard accept(error, requestID: requestID) else { return }
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
        guard bootstrapID == nil, !isEndingSession, !deletionPending, !isLoading else { return }
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
        defer { if requestID == sessionLifecycleID { isLoading = false } }
        do {
            let password = newPassword
            try await repository.resetPassword(password)
            guard isCurrent(requestID) else { return }
            newPassword = ""
            newPasswordConfirm = ""
            do {
                beginOperation()
                defer { finishOperation(requestID) }
                let restored = try await repository.signIn(identifier: email, password: password)
                guard isCurrent(requestID) else { return }
                session = restored
                path = session?.needsProfile == true ? [.chooseUsername] : []
            } catch {
                guard accept(error, requestID: requestID) else { return }
                // The code is consumed: a failed subsequent login must not retry the reset.
                signInIdentifier = email
                signInPassword = ""
                returnToLogin()
                infoMessage = L10n.text("Senha alterada. Entre com sua nova senha.")
            }
        } catch {
            guard accept(error, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Conta (chamado a partir de Ajustes)

    func signOut() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        lifecycle.invalidate()
        bootstrapID = nil
        isBootstrapping = false
        pendingEmailLink = nil
        await drainOperations()
        await PushCoordinator.shared.disconnect(cleanupAPI: session.map { AccountAPIClient(expectedUserID: $0.userID) })
        do {
            try await repository.signOut()
            reset()
            await AppBadgeCoordinator.shared.sync(userID: nil, unreadCount: nil)
        } catch {
            // A failed explicit logout keeps the current session, with a new API binding.
            errorMessage = error.localizedDescription
        }
        isLoading = false
        isEndingSession = false
    }

    func deleteAccount() async throws {
        guard !isEndingSession else { return }
        isEndingSession = true
        lifecycle.invalidate()
        await drainOperations()
        await PushCoordinator.shared.disconnect(cleanupAPI: session.map { AccountAPIClient(expectedUserID: $0.userID) })
        do {
            try await repository.deleteAccount()
            defaults.removeObject(forKey: Self.deletionKey)
            deletionPending = false
            reset()
            await AppBadgeCoordinator.shared.sync(userID: nil, unreadCount: nil)
            isEndingSession = false
        } catch {
            isEndingSession = false
            if let failure = error as? AuthError, [.deletionPending, .sessionExpired, .accountDisabled].contains(failure) {
                endInvalidSession(failure)
                await cleanupTask?.value
                return
            }
            throw error
        }
    }

    /// Terminal failures remove private UI immediately, then drain provider work
    /// before signing out so an old SDK callback cannot resurrect the identity.
    private func endInvalidSession(_ error: AuthError) {
        guard !isEndingSession else { return }
        isEndingSession = true
        let cleanupAPI = session.map { AccountAPIClient(expectedUserID: $0.userID) }
        reset()
        deletionPending = error == .deletionPending
        if deletionPending { defaults.set(true, forKey: Self.deletionKey) }
        else { path = [.signIn]; infoMessage = error.localizedDescription }
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            await self.drainOperations()
            await PushCoordinator.shared.disconnect(cleanupAPI: cleanupAPI)
            do { try await self.repository.signOut() }
            catch { self.errorMessage = error.localizedDescription }
            await AppBadgeCoordinator.shared.sync(userID: nil, unreadCount: nil)
            self.isEndingSession = false
        }
    }

    func acknowledgePendingDeletion() {
        guard !isEndingSession else { return }
        defaults.removeObject(forKey: Self.deletionKey)
        deletionPending = false
        returnToLogin()
    }

    private func reset() {
        pendingEmailLink = nil
        lifecycle.invalidate()
        bootstrapID = nil
        isBootstrapping = false
        isLoading = false
        fieldError = nil
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
