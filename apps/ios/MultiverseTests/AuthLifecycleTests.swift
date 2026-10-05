import Foundation
import Testing
@testable import Multiverse

@MainActor private final class LifecycleAccountStub: AccountAPI {
    var hold = true
    var continuations: [CheckedContinuation<AccountEnvelope, any Error>] = []
    var calls = 0
    var failure: AuthError?
    var deletionFailure: AuthError?
    let envelope = AccountEnvelope(profile: .init(userID: "audit-owner", username: "auditowner", displayName: "Audit", avatarColor: "#F4A814", bio: ""), onboarding: .init(completed: true))
    func fetchAccount() async throws -> AccountEnvelope {
        calls += 1
        if hold { return try await withCheckedThrowingContinuation { continuations.append($0) } }
        if let failure { throw failure }
        return envelope
    }
    func release() { hold = false; let old = continuations; continuations = []; old.forEach { $0.resume(returning: envelope) } }
    func usernameAvailable(_ username: String) async throws -> Bool { true }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String, avatarID: String?) async throws -> RemoteProfile { envelope.profile! }
    func suggestions() async throws -> FollowSuggestions { .init(users: [], minimumFollows: 0) }
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState { state }
    func deleteAccount() async throws { if let deletionFailure { throw deletionFailure } }
}

@MainActor private final class LifecycleIdentityStub: GoogleAuthenticationClient {
    var session: AuthSession? = .init(userID: "audit-owner", email: "test@example.com", handle: "")
    var pending: CheckedContinuation<Void, Never>?
    var delayLogin = false
    var signOutCalls = 0
    func currentSession() -> AuthSession? { session }
    func signIn() async throws -> AuthSession {
        if delayLogin { await withCheckedContinuation { pending = $0 } }
        let result = AuthSession(userID: "audit-owner", email: "test@example.com", handle: "")
        session = result
        return result
    }
    func signOut() throws { signOutCalls += 1; session = nil }
    func deleteAccount() async throws { session = nil }
    func release() { pending?.resume(); pending = nil; delayLogin = false }
}
@MainActor private final class IdentityObservationStub: AuthIdentityObserving {
    var changed: (@MainActor @Sendable (String?) -> Void)?
    func start(_ changed: @escaping @MainActor @Sendable (String?) -> Void) { self.changed = changed }
}

@Suite(.serialized) @MainActor struct AuthLifecycleTests {
    private func settled(_ auth: AuthStore) async {
        for _ in 0..<1000 { if !auth.isEndingSession { return }; await Task.yield() }
        #expect(!auth.isEndingSession)
    }

    @Test func delayedBootstrapCannotRestoreSessionAfterLogout() async {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        let boot = Task { await auth.bootstrap() }
        while api.continuations.isEmpty { await Task.yield() }
        await auth.signOut()
        api.release(); await boot.value
        #expect(auth.session == nil && identity.session == nil)
        #expect(!auth.isBootstrapping && !auth.isLoading && auth.errorMessage == nil)
    }

