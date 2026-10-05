import Foundation

struct ProfileEditInput: Encodable, Sendable {
    let displayName: String
    let bio: String
    let avatarColor: String
    let avatarID: String?
    let photoAction: String
    let photo: String?
}
@MainActor protocol ProfileEditingAPI: Sendable {
    func editProfile(_ input: ProfileEditInput) async throws -> RemoteProfile
    func profilePhoto(_ id: String) async throws -> Data
}
extension AccountAPIClient: ProfileEditingAPI {
    func editProfile(_ input: ProfileEditInput) async throws -> RemoteProfile {
        try await request("me/profile/details", method: "PUT", body: JSONEncoder().encode(input))
    }
    func profilePhoto(_ id: String) async throws -> Data {
        struct Photo: Decodable { let id: String; let base64: String }
        guard UUID(uuidString: id) != nil else { throw CommunityError.invalidImage }
        let photo: Photo = try await request("people/photos/" + id)
        guard photo.id.lowercased() == id.lowercased(), let data = Data(base64Encoded: photo.base64), data.count <= 262144 else { throw CommunityError.invalidImage }
        return data
    }
}
