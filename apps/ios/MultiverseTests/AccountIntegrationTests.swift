import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class AccountStub: AccountAPI {
    var profile: RemoteProfile?
    var progress = OnboardingState()
    var people: [RemoteProfile] = []
    var failure: AuthError?
    var suggestionFailure: AuthError?
    var suggestionCalls = 0
    var savedVersions: [Int] = []
    var peopleAfterNextSaveConflict: [RemoteProfile]?
    var available = true
    var suspendAvailability = false
    var availabilityRequests: [CheckedContinuation<Bool, Error>] = []
    init(uid: String) {
        profile = RemoteProfile(userID: uid, username: "real.name", displayName: "Real Name", avatarColor: "#F4A814", bio: "Real bio")
    }
    func fetchAccount() async throws -> AccountEnvelope {
        if let failure { throw failure }
        return AccountEnvelope(profile: profile, onboarding: progress)
    }
    func usernameAvailable(_ username: String) async throws -> Bool {
        if suspendAvailability {
            return try await withCheckedThrowingContinuation { availabilityRequests.append($0) }
        }
        if let failure { throw failure }
        return available
    }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String) async throws -> RemoteProfile {
        if let failure { throw failure }
        return profile!
    }
    func suggestions() async throws -> FollowSuggestions {
        suggestionCalls += 1
        if let suggestionFailure { throw suggestionFailure }
        return FollowSuggestions(users: people, minimumFollows: min(3, people.count))
    }
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState {
        if let failure { throw failure }
        if let changed = peopleAfterNextSaveConflict {
            people = changed
            peopleAfterNextSaveConflict = nil
            throw AuthError.suggestionsChanged
        }
        guard state.version == progress.version else { throw AuthError.onboardingConflict }
        savedVersions.append(state.version)
        progress = state
        progress.version += 1
        return progress
    }
    func deleteAccount() async throws { if let failure { throw failure } }
}

@MainActor
final class IdentityStub: GoogleAuthenticationClient {
    var session: AuthSession?
    init(uid: String) { session = AuthSession(userID: uid, email: "test@example.com", handle: "", displayName: "Google Name") }
    func currentSession() -> AuthSession? { session }
    func signIn() async throws -> AuthSession { session! }
    func signOut() throws { session = nil }
    func deleteAccount() async throws { session = nil }
}

@MainActor
struct AccountIntegrationTests {
    private func people(_ count: Int) -> [RemoteProfile] {
        (0..<count).map { RemoteProfile(userID: "person-\($0)", username: "person\($0)", displayName: "Person \($0)", avatarColor: "#F4A814", bio: "") }
    }

    @Test(arguments: [0, 1, 2, 3, 5]) func onboardingOnlyRequiresAvailablePeople(count: Int) async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.people = people(count)
        api.progress = OnboardingState(universeIDs: ["marvel"], step: 2)
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        #expect(store.onboardingStepCount == (count == 0 ? 2 : 3))
        #expect(store.minimumOnboardingFollows == min(3, count))
        store.advanceOnboarding()
        try await waitForTransition(store)
        if count == 0 { #expect(store.isOnboarded); return }
        #expect(store.onboardingPhase == .step3)
        #expect(!store.canAdvanceOnboarding)
        store.followAll(Array(api.people.prefix(min(3, count))).map(\.userID))
        #expect(store.canAdvanceOnboarding)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.isOnboarded)
        #expect(api.progress.followedUserIDs.count == min(3, count))
    }

