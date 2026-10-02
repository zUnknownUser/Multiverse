import Foundation
import FirebaseAuth
import FirebaseAnalytics
import FirebaseFunctions
import FirebaseCore

@MainActor
protocol EmailAuthenticationClient: Sendable {
    /// Returns nil once the email is verified; profile completion belongs to AccountAPI.
    func pendingEmail() -> String?
    func signIn(email: String, password: String) async throws -> AuthSession
    func createAccount(email: String, password: String) async throws
    func sendVerification() async throws
    func confirmVerification(code: String?) async throws
    func completeProfile(name: String) async throws -> AuthSession
    func sendPasswordReset(email: String) async throws
    func validateResetCode(_ code: String) async throws -> String
    func confirmPasswordReset(code: String, password: String) async throws
}

@MainActor
final class FirebaseEmailAuthenticationClient: EmailAuthenticationClient {
    func pendingEmail() -> String? {
        guard let user = Auth.auth().currentUser,
              user.providerData.contains(where: { $0.providerID == "password" }),
              !user.isEmailVerified else { return nil }
        return user.email
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            guard result.user.isEmailVerified else { throw AuthError.emailNotVerified }
            Analytics.logEvent(AnalyticsEventLogin, parameters: [AnalyticsParameterMethod: "password"])
            return Self.session(result.user)
        } catch { throw Self.failure(error) }
    }

    func createAccount(email: String, password: String) async throws {
        do {
            // Resume an interrupted signup instead of trying to create the same user again.
            if Auth.auth().currentUser?.email?.lowercased() != email.lowercased() || pendingEmail() == nil {
                _ = try await Auth.auth().createUser(withEmail: email, password: password)
                Analytics.logEvent(AnalyticsEventSignUp, parameters: [AnalyticsParameterMethod: "password"])
            }
            try await sendVerification()
        } catch { throw Self.failure(error) }
    }

    func sendVerification() async throws {
        guard Auth.auth().currentUser != nil else { throw AuthError.sessionExpired }
        do {
            Auth.auth().languageCode = L10n.language()
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("requestEmailVerificationCode").call(["locale": L10n.language()])
        } catch { throw Self.failure(error) }
    }

    func confirmVerification(code: String?) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthError.sessionExpired }
        do {
            guard let code, code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
                throw AuthError.invalidCode
            }
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("confirmEmailVerificationCode").call(["code": code])
            try await user.reload()
            guard user.isEmailVerified else { throw AuthError.emailNotVerified }
            _ = try await user.getIDToken(forcingRefresh: true)
        } catch { throw Self.failure(error) }
    }

    func completeProfile(name: String) async throws -> AuthSession {
        guard let user = Auth.auth().currentUser else { throw AuthError.sessionExpired }
        do {
            try await user.reload()
            guard user.isEmailVerified else { throw AuthError.emailNotVerified }
            let change = user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            return Self.session(user)
        } catch { throw Self.failure(error) }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            Auth.auth().languageCode = L10n.language()
            let settings = ActionCodeSettings()
            settings.handleCodeInApp = true
            settings.setIOSBundleID(Bundle.main.bundleIdentifier ?? "com.nexussoft.multiverse")
            guard let projectID = FirebaseApp.app()?.options.projectID else { throw AuthError.emailAuthenticationFailed }
            settings.url = URL(string: "https://\(projectID).firebaseapp.com")
            try await Auth.auth().sendPasswordReset(withEmail: email, actionCodeSettings: settings)
        } catch {
            // Do not reveal whether an address is registered.
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain && nsError.code == AuthErrorCode.userNotFound.rawValue { return }
            throw Self.failure(error)
        }
    }

    func validateResetCode(_ code: String) async throws -> String {
        do { return try await Auth.auth().verifyPasswordResetCode(code) }
        catch { throw Self.failure(error) }
    }

    func confirmPasswordReset(code: String, password: String) async throws {
        do { try await Auth.auth().confirmPasswordReset(withCode: code, newPassword: password) }
        catch { throw Self.failure(error) }
    }

    private static func session(_ user: FirebaseAuth.User) -> AuthSession {
        AuthSession(userID: user.uid, email: user.email ?? "", handle: "", displayName: user.displayName)
    }

    static func failure(_ error: Error) -> AuthError {
        if let error = error as? AuthError { return error }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .networkUnavailable }
        if nsError.domain == FunctionsErrorDomain {
            switch FunctionsErrorCode(rawValue: nsError.code) {
            case .resourceExhausted: return .tooManyRequests
            case .invalidArgument: return .invalidCode
            case .deadlineExceeded: return .verificationCodeExpired
            case .unauthenticated: return .sessionExpired
            case .notFound, .unavailable: return .verificationUnavailable
            default: return .emailAuthenticationFailed
            }
        }
        guard nsError.domain == AuthErrorDomain else { return .emailAuthenticationFailed }
        switch AuthErrorCode(rawValue: nsError.code) {
        case .invalidEmail: return .invalidEmail
        case .wrongPassword, .userNotFound, .invalidCredential: return .emailCredentialsInvalid
        case .emailAlreadyInUse: return .emailAlreadyRegistered
        case .weakPassword: return .weakPassword
        case .userDisabled: return .accountDisabled
        case .tooManyRequests: return .tooManyRequests
        case .operationNotAllowed: return .emailProviderDisabled
        case .expiredActionCode, .invalidActionCode: return .invalidActionLink
        case .networkError: return .networkUnavailable
        case .requiresRecentLogin: return .recentLoginRequired
        case .userTokenExpired, .invalidUserToken: return .sessionExpired
        default: return .emailAuthenticationFailed
        }
    }
}

/// Only Firebase action links for this project are accepted. Tokens are kept in memory.
struct EmailActionLink: Equatable {
    enum Mode: String { case resetPassword, verifyEmail }
    let mode: Mode
    let code: String

    init(url: URL, projectID: String, apiKey: String) throws {
        var candidate = url
        for _ in 0..<3 {
            guard candidate.scheme == "https",
                  ["\(projectID).firebaseapp.com", "\(projectID).web.app"].contains(candidate.host ?? ""),
                  let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else {
                throw AuthError.invalidActionLink
            }
            let items = components.queryItems ?? []
            if let nested = items.first(where: { $0.name == "link" })?.value,
               let nestedURL = URL(string: nested) {
                candidate = nestedURL
                continue
            }
            func value(_ name: String) -> String? {
                let matches = items.filter { $0.name == name }
                return matches.count == 1 ? matches.first?.value : nil
            }
            guard candidate.path == "/__/auth/action",
                  value("apiKey") == apiKey,
                  let mode = Mode(rawValue: value("mode") ?? ""),
                  let code = value("oobCode"), !code.isEmpty else { throw AuthError.invalidActionLink }
            self.mode = mode
            self.code = code
            return
        }
        throw AuthError.invalidActionLink
    }
}

enum EmailActionResult: Equatable, Sendable {
    case resetPassword(email: String)
}
