import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class EmailClientStub: EmailAuthenticationClient {
    var pending: String?
    var error: AuthError?
    var resetEmails: [String] = []
    var verificationRequests = 0
    var signupRequests = 0
    var signInCalls = 0
    var suspendConfirmation = false
    var confirmationContinuation: CheckedContinuation<Void, Never>?
    func resumeConfirmation() {
        confirmationContinuation?.resume()
        confirmationContinuation = nil
    }
    var receivedCode: String?
    var resetPassword: String?
    var needsProfile = false
    var suspendResetRequest = false
    var resetRequestContinuation: CheckedContinuation<Void, Never>?
    var validatedCodes: [String] = []
    var suspendValidation = false
    var validationContinuation: CheckedContinuation<Void, Never>?
    func resumeValidation() {
        validationContinuation?.resume()
        validationContinuation = nil
    }

    func resumeResetRequest() {
        resetRequestContinuation?.resume()
        resetRequestContinuation = nil
    }
    func pendingEmail() -> String? { pending }
    func signIn(email: String, password: String) async throws -> AuthSession {
        signInCalls += 1
        if let error { throw error }
        return AuthSession(userID: "email-user", email: email, handle: "", displayName: "Teste", needsProfile: needsProfile)
    }
    func createAccount(email: String, password: String) async throws {
        if let error { throw error }
        pending = email
        signupRequests += 1
    }
    func sendVerification() async throws {
        if let error { throw error }
        verificationRequests += 1
    }
    func confirmVerification(code: String?) async throws {
        if let error { throw error }
        receivedCode = code
    }
    func completeProfile(name: String) async throws -> AuthSession {
        if let error { throw error }
        return AuthSession(userID: "email-user", email: pending ?? "test@example.com", handle: "", displayName: name)
    }
    func sendPasswordReset(email: String) async throws {
        if suspendResetRequest {
            await withCheckedContinuation { resetRequestContinuation = $0 }
        }
        if let error { throw error }
        resetEmails.append(email)
    }
    func validateResetCode(_ code: String) async throws -> String {
        validatedCodes.append(code)
        if suspendValidation {
            await withCheckedContinuation { validationContinuation = $0 }
        }
        if let error { throw error }
        receivedCode = code
        return "test@example.com"
    }
    func confirmPasswordReset(code: String, password: String) async throws {
        if suspendConfirmation {
            await withCheckedContinuation { confirmationContinuation = $0 }
        }
        if let error { throw error }
        receivedCode = code
        resetPassword = password
    }
}

@MainActor
struct EmailAuthTests {
    @Test(arguments: [false, true]) func logoutDuringPasswordConfirmationPreventsAutomaticLoginAndStaleErrors(fails: Bool) async throws {
        let client = EmailClientStub()
        let identity = IdentityStub(uid: "recovery-user")
        let store = AuthStore(repository: FirebaseAuthRepository(client: identity, emailClient: client, accountAPI: nil))
        store.isBootstrapping = false
        await store.handleEmailLink(try resetURL())
        store.newPassword = "Password1"
        store.newPasswordConfirm = "Password1"
        client.suspendConfirmation = true
        let confirmation = Task { await store.submitNewPassword() }
        defer { client.resumeConfirmation(); confirmation.cancel() }
        try await waitUntil { client.confirmationContinuation != nil }
        await store.signOut()
        if fails { client.error = .networkUnavailable }
        client.resumeConfirmation()
        await confirmation.value
        #expect(client.signInCalls == 0)
        #expect(store.session == nil)
        #expect(store.path.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(store.infoMessage == nil)
        #expect(store.newPassword.isEmpty)
        #expect(!store.isLoading)
    }

