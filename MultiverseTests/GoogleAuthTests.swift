import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class GoogleClientStub: GoogleAuthenticationClient {
    var session: AuthSession?
    var error: AuthError?
    var calls = 0
    var delay = false
    let result = AuthSession(userID: "firebase-user", email: "test@example.com", handle: "", displayName: "Teste")

    func currentSession() -> AuthSession? { session }
    func signIn() async throws -> AuthSession {
        calls += 1
        if delay { try await Task.sleep(for: .milliseconds(100)) }
        if let error { throw error }
        session = result
        return result
    }
    func signOut() throws {
        if let error { throw error }
        session = nil
    }
    func deleteAccount() async throws {
        if let error { throw error }
        session = nil
    }
}

@MainActor
struct GoogleAuthTests {
    @Test func googleLoginUsesFirebaseIdentityAndRestoresSession() async {
        let client = GoogleClientStub()
        let repository = FirebaseAuthRepository(client: client)
        let store = AuthStore(repository: repository)
        await store.continueWithGoogle()
        #expect(store.session == client.result)
        #expect(!store.isLoading)
        let restored = AuthStore(repository: repository)
        await restored.bootstrap()
        #expect(restored.session == client.result)
        await store.signOut()
        #expect(store.session == nil)
        #expect(client.session == nil)
    }

    @Test func cancellationDoesNotDisplayErrorOrCreateSession() async {
        let client = GoogleClientStub()
        client.error = .cancelled
        let store = AuthStore(repository: FirebaseAuthRepository(client: client))
        await store.continueWithGoogle()
        #expect(store.session == nil)
        #expect(store.errorMessage == nil)
        #expect(!store.isLoading)
    }

    @Test func networkFailureAllowsRetry() async {
        let client = GoogleClientStub()
        client.error = .networkUnavailable
        let store = AuthStore(repository: FirebaseAuthRepository(client: client))
        await store.continueWithGoogle()
        #expect(store.session == nil)
        #expect(store.errorMessage != nil)
        client.error = nil
        await store.continueWithGoogle()
        #expect(store.session == client.result)
        #expect(store.errorMessage == nil)
    }

    @Test func duplicateTapsOnlyStartOneLogin() async {
        let client = GoogleClientStub()
        client.delay = true
        let store = AuthStore(repository: FirebaseAuthRepository(client: client))
        async let first: Void = store.continueWithGoogle()
        async let second: Void = store.continueWithGoogle()
        _ = await (first, second)
        #expect(client.calls == 1)
    }

    @Test func appleDoesNotCreateDemoSession() async {
        let client = GoogleClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(client: client))
        await store.continueWithApple()
        #expect(store.session == nil)
        #expect(store.errorMessage == AuthError.unavailable.localizedDescription)
        #expect(client.calls == 0)
    }

    @Test func failedSignOutKeepsSession() async {
        let client = GoogleClientStub()
        let store = AuthStore(repository: FirebaseAuthRepository(client: client))
        await store.continueWithGoogle()
        client.error = .networkUnavailable
        await store.signOut()
        #expect(store.session == client.result)
        #expect(store.errorMessage != nil)
    }

    @Test func realAccountDoesNotInheritDemoProfileOrDiary() async {
        let session = AuthSession(userID: "account-isolation-test", email: "test@example.com", handle: "", displayName: "Teste")
        let store = AppStore(session: session)
        await store.bootstrap()
        #expect(store.meID == session.userID)
        #expect(store.me.id == session.userID)
        #expect(store.user(store.meID)?.name == "Teste")
        #expect(store.diary.isEmpty)
        #expect(store.friendsCount == 0)
        #expect(store.conversations.isEmpty)
    }

    @Test func onboardingCompletionBelongsToOneAccount() {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(firstID)")
            UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(secondID)")
        }
        let first = AuthSession(userID: firstID, email: "first@example.com", handle: "")
        let second = AuthSession(userID: secondID, email: "second@example.com", handle: "")
        let firstStore = AppStore(session: first)
        firstStore.isOnboarded = true
        #expect(AppStore(session: first).isOnboarded)
        #expect(!AppStore(session: second).isOnboarded)
    }

    @Test func firebaseConfigurationMatchesCallbackAndAppBundle() throws {
        let url = try #require(Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"))
        let config = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(config["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier)
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(try #require(config["REVERSED_CLIENT_ID"] as? String)))
    }

    @Test func accountSettingsAreScopedToFirebaseUser() async throws {
        let suite = "google-auth-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = GoogleClientStub()
        client.session = client.result
        let repository = FirebaseAuthRepository(client: client, defaults: defaults)
        var settings = AccountSettings()
        settings.publicDiary = false
        await repository.updateAccountSettings(settings)
        client.session = AuthSession(userID: "another-user", email: "other@example.com", handle: "")
        #expect(await repository.fetchAccountSettings().publicDiary)
        client.session = client.result
        #expect(await repository.fetchAccountSettings().publicDiary == false)
    }
}
