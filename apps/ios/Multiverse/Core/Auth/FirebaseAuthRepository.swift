import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseAnalytics
import GoogleSignIn
import UIKit

/// Authentication boundary, injectable without contacting Google or Firebase in tests.
@MainActor
protocol GoogleAuthenticationClient: Sendable {
    func currentSession() -> AuthSession?
    func signIn() async throws -> AuthSession
    func signOut() throws
    func deleteAccount() async throws
}

@MainActor
final class FirebaseGoogleAuthenticationClient: GoogleAuthenticationClient {
    func currentSession() -> AuthSession? {
        guard let user = Auth.auth().currentUser else { return nil }
        if user.providerData.contains(where: { $0.providerID == "password" }),
           !user.isEmailVerified { return nil }
        return session(for: user)
    }

    func signIn() async throws -> AuthSession {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let presenter = Self.presentingViewController() else {
            throw AuthError.googleSignInFailed
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.googleSignInFailed
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken, accessToken: result.user.accessToken.tokenString
            )
            let authenticated = try await Auth.auth().signIn(with: credential)
            if authenticated.additionalUserInfo?.isNewUser == true {
                Analytics.logEvent(AnalyticsEventSignUp, parameters: [AnalyticsParameterMethod: "google"])
            }
            Analytics.logEvent(AnalyticsEventLogin, parameters: [AnalyticsParameterMethod: "google"])
            return session(for: authenticated.user)
        } catch {
            throw Self.loginError(error)
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        Analytics.logEvent("logout", parameters: nil)
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            throw Self.loginError(error)
        }
    }

    private func session(for user: FirebaseAuth.User) -> AuthSession {
        // A Google display name is not a reserved Multiverse username.
        AuthSession(userID: user.uid, email: user.email ?? "", handle: "", displayName: user.displayName)
    }

    static func loginError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain, nsError.code == GIDSignInError.canceled.rawValue {
            return .cancelled
        }
        if nsError.domain == NSURLErrorDomain { return .networkUnavailable }
        if nsError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: nsError.code) {
            case .networkError: return .networkUnavailable
            case .requiresRecentLogin: return .recentLoginRequired
            default: break
            }
        }
        return (error as? AuthError) ?? .googleSignInFailed
    }

    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// Firebase Google/e-mail authentication. Email confirmation uses callable functions.
/// Profiles are authoritative in the API. Local profile storage is used only by injected demo/test clients.
@MainActor
final class FirebaseAuthRepository: AuthRepository {
    private let client: any GoogleAuthenticationClient
    private let defaults: UserDefaults
    private let emailClient: any EmailAuthenticationClient
    private var resetCode: String?
    private var resetRequestID = UUID()
    private let accountAPI: (any AccountAPI)?

    init(client: any GoogleAuthenticationClient = FirebaseGoogleAuthenticationClient(), defaults: UserDefaults = .standard, emailClient: any EmailAuthenticationClient = FirebaseEmailAuthenticationClient(), accountAPI: (any AccountAPI)? = AccountAPIClient()) {
        self.client = client
        self.defaults = defaults
        self.emailClient = emailClient
        self.accountAPI = accountAPI
    }

