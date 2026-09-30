import Foundation

/// Autenticação e conta — protocolo separado de `MultiverseRepository` porque é uma
/// preocupação diferente (identidade, não conteúdo). FirebaseAuthRepository é a
/// implementação real; MockAuthRepository fica disponível para desenvolvimento.
protocol AuthRepository: Sendable {
    func currentSession() async throws -> AuthSession?

    func signIn(identifier: String, password: String) async throws -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signOut() async throws

    /// Envia o código de verificação pro e-mail informado.
    func startSignUp(email: String, password: String) async throws
    func resendVerificationCode() async throws
    func verifyCode(_ code: String) async throws
    func checkUsernameAvailable(_ username: String) async throws -> Bool
    func completeSignUp(name: String, username: String, avatarColor: String, bio: String) async throws -> AuthSession

    func requestPasswordReset(email: String) async throws
    /// Only an authenticated account whose email still needs confirmation.
    func pendingSignUpEmail() async -> String?
    func prepareEmailAction(_ url: URL) async throws -> EmailActionResult
    func resetPassword(_ newPassword: String) async throws

    func deleteAccount() async throws

    func fetchAccountSettings() async -> AccountSettings
    func updateAccountSettings(_ settings: AccountSettings) async

    func fetchBlockedUsers() async -> [BlockedUser]
    func blockUser(handle: String) async
    func unblockUser(_ id: String) async
}

// Demo implementations do not process real action links.
extension AuthRepository {
    func pendingSignUpEmail() async -> String? { nil }
    func prepareEmailAction(_ url: URL) async throws -> EmailActionResult { throw AuthError.invalidActionLink }
}
