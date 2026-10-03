import Foundation

struct CommunityFilter: Hashable, Sendable {
    var universe: String? = nil
    var item: String? = nil
    var search = ""
    var feed = "recent"
    var kind: String? = nil
    var club: String? = nil
    var schedule: String? = nil
    var segment: Int? = nil
}
struct PostImage: Codable, Identifiable, Equatable, Sendable { let id: String; let width: Int; let height: Int }
struct PostImageData: Decodable, Sendable { let id: String; let width: Int; let height: Int; let base64: String }
struct PostMention: Codable, Identifiable, Sendable { let id: String; let handle: String }
struct PostVotes: Codable, Sendable { let counts: [Int]; let mine: Int? }
struct PostEdit: Encodable, Sendable {
    let title: String; let text: String; let spoiler: Bool; let imageIDs: [String]; let version: Int; let mutationID: String
}
struct LiveClub: Codable, Identifiable, Sendable {
    let id: String; let owner: String; let universeID: String; let name: String; let description: String
    let version: Int; let createdAt: Date; let memberCount: Int; let joined: Bool
}
struct ClubSchedule: Codable, Identifiable, Sendable {
    let id: String; let itemID: String; let startsOn: String; let totalUnits: Int; let unitLabel: String; let myUnits: Int
}
struct LiveClubsPage: Decodable, Sendable { let clubs: [LiveClub]; let nextCursor: String? }
struct LiveClubDetail: Decodable, Sendable { let club: LiveClub; let schedule: [ClubSchedule] }
struct ClubMember: Decodable, Identifiable, Sendable {
    let id: String; let name: String; let handle: String; let avatarColor: String; let units: Int
    var user: User { .init(id: id, name: name, handle: handle, avatarColor: avatarColor, bio: "", followers: nil, badgeUniverse: "") }
}
struct ClubMembersPage: Decodable, Sendable { let members: [ClubMember]; let nextCursor: String? }
struct LiveRoom: Decodable, Identifiable, Sendable {
    let itemID: String; let universeID: String; let online: Int; let progress: Int
    var id: String { itemID }
}
struct LiveRoomsPage: Decodable, Sendable { let rooms: [LiveRoom]; let nextCursor: String? }
struct RoomChanges: Decodable, Sendable { let itemID: String; let online: Int; let progress: Int; let revision: String }
struct RoomVisit: Decodable, Sendable { let itemID: String; let online: Int; let progress: Int }
struct ClubInput: Encodable, Sendable { let name: String; let description: String; let universeID: String; let version: Int? }
struct ScheduleInput: Encodable, Sendable { let itemID: String; let startsOn: String; let totalUnits: Int; let unitLabel: String }