    func currentSession() async throws -> AuthSession? {
        guard let session = client.currentSession() else { return nil }
        return try await resolved(session)
    }
    func signInWithGoogle() async throws -> AuthSession { try await resolved(client.signIn()) }
    func signOut() async throws {
        try client.signOut()
        invalidateResetAction()
    }
    func deleteAccount() async throws {
        let id = client.currentSession()?.userID
        if let accountAPI {
            try await accountAPI.deleteAccount()
            try client.signOut()
        } else {
            try await client.deleteAccount()
        }
        invalidateResetAction()
        if let id {
            for key in ["mv-onboarded-\(id)", "mv-account-settings-\(id)", "mv-blocked-users-\(id)", "mv-local-profile-\(id)"] {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func signIn(identifier: String, password: String) async throws -> AuthSession {
        try await resolved(emailClient.signIn(email: Self.normalizedEmail(identifier), password: password))
    }
    func signInWithApple() async throws -> AuthSession { throw AuthError.unavailable }
    func pendingSignUpEmail() async -> String? { emailClient.pendingEmail() }
    func startSignUp(email: String, password: String) async throws {
        try await emailClient.createAccount(email: Self.normalizedEmail(email), password: password)
    }
    func resendVerificationCode() async throws { try await emailClient.sendVerification() }
    func verifyCode(_ code: String) async throws { try await emailClient.confirmVerification(code: code) }
    func checkUsernameAvailable(_ username: String) async throws -> Bool {
        guard username.range(of: "^[a-zA-Z0-9_.]{3,24}$", options: .regularExpression) != nil else { return false }
        if let accountAPI { return try await accountAPI.usernameAvailable(username) }
        return true
    }
    func completeSignUp(name: String, username: String, avatarColor: String, bio: String, avatarID: String? = nil) async throws -> AuthSession {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AuthError.profileIncomplete }
        if let accountAPI {
            guard let session = client.currentSession() else { throw AuthError.sessionExpired }
            let profile = try await accountAPI.saveProfile(name: name, username: username, avatarColor: avatarColor, bio: bio, avatarID: avatarID)
            guard profile.userID == session.userID else { throw AuthError.sessionExpired }
            return sessionWithProfile(session, profile: profile, onboarding: nil)
        }
        let session = try await emailClient.completeProfile(name: name)
        let profile = LocalAuthProfile(handle: username.isEmpty ? "" : "@" + username, avatarColor: avatarColor, bio: bio, avatarID: avatarID)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: "mv-local-profile-\(session.userID)")
        }
        return decorated(session)
    }
    func requestPasswordReset(email: String) async throws {
        try await emailClient.sendPasswordReset(email: Self.normalizedEmail(email))
    }
    func prepareEmailAction(_ url: URL) async throws -> EmailActionResult {
        invalidateResetAction()
        let requestID = resetRequestID
        guard let options = FirebaseApp.app()?.options, let projectID = options.projectID,
              let apiKey = options.apiKey else { throw AuthError.invalidActionLink }
        let link = try EmailActionLink(url: url, projectID: projectID, apiKey: apiKey)
        switch link.mode {
        case .resetPassword:
            let email = try await emailClient.validateResetCode(link.code)
            guard requestID == resetRequestID else { throw AuthError.invalidActionLink }
            resetCode = link.code
            return .resetPassword(email: email)
        case .verifyEmail:
            throw AuthError.invalidActionLink
        }
    }
    func resetPassword(_ newPassword: String) async throws {
        guard let code = resetCode else { throw AuthError.invalidActionLink }
        let requestID = resetRequestID
        try await emailClient.confirmPasswordReset(code: code, password: newPassword)
        if requestID == resetRequestID { invalidateResetAction() }
    }
    private func invalidateResetAction() {
        resetCode = nil
        resetRequestID = UUID()
    }
    private func resolved(_ session: AuthSession) async throws -> AuthSession {
        guard let accountAPI else { return decorated(session) }
        let account = try await accountAPI.fetchAccount()
        guard let profile = account.profile else {
            var pending = session
            pending.needsProfile = true
            return pending
        }
        guard profile.userID == session.userID else { throw AuthError.sessionExpired }
        return sessionWithProfile(session, profile: profile, onboarding: account.onboarding)
    }
    private func sessionWithProfile(_ session: AuthSession, profile: RemoteProfile, onboarding: OnboardingState?) -> AuthSession {
        AuthSession(userID: session.userID, email: session.email, handle: "@" + profile.username,
                    displayName: profile.displayName, avatarColor: profile.avatarColor, bio: profile.bio,
                    onboarding: onboarding, avatarID: profile.avatarID)
    }
    private static func normalizedEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            throw AuthError.invalidEmail
        }
        return email
    }
    private struct LocalAuthProfile: Codable {
        let handle: String
        let avatarColor: String
        let bio: String
        var avatarID: String? = nil
    }
    private func decorated(_ session: AuthSession) -> AuthSession {
        guard let data = defaults.data(forKey: "mv-local-profile-\(session.userID)"),
              let profile = try? JSONDecoder().decode(LocalAuthProfile.self, from: data) else { return session }
        return AuthSession(userID: session.userID, email: session.email, handle: profile.handle,
                           displayName: session.displayName, avatarColor: profile.avatarColor, bio: profile.bio, avatarID: profile.avatarID)
    }

    func fetchAccountSettings() async -> AccountSettings {
        read("mv-account-settings") ?? AccountSettings()
    }
    func updateAccountSettings(_ settings: AccountSettings) async { write(settings, key: "mv-account-settings") }
    func fetchBlockedUsers() async -> [BlockedUser] { read("mv-blocked-users") ?? [] }
    func blockUser(handle: String) async {
        var users = await fetchBlockedUsers()
        guard !users.contains(where: { $0.handle == handle }) else { return }
        users.append(BlockedUser(id: handle, handle: handle, blockedOn: L10n.text("hoje")))
        write(users, key: "mv-blocked-users")
    }
    func unblockUser(_ id: String) async {
        let users = await fetchBlockedUsers().filter { $0.id != id }
        write(users, key: "mv-blocked-users")
    }
    private func read<T: Decodable>(_ key: String) -> T? {
        guard let id = client.currentSession()?.userID,
              let data = defaults.data(forKey: "\(key)-\(id)") else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func write<T: Encodable>(_ value: T, key: String) {
        guard let id = client.currentSession()?.userID, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "\(key)-\(id)")
    }
}