    @Test(arguments: [false, true]) func logoutDuringResetEmailDeliveryDoesNotReopenRecovery(fails: Bool) async throws {
        let client = EmailClientStub()
        client.suspendResetRequest = true
        let cooldown = EmailResendCooldown()
        let store = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "recovery-user"), emailClient: client, accountAPI: nil), resendCooldowns: cooldown)
        store.resetEmail = "test@example.com"
        store.path = [.forgotPassword]
        let delivery = Task { await store.requestPasswordReset() }
        defer { client.resumeResetRequest(); delivery.cancel() }
        try await waitUntil { client.resetRequestContinuation != nil }
        await store.signOut()
        if fails { client.error = .networkUnavailable }
        client.resumeResetRequest()
        await delivery.value
        #expect(store.path.isEmpty)
        #expect(store.resetEmail.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
        #expect(cooldown.remaining(for: .passwordReset, email: "test@example.com") == 0)
    }

    @Test func returningToForgotPasswordDoesNotBypassRecipientCooldown() async {
        let client = EmailClientStub()
        var date = Date(timeIntervalSince1970: 1_000)
        let cooldown = EmailResendCooldown(now: { date })
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil), resendCooldowns: cooldown)
        store.resetEmail = "test@example.com"
        await store.requestPasswordReset()
        store.returnToLogin()
        store.push(.forgotPassword)
        store.resetEmail = " TEST@example.com "
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 1)
        #expect(store.path.last == .linkSent)
        store.resetEmail = "other@example.com"
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 2)
        store.resetEmail = "test@example.com"
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 2)
        date += 60
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 3)
    }

    @Test func verificationDoesNotSharePasswordResetCooldownAndSignupCanResumeWithoutResending() async {
        let client = EmailClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.resetEmail = "test@example.com"
        await store.requestPasswordReset()
        store.draft.email = "test@example.com"
        store.path = [.verifyCode]
        await store.resendCode()
        await store.resendCode()
        #expect(client.verificationRequests == 1)
        #expect(store.verificationResendCooldown > 0)
        client.pending = "test@example.com"
        store.draft.password = "Password1"
        store.path = [.createAccount]
        await store.submitSignUpEmail()
        #expect(client.signupRequests == 0)
        #expect(store.path.last == .verifyCode)
        #expect(store.draft.password.isEmpty)
    }

    @Test(arguments: [false, true]) func linkArrivingDuringResetRequestWaitsForOperation(signedInBeforeDelivery: Bool) async throws {
        let client = EmailClientStub()
        client.suspendResetRequest = true
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.isBootstrapping = false
        store.resetEmail = "test@example.com"
        store.path = [.signIn, .forgotPassword]
        let request = Task { await store.requestPasswordReset() }
        defer { client.resumeResetRequest(); request.cancel() }
        try await waitUntil { client.resetRequestContinuation != nil }
        await store.handleEmailLink(try resetURL(code: "older-code"))
        await store.handleEmailLink(try resetURL(code: "latest-code"))
        #expect(client.validatedCodes.isEmpty)
        if signedInBeforeDelivery {
            store.session = AuthSession(userID: "signed-in", email: "other@example.com", handle: "@other")
        }
        client.resumeResetRequest()
        await request.value
        try await waitUntil { store.path.last == .newPassword || store.infoMessage != nil }
        if signedInBeforeDelivery {
            #expect(store.session?.userID == "signed-in")
            #expect(store.path.last != .newPassword)
            #expect(store.infoMessage != nil)
            #expect(client.validatedCodes.isEmpty)
        } else {
            #expect(store.path.last == .newPassword)
            #expect(client.validatedCodes == ["latest-code"])
            #expect(!store.isLoading)
        }
    }

    @Test func logoutDiscardsLinkQueuedDuringAnotherOperation() async throws {
        let client = EmailClientStub()
        let identity = IdentityStub(uid: "previous-user")
        let store = AuthStore(repository: FirebaseAuthRepository(client: identity, emailClient: client, accountAPI: nil))
        store.isBootstrapping = false
        store.isLoading = true
        await store.handleEmailLink(try resetURL())
        await store.signOut()
        store.isLoading = false
        for _ in 0..<10 { await Task.yield() }
        #expect(client.validatedCodes.isEmpty)
        #expect(store.path.isEmpty)
    }

    @Test func logoutInvalidatesLinkValidationAlreadyInFlight() async throws {
        let client = EmailClientStub()
        client.suspendValidation = true
        let identity = IdentityStub(uid: "previous-user")
        let repository = FirebaseAuthRepository(client: identity, emailClient: client, accountAPI: nil)
        let store = AuthStore(repository: repository)
        store.isBootstrapping = false
        let url = try resetURL()
        let validation = Task { await store.handleEmailLink(url) }
        defer { client.resumeValidation(); validation.cancel() }
        try await waitUntil { client.validationContinuation != nil }
        await store.signOut()
        client.resumeValidation()
        await validation.value
        #expect(store.path.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
        await #expect(throws: AuthError.invalidActionLink) {
            try await repository.resetPassword("Password1")
        }
        #expect(client.resetPassword == nil)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    @Test func unverifiedAccountRestoresVerificationScreenOnLaunch() async {
        let email = EmailClientStub()
        email.pending = "pending@example.com"
        let identity = IdentityStub(uid: "pending-user")
        identity.session = nil
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, emailClient: email, accountAPI: nil))
        await auth.bootstrap()
        #expect(auth.session == nil)
        #expect(auth.draft.email == "pending@example.com")
        #expect(auth.path == [.createAccount, .verifyCode])
        #expect(!auth.isBootstrapping)
    }

    @Test func emailLoginNormalizesWhitespace() async throws {
        let client = EmailClientStub()
        let repository = FirebaseAuthRepository(emailClient: client, accountAPI: nil)
        let result = try await repository.signIn(identifier: " test@example.com \n", password: "Password1")
        #expect(result.email == "test@example.com")
    }

    @Test func usernameIsNotTreatedAsEmail() async {
        let repository = FirebaseAuthRepository(emailClient: EmailClientStub(), accountAPI: nil)
        await #expect(throws: AuthError.invalidEmail) {
            try await repository.signIn(identifier: "@lorista", password: "Password1")
        }
    }

    @Test func resetFailureDoesNotClaimEmailWasSent() async {
        let client = EmailClientStub()
        client.error = .networkUnavailable
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.resetEmail = "test@example.com"
        store.path = [.signIn, .forgotPassword]
        await store.requestPasswordReset()
        #expect(store.path.last == .forgotPassword)
        #expect(store.passwordResetResendCooldown == 0)
        #expect(store.errorMessage != nil)
    }

    @Test func resetRequestCannotBeRepeatedDuringCooldown() async {
        let client = EmailClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.resetEmail = "test@example.com"
        store.path = [.signIn, .forgotPassword]
        await store.requestPasswordReset()
        await store.requestPasswordReset()
        #expect(client.resetEmails.count == 1)
        #expect(store.path.filter { $0 == .linkSent }.count == 1)
    }

    @Test func newPasswordRequiresVerifiedResetCode() async {
        let client = EmailClientStub()
        let repository = FirebaseAuthRepository(emailClient: client, accountAPI: nil)
        await #expect(throws: AuthError.invalidActionLink) {
            try await repository.resetPassword("Password1")
        }
        #expect(client.resetPassword == nil)
    }

    @Test func unverifiedLoginReturnsToVerificationInsteadOfApp() async {
        let client = EmailClientStub()
        client.error = .emailNotVerified
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.signInIdentifier = "test@example.com"
        store.signInPassword = "Password1"
        await store.signIn()
        #expect(store.session == nil)
        #expect(store.path.last == .verifyCode)
        #expect(store.draft.email == "test@example.com")
    }

    @Test func sixDigitConfirmationAdvancesOnlyOnSuccess() async {
        let client = EmailClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
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

    @Test(arguments: [false, true]) func verifiedResetLinkOpensExistingScreenAndConsumesCode(needsProfile: Bool) async throws {
        let client = EmailClientStub()
        client.needsProfile = needsProfile
        let suite = "password-reset-profile-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = FirebaseAuthRepository(defaults: defaults, emailClient: client, accountAPI: nil)
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
        #expect(store.path == (needsProfile ? [.chooseUsername] : []))
        #expect(store.newPassword.isEmpty)
        await #expect(throws: AuthError.invalidActionLink) {
            try await repository.resetPassword("AnotherPassword1")
        }
    }

    @Test func expiredResetLinkDoesNotOpenNewPasswordScreen() async throws {
        let client = EmailClientStub()
        client.error = .invalidActionLink
        let store = AuthStore(repository: FirebaseAuthRepository(emailClient: client, accountAPI: nil))
        store.isBootstrapping = false
        await store.handleEmailLink(try resetURL())
        #expect(store.path.last != .newPassword)
        #expect(store.errorMessage != nil)
        #expect(client.resetPassword == nil)
    }

    private func resetURL(code: String = "test-only-code") throws -> URL {
        let resource = try #require(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let config = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: resource), format: nil) as? [String: Any])
        let project = try #require(config["PROJECT_ID"] as? String)
        let apiKey = try #require(config["API_KEY"] as? String)
        var url = URLComponents()
        url.scheme = "https"
        url.host = "\(project).firebaseapp.com"
        url.path = "/__/auth/action"
        url.queryItems = [URLQueryItem(name: "mode", value: "resetPassword"),
                          URLQueryItem(name: "oobCode", value: code),
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
