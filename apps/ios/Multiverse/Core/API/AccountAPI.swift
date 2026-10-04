@MainActor
protocol AccountAPI: Sendable {
    func fetchAccount() async throws -> AccountEnvelope
    func usernameAvailable(_ username: String) async throws -> Bool
    func saveProfile(name: String, username: String, avatarColor: String, bio: String, avatarID: String?) async throws -> RemoteProfile
    func suggestions() async throws -> FollowSuggestions
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState
    func deleteAccount() async throws
}


extension AccountAPI {
    func saveProfile(name: String, username: String, avatarColor: String, bio: String) async throws -> RemoteProfile {
        try await saveProfile(name: name, username: username, avatarColor: avatarColor, bio: bio, avatarID: nil)
    }
}
