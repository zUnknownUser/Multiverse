import Foundation

/// Autenticação e conta — protocolo separado de `MultiverseRepository` porque é uma
/// preocupação diferente (identidade, não conteúdo). Hoje só existe `MockAuthRepository`;
/// a fase 2 troca por um backend real (ex.: Supabase Auth) sem tocar nas Views.
protocol AuthRepository: Sendable {
    func currentSession() async -> AuthSession?

    func signIn(identifier: String, password: String) async throws -> AuthSession
    func signInWithApple() async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func signOut() async

    /// Envia o código de verificação pro e-mail informado.
    func startSignUp(email: String, password: String) async throws
    func resendVerificationCode() async throws
    func verifyCode(_ code: String) async throws
    func checkUsernameAvailable(_ username: String) async -> Bool
    func completeSignUp(name: String, username: String, avatarColor: String, bio: String) async throws -> AuthSession

    func requestPasswordReset(email: String) async throws
    /// Simula o toque no link recebido por e-mail.
    func resetPassword(_ newPassword: String) async throws -> AuthSession

    func deleteAccount() async throws

    func fetchAccountSettings() async -> AccountSettings
    func updateAccountSettings(_ settings: AccountSettings) async

    func fetchBlockedUsers() async -> [BlockedUser]
    func blockUser(handle: String) async
    func unblockUser(_ id: String) async
}