    @Test func growingCommunityAddsFollowStepBeforeCompleting() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.progress = OnboardingState(universeIDs: ["marvel"], step: 2)
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        api.people = people(1)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(!store.isOnboarded)
        #expect(store.onboardingStepCount == 3)
        #expect(store.onboardingPhase == .step3)
        #expect(store.minimumOnboardingFollows == 1)
        store.toggleFollow("person-0", silent: true)
        api.people = people(3)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(!store.isOnboarded)
        #expect(!store.canAdvanceOnboarding)
        #expect(store.onboardingError == nil)
        #expect(store.minimumOnboardingFollows == 3)
        store.followAll(api.people.map(\.userID))
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.isOnboarded)
    }

    @Test func departingPeopleDoNotBlockOnboardingOrEraseOtherSelections() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.people = people(3)
        api.progress = OnboardingState(universeIDs: ["marvel"], seenItemIDs: ["m-civil"], followedUserIDs: api.people.map(\.userID), step: 3)
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        api.people = []
        // Pull to refresh also works while the CTA cannot advance.
        store.follows = []
        #expect(!store.canAdvanceOnboarding)
        await store.refreshOnboardingPeople()
        #expect(store.onboardingPhase == .step2)
        #expect(store.canAdvanceOnboarding)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.isOnboarded)
        #expect(api.progress.followedUserIDs.isEmpty)
        #expect(api.progress.universeIDs == ["marvel"])
        #expect(api.progress.seenItemIDs == ["m-civil"])
    }

    @Test func changedSuggestionsRecoverAsInformationAndNetworkFailureIsNotAnEmptyCommunity() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.people = people(1)
        api.progress = OnboardingState(universeIDs: ["marvel"], followedUserIDs: ["person-0"], step: 3)
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        api.suggestionFailure = .networkUnavailable
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(!store.isOnboarded)
        #expect(store.onboardingError == AuthError.networkUnavailable.localizedDescription)
        #expect(store.follows == ["person-0"])
        #expect(store.onboardingStepCount == 3)
        api.suggestionFailure = nil
        api.peopleAfterNextSaveConflict = []
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(!store.isOnboarded)
        #expect(store.onboardingError == nil)
        #expect(store.onboardingPhase == .step2)
        #expect(store.toast != nil)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.isOnboarded)
    }

    @Test func productionDiscoveryDoesNotOfferDemoProfilesOrEphemeralFollows() async {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.progress.completed = true
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        #expect(store.homeSuggestedPeople.isEmpty)
        #expect(store.searchResults(query: "", filter: .people).rows.isEmpty)
        #expect(store.searchResults(query: "Nina", filter: .all).rows.isEmpty)
    }

    @Test func invalidSuggestionCountsCannotCreateAnImpossibleStep() {
        #expect(throws: AuthError.apiUnavailable) { try FollowSuggestions(users: [], minimumFollows: 3).validate(for: "me") }
        #expect(throws: AuthError.apiUnavailable) { try FollowSuggestions(users: people(1) + people(1), minimumFollows: 2).validate(for: "me") }
        #expect(throws: AuthError.apiUnavailable) { try FollowSuggestions(users: people(1), minimumFollows: 1).validate(for: "person-0") }
    }
    @Test func productionAccountNeverPublishesDemoWidgetDataEvenAfterRecovery() async {
        let uid = UUID().uuidString
        let api = AccountStub(uid: uid)
        api.failure = .apiUnavailable
        let writer = WidgetSnapshotSpy()
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""),
                             accountAPI: api, widgetWriter: writer)
        await store.bootstrap()
        #expect(store.accountLoadError != nil)
        #expect(writer.snapshots.isEmpty)
        api.failure = nil
        await store.reloadAccount()
        #expect(store.accountLoadError == nil)
        #expect(writer.snapshots.isEmpty)
    }

    @Test(arguments: [false, true]) func suggestionsAreRequiredOnlyWhileOnboardingIsIncomplete(completed: Bool) async {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.progress.completed = completed
        api.suggestionFailure = .apiUnavailable
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        #expect(store.isOnboarded == completed)
        #expect((store.accountLoadError == nil) == completed)
        #expect(api.suggestionCalls == (completed ? 0 : 1))
        #expect(!store.isLoading)
    }

    @Test func olderUsernameReplyCannotOverwriteNewerResultForTheSameName() async throws {
        let api = AccountStub(uid: "username-user")
        api.suspendAvailability = true
        let auth = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "username-user"), accountAPI: api))
        auth.draft.username = "same.name"
        let first = Task { await auth.checkUsername() }
        try await waitForAvailability(api, count: 1)
        let second = Task { await auth.checkUsername() }
        try await waitForAvailability(api, count: 2)
        api.availabilityRequests[1].resume(returning: false)
        await second.value
        api.availabilityRequests[0].resume(returning: true)
        await first.value
        #expect(auth.usernameAvailable == false)
    }

    @Test func cancelledUsernameCheckDoesNotPresentAnErrorAfterLeavingTheScreen() async throws {
        let api = AccountStub(uid: "username-user")
        api.suspendAvailability = true
        let auth = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "username-user"), accountAPI: api))
        auth.draft.username = "same.name"
        let check = Task { await auth.checkUsername() }
        try await waitForAvailability(api, count: 1)
        check.cancel()
        api.availabilityRequests[0].resume(throwing: AuthError.networkUnavailable)
        await check.value
        #expect(auth.errorMessage == nil)
        #expect(auth.usernameAvailable == nil)
    }

    @Test func editingUsernameImmediatelyInvalidatesAvailability() async {
        let api = AccountStub(uid: "username-user")
        let auth = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "username-user"), accountAPI: api))
        auth.draft.username = "available.name"
        await auth.checkUsername()
        #expect(auth.usernameAvailable == true)
        auth.draft.username = "different.name"
        #expect(auth.usernameAvailable == nil)
    }

    private func waitForAvailability(_ api: AccountStub, count: Int) async throws {
        for _ in 0..<100 {
            if api.availabilityRequests.count == count { return }
            await Task.yield()
        }
        try #require(api.availabilityRequests.count == count)
    }

    @Test(arguments: [false, true]) func googleNewAccountRequiresServerProfileAndKeepsExistingScreens(restoringSession: Bool) async {
        let identity = IdentityStub(uid: "new-user")
        let api = AccountStub(uid: "new-user")
        api.profile = nil
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        if restoringSession { await auth.bootstrap() }
        else { await auth.continueWithGoogle() }
        #expect(auth.session?.needsProfile == true)
        #expect(auth.path == [.chooseUsername])
        #expect(auth.draft.name == "Google Name")
    }

    @Test func serverProfileRestoresInsteadOfProviderDisplayName() async throws {
        let identity = IdentityStub(uid: "existing-user")
        let api = AccountStub(uid: "existing-user")
        api.progress.completed = true
        let auth = AuthStore(repository: FirebaseAuthRepository(client: identity, accountAPI: api))
        await auth.bootstrap()
        let session = try #require(auth.session)
        #expect(session.displayName == "Real Name")
        #expect(session.handle == "@real.name")
        #expect(session.onboarding?.completed == true)
        #expect(!session.needsProfile)
    }

    @Test func serverFailureDoesNotEnterWithDemoProfileAndAllowsRetry() async {
        let api = AccountStub(uid: "offline-user")
        let auth = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "offline-user"), accountAPI: api))
        api.failure = .apiUnavailable
        await auth.bootstrap()
        #expect(auth.session == nil)
        #expect(auth.bootstrapFailed)
        api.failure = nil
        await auth.bootstrap()
        #expect(auth.session?.userID == "offline-user")
        #expect(!auth.bootstrapFailed)
        #expect(auth.errorMessage == nil)
    }

    @Test func usernameRaceReturnsToSelectionAndFailedDeletionPreservesSession() async throws {
        let api = AccountStub(uid: "profile-user")
        let auth = AuthStore(repository: FirebaseAuthRepository(client: IdentityStub(uid: "profile-user"), accountAPI: api))
        await auth.bootstrap()
        auth.draft.name = "Name"
        auth.path = [.chooseUsername, .avatarAndBio]
        api.failure = .usernameTaken
        await auth.finishSignUp()
        #expect(auth.path == [.chooseUsername])
        #expect(auth.usernameAvailable == false)
        api.failure = .apiUnavailable
        await #expect(throws: AuthError.apiUnavailable) { try await auth.deleteAccount() }
        #expect(auth.session?.userID == "profile-user")
    }

    @Test func restoresProgressOnAnotherDeviceAndReloadClearsRemovedSelections() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.progress = OnboardingState(universeIDs: ["wow"], seenItemIDs: ["w-wotlk"], step: 2, version: 7)
        UserDefaults.standard.set(true, forKey: "mv-onboarded-\(uid)")
        let session = AuthSession(userID: uid, email: "test@example.com", handle: "")
        let store = AppStore(session: session, accountAPI: api)
        await store.bootstrap()
        #expect(!store.isOnboarded)
        #expect(store.onboardingPhase == .step2)
        #expect(store.onboardingUniverses == ["wow"])
        #expect(store.isSeen("w-wotlk"))
        #expect(store.user(uid)?.name == "Real Name")
        #expect(store.onboardingPeopleSorted().isEmpty)
        api.progress.seenItemIDs = []
        await store.reloadAccount()
        #expect(!store.isSeen("w-wotlk"))
    }

    @Test func zeroPeopleSkipsFollowStepAndOnlyCompletesAfterSuccessfulSave() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.progress = OnboardingState(universeIDs: ["wow"], step: 2)
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        #expect(store.minimumOnboardingFollows == 0)
        api.failure = .networkUnavailable
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(!store.isOnboarded)
        #expect(store.onboardingPhase == .step2)
        #expect(store.onboardingError != nil)
        api.failure = nil
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.isOnboarded)
        #expect(api.progress.completed)
        #expect(api.progress.followedUserIDs.isEmpty)
    }

    @Test func partialCommunityUsesRealPeopleAndSerializesProgressVersions() async throws {
        let uid = UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: "mv-onboarded-\(uid)") }
        let api = AccountStub(uid: uid)
        api.people = [RemoteProfile(userID: "real-person", username: "lorista", displayName: "Lorista", avatarColor: "#F4A814", bio: "Real person")]
        api.progress = OnboardingState(universeIDs: ["wow"])
        let store = AppStore(session: AuthSession(userID: uid, email: "test@example.com", handle: ""), accountAPI: api)
        await store.bootstrap()
        #expect(store.minimumOnboardingFollows == 1)
        #expect(store.onboardingPeopleSorted().map(\.id) == ["real-person"])
        store.advanceOnboarding()
        try await waitForTransition(store)
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(store.onboardingPhase == .step3)
        store.toggleFollow("real-person")
        store.advanceOnboarding()
        try await waitForTransition(store)
        #expect(api.savedVersions == [0, 1, 2])
        #expect(api.progress.followedUserIDs == ["real-person"])
        #expect(store.isOnboarded)
    }

    private func waitForTransition(_ store: AppStore) async throws {
        for _ in 0..<100 {
            if !store.onboardingTransitioning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Onboarding transition did not finish")
    }
}
