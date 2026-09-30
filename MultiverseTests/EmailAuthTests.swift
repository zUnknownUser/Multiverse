import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class EmailClientStub: EmailAuthenticationClient {
    var pending: String?
    var error: AuthError?
    var resetEmails: [String] = []
    var receivedCode: String?
    var resetPassword: String?
    func pendingEmail() -> String? { pending }
    func pendingEmailIsVerified() -> Bool { false }
    func signIn(email: String, password: String) async throws -> AuthSession {
        if let error { throw error }
        return AuthSession(userID: "email-user", email: email, handle: "", displayName: "Teste")
    }
    func createAccount(email: String, password: String) async throws {
        if let error { throw error }
        pending = email
    }
    func sendVerification() async throws { if let error { throw error } }
    func confirmVerification(code: String?) async throws {
        if let error { throw error }
        receivedCode = code
    }
    func completeProfile(name: String) async throws -> AuthSession {
        if let error { throw error }
        return AuthSession(userID: "email-user", email: pending ?? "test@example.com", handle: "", displayName: name)
    }
    func sendPasswordReset(email: String) async throws {
        if let error { throw error }
        resetEmails.append(email)
    }
    func validateResetCode(_ code: String) async throws -> String {
        if let error { throw error }
        receivedCode = code
        return "test@example.com"
    }
    func confirmPasswordReset(code: String, password: String) async throws {
        if let error { throw error }
        receivedCode = code
        resetPassword = password
    }
}

@MainActor
struct EmailAuthTests {
    @Test func emailLoginNormalizesWhitespace() async throws {
        let client = EmailClientStub()
        let repository = FirebaseAuthRepository(emailClient: client)
        let result = try await repository.signIn(identifier: " test@example.com \n", password: "Password1")
        #expect(result.email == "test@example.com")
    }

    @Test func usernameIsNotTreatedAsEmail() async {
        let repository = FirebaseAuthRepository(emailClient: EmailClientStub())
        await #expect(throws: AuthError.invalidEmail) {
            try await repository.signIn(identifier: "@lorista", password: "Password1")
        }
    }

    @Test func resetFailureDoesNotClaimEmailWasSent() async {
        let client = EmailClientStub()
        client.error = .networkUnavailable
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client))
        store.resetEmail = "test@example.com"
        store.path = [.signIn, .forgotPassword]
        await store.requestPasswordReset()
        #expect(store.path.last == .forgotPassword)
        #expect(store.resendCooldown == 0)
        #expect(store.errorMessage != nil)
    }

    @Test func resetRequestCannotBeRepeatedDuringCooldown() async {
        let client = EmailClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client))
        store.resetEmail = "test@example.com"
        store.path = [.signIn, .forgotPassword]
        await store.requestPasswordReset()
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 1)
        #expect(store.path.filter { $0 == .linkSent }.count == 1)
    }

    @Test func newPasswordRequiresVerifiedResetCode() async {
        let client = EmailClientStub()
        let repository = FirebaseAuthRepository(emailClient: client)
        await #expect(throws: AuthError.invalidActionLink) {
            try await repository.resetPassword("Password1")
        }
        #expect(client.resetPassword == nil)
    }

    @Test func unverifiedLoginReturnsToVerificationInsteadOfApp() async {
        let client = EmailClientStub()
        client.error = .emailNotVerified
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client))
        store.signInIdentifier = "test@example.com"
        store.signInPassword = "Password1"
        await store.signIn()
        #expect(store.session == nil)
        #expect(store.path.last == .verifyCode)
        #expect(store.draft.email == "test@example.com")
    }

    @Test func sixDigitConfirmationAdvancesOnlyOnSuccess() async {
        let client = EmailClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client))
        store.path = [.verifyCode]
        store.verificationCode = "001234"
        client.error = .invalidCode
        await store.submitCode()
        #expect(store.path.last == .verifyCode)
        #expect(store.verificationCode.isEmpty)
        client.error = nil
        store.verificationCode = "001234"
        await store.submitCode()
        #expect(client.receivedCode == "001234")
        #expect(store.path.last == .chooseUsername)
        #expect(store.session == nil)
    }

    @Test func verifiedResetLinkOpensExistingScreenAndConsumesCode() async throws {
        let client = EmailClientStub()
        let repository = FirebaseAuthRepository(emailClient: client)
        let store = AuthStore(repository: repository)
        store.isBootstrapping = false
        await store.handleEmailLink(try resetURL())
        #expect(store.path.last == .newPassword)
        #expect(store.resetEmail == "test@example.com")
        store.newPassword = "Password1"
        store.newPasswordConfirm = "Password1"
        await store.submitNewPassword()
        #expect(client.resetPassword == "Password1")
        #expect(store.session?.userID == "email-user")
        #expect(store.path.isEmpty)
        #expect(store.newPassword.isEmpty)
        await #expect(throws: AuthError.invalidActionLink) {
            try await repository.resetPassword("AnotherPassword1")
        }
    }

    @Test func expiredResetLinkDoesNotOpenNewPasswordScreen() async throws {
        let client = EmailClientStub()
        client.error = .invalidActionLink
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client))
        store.isBootstrapping = false
        await store.handleEmailLink(try resetURL())
        #expect(store.path.last != .newPassword)
        #expect(store.errorMessage != nil)
        #expect(client.resetPassword == nil)
    }

    private func resetURL() throws -> URL {
        let resource = try #require(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let config = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: Any])
        let project = try #require(config["PROJECT_ID"] as? String)
        let apiKey = try #require(config["API_KEY"] as? String)
        var url = URLComponents()
        url.scheme = "https"
        url.host = "\(project).firebaseapp.com"
        url.path = "/__/auth/action"
        url.queryItems = [URLQueryItem(name: "mode", value: "resetPassword"),
                          URLQueryItem(name: "oobCode", value: "test-only-code"),
                          URLQueryItem(name: "apiKey", value: apiKey)]
        return try #require(url.url)
    }

    @Test func actionParserAcceptsFirebaseResetLink() throws {
        let url = try #require(URL(string: "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=test-code&apiKey=test-key"))
        let action = try EmailActionLink(url: url, projectID: "demo", apiKey: "test-key")
        #expect(action.mode == .resetPassword)
        #expect(action.code == "test-code")
    }

    @Test(arguments: [
        "https://evil.example/__/auth/action?mode=resetPassword&oobCode=test-code&apiKey=test-key",
        "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=test-code&apiKey=other-key",
        "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=a&oobCode=b&apiKey=test-key",
        "https://demo.firebaseapp.com/__/auth/action?mode=resetPassword&apiKey=test-key",
        "https://demo.firebaseapp.com/__/auth/action?mode=signIn&oobCode=test-code&apiKey=test-key"
    ])
    func actionParserRejectsWrongProjectAndMalformedLinks(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(throws: AuthError.invalidActionLink) {
            try EmailActionLink(url: url, projectID: "demo", apiKey: "test-key")
        }
    }
}