    @Test func logoutDrainsProviderCallbackThenClearsSDKIdentity() async {
        let identity = LifecycleIdentityStub(); identity.session = nil; identity.delayLogin = true
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: nil))
        let login = Task { await auth.continueWithGoogle() }
        while identity.pending == nil { await Task.yield() }
        let logout = Task { await auth.signOut() }
        while !auth.isEndingSession { await Task.yield() }
        #expect(identity.signOutCalls == 0)
        await auth.continueWithGoogle() // Must not start a second provider operation during cleanup.
        identity.release()
        await login.value; await logout.value
        #expect(identity.signOutCalls == 1)
        #expect(auth.session == nil && identity.session == nil && !auth.isLoading)
        await auth.continueWithGoogle()
        #expect(auth.session?.userID == "audit-owner")
    }

    @Test func delayedBootstrapErrorCannotPolluteNewLogin() async {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        let boot = Task { await auth.bootstrap() }
        while api.continuations.isEmpty { await Task.yield() }
        await auth.signOut()
        api.hold = false
        await auth.continueWithGoogle()
        let current = auth.session
        api.continuations.removeFirst().resume(throwing: AuthError.sessionExpired)
        await boot.value
        #expect(current != nil && auth.session == current)
        #expect(auth.errorMessage == nil && auth.infoMessage == nil && !auth.bootstrapFailed)
    }

    @Test func bootstrapIsSingleFlight() async {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        let boot = Task { await auth.bootstrap() }
        while api.continuations.isEmpty { await Task.yield() }
        await auth.bootstrap()
        #expect(api.calls == 1)
        api.release(); await boot.value
        #expect(auth.session != nil && !auth.isBootstrapping)
    }

    @Test func bootstrapTerminalFailureReturnsToLoginWithoutRetryLoop() async {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        api.hold = false; api.failure = .sessionExpired
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        await auth.bootstrap(); await settled(auth)
        #expect(auth.session == nil && identity.session == nil && !auth.bootstrapFailed)
        #expect(auth.path == [.signIn] && auth.infoMessage == AuthError.sessionExpired.localizedDescription)
    }

    @Test func networkFailurePreservesIdentityAndAllowsBootstrapRetry() async {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        api.hold = false; api.failure = .networkUnavailable
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        await auth.bootstrap()
        #expect(auth.bootstrapFailed && identity.session != nil && !auth.isEndingSession)
        api.failure = nil; await auth.bootstrap()
        #expect(auth.session != nil && !auth.bootstrapFailed)
    }

    @Test func unexpectedSDKLogoutRemovesPublishedSession() async {
        let identity = LifecycleIdentityStub(), observer = IdentityObservationStub()
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: nil), identityObserver: observer)
        await auth.bootstrap()
        observer.changed?(identity.session?.userID)
        #expect(auth.session != nil)
        identity.session = nil; observer.changed?(nil)
        #expect(auth.session == nil && auth.path == [.signIn])
        await settled(auth)
        #expect(identity.signOutCalls == 1)
    }

    @Test func oldFailureCannotCloseNewSessionWithSameUID() async {
        let identity = LifecycleIdentityStub(), lifecycle = SessionLifecycle()
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: nil), lifecycle: lifecycle)
        await auth.bootstrap()
        let old = lifecycle.generation
        await auth.signOut(); await auth.continueWithGoogle()
        lifecycle.report(AuthError.sessionExpired, generation: old)
        #expect(auth.session != nil && !auth.isEndingSession)
        lifecycle.report(AuthError.sessionExpired, generation: lifecycle.generation)
        #expect(auth.session == nil && auth.isEndingSession)
        await settled(auth)
        #expect(identity.session == nil)
    }

    @Test func pendingDeletionPersistsAcrossRelaunchUntilAcknowledged() async throws {
        let suite = "lifecycle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        api.hold = false; api.deletionFailure = .deletionPending
        let repo = FirebaseAuthRepository(client: identity, accountAPI: api)
        let auth = AuthStore(repository: repo, defaults: defaults)
        await auth.bootstrap(); try await auth.deleteAccount()
        #expect(auth.session == nil && identity.session == nil && auth.deletionPending)
        #expect(auth.errorMessage == nil && !auth.isEndingSession)
        let relaunched = AuthStore(repository: repo, defaults: defaults)
        await relaunched.bootstrap()
        #expect(relaunched.deletionPending && !relaunched.isBootstrapping && relaunched.session == nil)
        relaunched.acknowledgePendingDeletion()
        #expect(!relaunched.deletionPending && relaunched.path == [.signIn])
        #expect(!AuthStore(repository: repo, defaults: defaults).deletionPending)
    }

    @Test func deletingResponseDuringBootstrapShowsPendingState() async throws {
        let suite = "lifecycle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        api.hold = false; api.failure = .deletionPending
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api), defaults: defaults)
        await auth.bootstrap(); await settled(auth)
        #expect(auth.deletionPending && auth.session == nil && !auth.bootstrapFailed)
        #expect(identity.session == nil && auth.errorMessage == nil)
    }

    @Test func rejectedDeletionKeepsAccountAndDoesNotClaimPending() async throws {
        let identity = LifecycleIdentityStub(), api = LifecycleAccountStub()
        api.hold = false; api.deletionFailure = .recentLoginRequired
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        await auth.bootstrap()
        await #expect(throws: AuthError.recentLoginRequired) { try await auth.deleteAccount() }
        #expect(auth.session != nil && identity.session != nil && !auth.deletionPending && !auth.isEndingSession)
    }
}