@MainActor protocol SpacesAPI: Sendable {
    func fetchClubs(query: String, universe: String?, after: String?) async throws -> LiveClubsPage
    func fetchClub(_ id: String) async throws -> LiveClubDetail
    func saveClub(id: String, input: ClubInput) async throws -> PostReceipt
    func joinClub(_ id: String, joined: Bool) async throws -> PostReceipt
    func deleteClub(_ id: String) async throws -> PostDeletion
    func reportClub(_ id: String, reason: String, block: Bool) async throws -> PostReceipt
    func saveSchedule(club: String, id: String, input: ScheduleInput) async throws -> PostReceipt
    func deleteSchedule(club: String, id: String) async throws -> PostDeletion
    func saveClubProgress(club: String, schedule: String, units: Int) async throws -> PostReceipt
    func fetchClubMembers(club: String, schedule: String?, after: String?) async throws -> ClubMembersPage
    func fetchRooms(query: String, universe: String?, after: String?) async throws -> LiveRoomsPage
    func visitRoom(_ item: String, progress: Int?) async throws -> RoomVisit
    func roomChanges(_ item: String, after: String?) async throws -> RoomChanges
}
extension CommunityAPI {
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage {
        guard filter.search.isEmpty, filter.feed == "recent", filter.kind == nil, filter.club == nil else { throw CommunityError.unavailable }
        return try await fetchPosts(universe: filter.universe, item: filter.item, after: after)
    }
    func editPost(_ id: String, input: PostEdit) async throws -> PostReceipt { throw CommunityError.unavailable }
    func uploadPostImage(post: String, id: String, data: Data) async throws -> PostImage { throw CommunityError.unavailable }
    func fetchPostImage(post: String, id: String) async throws -> PostImageData { throw CommunityError.unavailable }
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt {
        guard parent == nil else { throw CommunityError.unavailable }
        return try await postReply(post: post, id: id, text: text, spoiler: spoiler)
    }
    func votePost(_ id: String, choice: Int) async throws -> PostReceipt { throw CommunityError.unavailable }
    func resolveTheory(_ id: String, status: String, note: String, version: Int) async throws -> PostReceipt { throw CommunityError.unavailable }
    func mentionPeople(query: String) async throws -> [User] { throw CommunityError.unavailable }
}
extension AccountAPIClient: SpacesAPI {
    func fetchPosts(filter: CommunityFilter, after: String?) async throws -> CommunityPage {
        let entries: [(String, String?)] = [("universe", filter.universe), ("item", filter.item), ("q", filter.search), ("feed", filter.feed), ("kind", filter.kind), ("club", filter.club), ("schedule", filter.schedule), ("after", after), ("segment", filter.segment.map(String.init))]
        return try await request("posts", query: entries.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } })
    }
    func editPost(_ id: String, input: PostEdit) async throws -> PostReceipt { try await request("posts/" + id, method: "PATCH", body: JSONEncoder().encode(input)) }
    func uploadPostImage(post: String, id: String, data: Data) async throws -> PostImage {
        try await request("posts/\(post)/images/\(id)", method: "PUT", body: JSONSerialization.data(withJSONObject: ["base64": data.base64EncodedString()]))
    }
    func fetchPostImage(post: String, id: String) async throws -> PostImageData { try await request("posts/\(post)/images/\(id)") }
    func postReply(post: String, id: String, text: String, spoiler: Bool, parent: String?) async throws -> CommentReceipt {
        struct Input: Encodable { let text: String; let spoiler: Bool; let parentID: String? }
        return try await request("posts/\(post)/comments/\(id)", method: "PUT", body: JSONEncoder().encode(Input(text: text, spoiler: spoiler, parentID: parent)))
    }
    func votePost(_ id: String, choice: Int) async throws -> PostReceipt { try await request("posts/\(id)/vote", method: "PUT", body: JSONSerialization.data(withJSONObject: ["choice": choice])) }
    func resolveTheory(_ id: String, status: String, note: String, version: Int) async throws -> PostReceipt { try await request("posts/\(id)/resolution", method: "PUT", body: JSONSerialization.data(withJSONObject: ["status": status, "note": note, "version": version])) }
    func mentionPeople(query: String) async throws -> [User] { try await searchPeople(query: query, after: nil).users.map(\.user) }
    func fetchClubs(query: String, universe: String?, after: String?) async throws -> LiveClubsPage {
        try await request("community/clubs", query: [("q", Optional(query)), ("universe", universe), ("after", after)].compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } })
    }
    func fetchClub(_ id: String) async throws -> LiveClubDetail { try await request("community/clubs/" + id) }
    func saveClub(id: String, input: ClubInput) async throws -> PostReceipt { try await request("community/clubs/" + id, method: "PUT", body: JSONEncoder().encode(input)) }
    func joinClub(_ id: String, joined: Bool) async throws -> PostReceipt { try await request("community/clubs/\(id)/membership", method: "PUT", body: JSONSerialization.data(withJSONObject: ["joined": joined])) }
    func deleteClub(_ id: String) async throws -> PostDeletion { try await request("community/clubs/" + id, method: "DELETE") }
    func reportClub(_ id: String, reason: String, block: Bool) async throws -> PostReceipt { try await request("community/clubs/\(id)/report", method: "PUT", body: JSONSerialization.data(withJSONObject: ["reason": reason, "alsoBlock": block])) }
    func saveSchedule(club: String, id: String, input: ScheduleInput) async throws -> PostReceipt { try await request("community/clubs/\(club)/schedule/\(id)", method: "PUT", body: JSONEncoder().encode(input)) }
    func deleteSchedule(club: String, id: String) async throws -> PostDeletion { try await request("community/clubs/\(club)/schedule/\(id)", method: "DELETE") }
    func saveClubProgress(club: String, schedule: String, units: Int) async throws -> PostReceipt { try await request("community/clubs/\(club)/schedule/\(schedule)/progress", method: "PUT", body: JSONSerialization.data(withJSONObject: ["units": units])) }
    func fetchClubMembers(club: String, schedule: String?, after: String?) async throws -> ClubMembersPage {
        try await request("community/clubs/\(club)/members", query: [("schedule", schedule), ("after", after)].compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } })
    }
    func fetchRooms(query: String, universe: String?, after: String?) async throws -> LiveRoomsPage {
        try await request("community/rooms", query: [("q", Optional(query)), ("universe", universe), ("after", after)].compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } })
    }
    func roomChanges(_ item: String, after: String?) async throws -> RoomChanges {
        try await request("community/rooms/\(item)/changes", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [], timeout: 35)
    }
    func visitRoom(_ item: String, progress: Int?) async throws -> RoomVisit {
        try await request("community/rooms/\(item)/visit", method: "PUT", body: JSONSerialization.data(withJSONObject: progress.map { ["progress": $0] } ?? [:]))
    }
}
