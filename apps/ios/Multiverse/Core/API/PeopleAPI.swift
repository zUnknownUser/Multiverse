import Foundation

@MainActor
protocol PeopleAPI: Sendable {
    func searchPeople(query: String, after: String?) async throws -> PeoplePage
    func suggestedPeople() async throws -> PeoplePage
    func fetchPerson(id: String) async throws -> PersonEnvelope
    func setFollowing(id: String, following: Bool) async throws -> PersonEnvelope
}

struct PersonSummary: Codable, Identifiable, Sendable, Equatable {
    let userID: String
    let username: String
    let displayName: String
    let avatarColor: String
    var avatarID: String? = nil
    var avatarPhotoID: String? = nil
    let bio: String
    let logCount: Int
    let followerCount: Int
    let followingCount: Int
    var duelRounds: Int? = nil
    var id: String { userID }
    var user: User { User(id: userID, name: displayName, handle: "@" + username, avatarColor: avatarColor, bio: bio, followers: followerCount, badgeUniverse: "", avatarID: avatarID, avatarPhotoID: avatarPhotoID) }
    var isValid: Bool { !userID.isEmpty && !displayName.isEmpty && logCount >= 0 && followerCount >= 0 && followingCount >= 0 }
}

struct SocialState: Codable, Sendable, Equatable {
    let version: Int
    let followingIDs: [String]
    let followerCount: Int
    func validate(ownerID: String) throws {
        guard version >= 0, followerCount >= 0, Set(followingIDs).count == followingIDs.count,
              !followingIDs.contains(ownerID), followingIDs.allSatisfy({ !$0.isEmpty }) else { throw AuthError.apiUnavailable }
    }
}

struct PeoplePage: Codable, Sendable {
    let users: [PersonSummary]
    let nextCursor: String?
    let state: SocialState
    func validate(ownerID: String) throws {
        try state.validate(ownerID: ownerID)
        guard users.count <= 50, Set(users.map(\.id)).count == users.count,
              users.allSatisfy({ $0.id != ownerID && $0.isValid }),
              nextCursor == nil || (!users.isEmpty && nextCursor == users.last?.username) else { throw AuthError.apiUnavailable }
    }
}

struct PersonEnvelope: Codable, Sendable {
    let person: PersonSummary
    let state: SocialState
    func validate(ownerID: String, personID: String) throws {
        try state.validate(ownerID: ownerID)
        guard person.userID == personID, person.isValid else { throw AuthError.apiUnavailable }
    }
}

enum PeopleError: LocalizedError, Equatable {
    case unavailable, invalidSearch, followFailed, onboardingRequired
    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("Este perfil não está mais disponível. Atualize as sugestões para encontrar outros loristas.")
        case .invalidSearch: return L10n.text("Use até 80 caracteres para buscar um nome ou @usuário.")
        case .followFailed: return L10n.text("Não foi possível atualizar quem você segue. Tente novamente.")
        case .onboardingRequired: return L10n.text("Conclua a apresentação do app para encontrar e seguir loristas.")
        }
    }
}
