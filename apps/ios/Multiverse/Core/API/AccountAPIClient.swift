import Foundation

@MainActor
final class AccountAPIClient: AccountAPI, ActivityAPI, PeopleAPI, SocialAPI, CommunityAPI, NotificationsAPI, LibraryAPI {
    private let http: any AuthenticatedRequesting

    init(baseURL: URL? = AccountAPIClient.configuredURL(), tokens: any APITokenProvider = FirebaseAPITokenProvider(), transport: URLSession = .shared, expectedUserID: String? = nil, lifecycle: SessionLifecycle? = nil) {
        self.http = AuthenticatedHTTPClient(baseURL: baseURL, tokens: tokens, transport: transport, expectedUserID: expectedUserID, lifecycle: lifecycle)
    }
    init(http: any AuthenticatedRequesting) { self.http = http }
    static func configuredURL() -> URL? {
        var value = Bundle.main.object(forInfoDictionaryKey: "MultiverseAPIBaseURL") as? String ?? ""
        #if DEBUG
        value = ProcessInfo.processInfo.environment["MULTIVERSE_API_BASE_URL"] ?? value
        #endif
        return AppEnvironment.current.apiURL(value)
    }
    private struct Availability: Decodable { let available: Bool }
    private struct Deletion: Decodable { let deleted: Bool }
    private struct ProfileInput: Encodable { let displayName: String; let username: String; let avatarColor: String; let bio: String; let avatarID: String?
        enum CodingKeys: String, CodingKey { case displayName, username, avatarColor, bio, avatarID }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(displayName, forKey: .displayName); try c.encode(username, forKey: .username)
            try c.encode(avatarColor, forKey: .avatarColor); try c.encode(bio, forKey: .bio)
            try c.encode(avatarID, forKey: .avatarID)
        }
    }

    func fetchFeed(after: String?) async throws -> SocialPage {
        try await request("feed", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }
    func fetchReview(id: String) async throws -> SocialPage { try await request("reviews/" + id) }
    func fetchComments(reviewID: String, after: String?) async throws -> CommentsPage {
        try await request("reviews/" + reviewID + "/comments", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }
    func postComment(reviewID: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt {
        struct Input: Encodable { let text: String; let spoiler: Bool }
        return try await request("reviews/" + reviewID + "/comments/" + id, method: "PUT", body: JSONEncoder().encode(Input(text: text, spoiler: spoiler)))
    }
    func setReaction(reviewID: String, commentID: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary {
        struct Input: Encodable {
            let reaction: String?; let liked: Bool
            enum CodingKeys: String, CodingKey { case reaction, liked }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(reaction, forKey: .reaction)
                try container.encode(liked, forKey: .liked)
            }
        }
        return try await request("reviews/" + reviewID + (commentID.map { "/comments/" + $0 } ?? "") + "/reaction", method: "PUT", body: JSONEncoder().encode(Input(reaction: reaction, liked: liked)))
    }
    func saveCommentPermission(_ permission: String) async throws -> DiaryPrivacy {
        struct Input: Encodable { let commentPermission: String }
        return try await request("me/comment-permission", method: "PUT", body: JSONEncoder().encode(Input(commentPermission: permission)))
    }
    func reportComment(reviewID: String, id: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt {
        struct Input: Encodable { let reason: String; let alsoBlock: Bool }
        return try await request("reviews/" + reviewID + "/comments/" + id + "/report", method: "PUT", body: JSONEncoder().encode(Input(reason: reason, alsoBlock: alsoBlock)))
    }
    func fetchPrivacy() async throws -> DiaryPrivacy { try await request("me/privacy") }
    func savePrivacy(publicDiary: Bool) async throws -> DiaryPrivacy {
        try await request("me/privacy", method: "PUT", body: JSONEncoder().encode(DiaryPrivacy(publicDiary: publicDiary)))
    }
    func fetchBlocks() async throws -> SocialBlocks { try await request("me/blocks") }
    func setBlock(id: String, blocked: Bool) async throws -> BlockReceipt {
        struct Input: Encodable { let blocked: Bool }
        return try await request("me/blocks/" + id, method: "PUT", body: JSONEncoder().encode(Input(blocked: blocked)))
    }
    func reportReview(id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt {
        struct Input: Encodable { let reason: String; let alsoBlock: Bool }
        return try await request("reviews/" + id + "/report", method: "PUT", body: JSONEncoder().encode(Input(reason: reason, alsoBlock: alsoBlock)))
    }
    func fetchAccount() async throws -> AccountEnvelope { try await request("me") }
    func fetchActivity() async throws -> ActivitySnapshot { try await fetchActivityPage(query: DiaryQuery(), after: nil) }
    func exportActivity() async throws -> ActivitySnapshot { try await request("me/activity") }
    func fetchActivityPage(query: DiaryQuery, after: String?) async throws -> ActivitySnapshot {
        var parameters = activityParameters
        parameters.append(URLQueryItem(name: "search", value: query.text))
        let selection: String = switch query.selection { case .all: "all"; case .liked: "liked"; case .rated: "rated"; case .rewatched: "rewatched" }
        parameters.append(URLQueryItem(name: "selection", value: selection))
        if let year = query.year { parameters.append(URLQueryItem(name: "year", value: String(year))) }
        if let after { parameters.append(URLQueryItem(name: "after", value: after)) }
        return try await request("me/activity", query: parameters)
    }
    func fetchReviews(itemID: String?, universeID: String?) async throws -> ActivitySnapshot {
        var parameters = [URLQueryItem(name: "limit", value: "5"), URLQueryItem(name: "selection", value: "reviewed")]
        if let itemID { parameters.append(URLQueryItem(name: "itemId", value: itemID)) }
        if let universeID { parameters.append(URLQueryItem(name: "universeId", value: universeID)) }
        return try await request("me/activity", query: parameters)
    }
    private var activityParameters: [URLQueryItem] {
        [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "timeZone", value: TimeZone.current.identifier)]
    }
    func searchPeople(query: String, after: String?) async throws -> PeoplePage {
        var parameters = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20")]
        if let after { parameters.append(URLQueryItem(name: "after", value: after)) }
        return try await request("people", query: parameters)
    }
    func suggestedPeople() async throws -> PeoplePage { try await request("people/suggestions") }
    func fetchPerson(id: String) async throws -> PersonEnvelope { try await request("people/" + id) }
    func setFollowing(id: String, following: Bool) async throws -> PersonEnvelope {
        struct Input: Encodable { let following: Bool }
        return try await request("me/follows/" + id, method: "PUT", body: JSONEncoder().encode(Input(following: following)))
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot {
        try await writeLog(id: id, input: input, method: "PUT")
    }
    func updateLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot {
        try await writeLog(id: id, input: input, method: "PATCH")
    }
    private func writeLog(id: UUID, input: SaveLogInput, method: String) async throws -> ActivitySnapshot {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await request("me/diary/" + id.uuidString.lowercased(), method: method, body: encoder.encode(input), query: activityParameters)
    }
    func deleteLog(id: UUID) async throws -> DeleteLogReceipt {
        try await request("me/diary/" + id.uuidString.lowercased(), method: "DELETE", query: activityParameters)
    }
    func usernameAvailable(_ username: String) async throws -> Bool {
        let response: Availability = try await request("me/username-availability", query: [URLQueryItem(name: "username", value: username)])
        return response.available
    }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String, avatarID: String? = nil) async throws -> RemoteProfile {
        try await request("me/profile", method: "PUT", body: JSONEncoder().encode(ProfileInput(displayName: name, username: username, avatarColor: avatarColor, bio: bio, avatarID: avatarID)))
    }
    func suggestions() async throws -> FollowSuggestions { try await request("me/onboarding/suggestions") }
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState {
        try await request("me/onboarding", method: "PUT", body: JSONEncoder().encode(state))
    }
    func deleteAccount() async throws {
        let result: Deletion = try await request("me", method: "DELETE")
        guard result.deleted else { throw AuthError.deletionPending }
    }
    func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = [], timeout: TimeInterval = 20) async throws -> Response {
        try await http.request(path, method: method, body: body, query: query, timeout: timeout)
    }
}
