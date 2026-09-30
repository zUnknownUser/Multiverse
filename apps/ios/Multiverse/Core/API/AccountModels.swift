import Foundation

struct RemoteProfile: Codable, Sendable, Equatable {
    let userID: String
    let username: String
    let displayName: String
    let avatarColor: String
    let bio: String
}

struct OnboardingState: Codable, Sendable, Equatable {
    var universeIDs: [String] = []
    var seenItemIDs: [String] = []
    var followedUserIDs: [String] = []
    var step = 1
    var completed = false
    var version = 0
}
struct AccountEnvelope: Codable, Sendable { let profile: RemoteProfile?; let onboarding: OnboardingState }
struct FollowSuggestions: Codable, Sendable { let users: [RemoteProfile]; let minimumFollows: Int }

