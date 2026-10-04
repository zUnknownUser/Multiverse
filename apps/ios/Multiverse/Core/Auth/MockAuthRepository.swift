import Foundation

/// Implementação em memória (+ `UserDefaults` pra sessão) de `AuthRepository`.
/// Conta de demonstração: e-mail `duda.kaminski@gmail.com` / usuário `@duda.lore` / senha `Multiverse1`.
actor MockAuthRepository: AuthRepository {
    private static let sessionKey = "mv-session"
    private static let demoUserID = "duda"
    private static let demoEmail = "duda.kaminski@gmail.com"
    private static let demoHandle = "@duda.lore"

    private var storedPassword = "Multiverse1"
    private var failedAttempts = 0
    private var lockedUntil: Date?

    private var pendingEmail = ""
    private var pendingPassword = ""
    private var isCodeVerified = false

    private var settings = AccountSettings()
    private var blockedUsers = [
        BlockedUser(id: "troll", handle: "@troll.do.flagelo", blockedOn: L10n.text("12 set")),
        BlockedUser(id: "spoiler", handle: "@spoiler.sem.aviso", blockedOn: L10n.text("3 ago")),
    ]

    private let simulatedLatency: Duration = .milliseconds(350)
    private func delay() async { try? await Task.sleep(for: simulatedLatency) }

    // MARK: - Sessão

    func currentSession() async -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    private func persist(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    // MARK: - Entrar

    func signIn(identifier: String, password: String) async throws -> AuthSession {
        await delay()
        if let until = lockedUntil, until > .now {
            let minutes = Int((until.timeIntervalSinceNow / 60).rounded(.up))
            throw AuthError.lockedOut(minutes: max(1, minutes))
        }
        let normalized = identifier.trimmingCharacters(in: .whitespaces).lowercased()
        let matchesAccount = normalized == Self.demoEmail
            || normalized == Self.demoHandle.lowercased()
            || normalized == String(Self.demoHandle.dropFirst()).lowercased()

        guard matchesAccount, password == storedPassword else {
            failedAttempts += 1
            if failedAttempts >= 3 {
                lockedUntil = .now.addingTimeInterval(5 * 60)
                throw AuthError.lockedOut(minutes: 5)
            }
            throw AuthError.invalidCredentials(attemptsRemaining: 3 - failedAttempts)
        }

        failedAttempts = 0
        lockedUntil = nil
        let session = AuthSession(userID: Self.demoUserID, email: Self.demoEmail, handle: Self.demoHandle)
        persist(session)
        return session
    }

    func signInWithApple() async throws -> AuthSession {
        await delay()
        let session = AuthSession(userID: Self.demoUserID, email: Self.demoEmail, handle: Self.demoHandle)
        persist(session)
        return session
    }

    func signInWithGoogle() async throws -> AuthSession {
        try await signInWithApple()
    }

    // MARK: - Criar conta

    func startSignUp(email: String, password: String) async throws {
        await delay()
        pendingEmail = email
        pendingPassword = password
        isCodeVerified = false
    }

    func resendVerificationCode() async throws {
        await delay()
    }

    func verifyCode(_ code: String) async throws {
        await delay()
        guard code.count == 6, code.allSatisfy(\.isNumber) else { throw AuthError.invalidCode }
        isCodeVerified = true
    }

    func checkUsernameAvailable(_ username: String) async -> Bool {
        await delay()
        let taken: Set<String> = ["admin", "multiverse", "suporte"]
        return username.count >= 3 && !taken.contains(username.lowercased())
    }

    func completeSignUp(name: String, username: String, avatarColor: String, bio: String, avatarID: String? = nil) async throws -> AuthSession {
        await delay()
        guard isCodeVerified else { throw AuthError.invalidCode }
        storedPassword = pendingPassword
        let session = AuthSession(userID: Self.demoUserID, email: pendingEmail, handle: "@\(username)", displayName: name, avatarColor: avatarColor, bio: bio, avatarID: avatarID)
        persist(session)
        return session
    }

    // MARK: - Esqueci a senha

    func requestPasswordReset(email: String) async throws {
        await delay()
    }

    func resetPassword(_ newPassword: String) async throws {
        await delay()
        storedPassword = newPassword
        failedAttempts = 0
        lockedUntil = nil

    }

    // MARK: - Conta

    func deleteAccount() async throws {
        await delay()
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    func fetchAccountSettings() async -> AccountSettings {
        await delay()
        return settings
    }

    func updateAccountSettings(_ newSettings: AccountSettings) async {
        settings = newSettings
    }

    func fetchBlockedUsers() async -> [BlockedUser] {
        await delay()
        return blockedUsers
    }

    func unblockUser(_ id: String) async {
        blockedUsers.removeAll { $0.id == id }
    }

    func blockUser(handle: String) async {
        let id = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !blockedUsers.contains(where: { $0.handle == handle }) else { return }
        blockedUsers.append(BlockedUser(id: id, handle: handle, blockedOn: L10n.text("hoje")))
    }
}
