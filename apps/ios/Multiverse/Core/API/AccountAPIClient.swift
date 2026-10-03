import Foundation

@MainActor
final class AccountAPIClient: AccountAPI, ActivityAPI, PeopleAPI, SocialAPI, CommunityAPI, NotificationsAPI, LibraryAPI {
    private let baseURL: URL?
    private let tokens: any APITokenProvider
    private let transport: URLSession
    private let expectedUserID: String?

    init(baseURL: URL? = AccountAPIClient.configuredURL(), tokens: any APITokenProvider = FirebaseAPITokenProvider(), transport: URLSession = .shared, expectedUserID: String? = nil) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.transport = transport
        self.expectedUserID = expectedUserID
    }
    static func configuredURL() -> URL? {
        var value = Bundle.main.object(forInfoDictionaryKey: "MultiverseAPIBaseURL") as? String ?? ""
        #if DEBUG
        value = ProcessInfo.processInfo.environment["MULTIVERSE_API_BASE_URL"] ?? value
        #endif
        guard let url = URL(string: value), url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        #if DEBUG
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host!)) else { return nil }
        #else
        guard url.scheme == "https" else { return nil }
        #endif
        return url
    }
    private struct Availability: Decodable { let available: Bool }
    private struct Deletion: Decodable { let deleted: Bool }
    private struct ProfileInput: Encodable { let displayName: String; let username: String; let avatarColor: String; let bio: String }
    private struct APIError: Decodable { let code: String? }

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
    func fetchActivity() async throws -> ActivitySnapshot { try await request("me/activity") }
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await request("me/diary/" + id.uuidString.lowercased(), method: "PUT", body: encoder.encode(input))
    }
    func usernameAvailable(_ username: String) async throws -> Bool {
        let response: Availability = try await request("me/username-availability", query: [URLQueryItem(name: "username", value: username)])
        return response.available
    }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String) async throws -> RemoteProfile {
        try await request("me/profile", method: "PUT", body: JSONEncoder().encode(ProfileInput(displayName: name, username: username, avatarColor: avatarColor, bio: bio)))
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
        guard let baseURL else { throw AuthError.apiNotConfigured }
        guard let uid = tokens.userID, expectedUserID == nil || uid == expectedUserID else { throw AuthError.sessionExpired }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        for attempt in 0...1 {
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + (try await tokens.token(forceRefresh: attempt == 1)), forHTTPHeaderField: "Authorization")
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            request.setValue(L10n.language(), forHTTPHeaderField: "Accept-Language")
            let data: Data
            let response: URLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                if (error as? URLError)?.code == .timedOut, path.hasPrefix("me/diary/") { throw ActivityError.timedOut }
                throw AuthError.networkUnavailable
            }
            try Task.checkCancellation()
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            guard let http = response as? HTTPURLResponse else { throw AuthError.apiUnavailable }
            if http.statusCode == 401 && attempt == 0 { continue }
            if (200..<300).contains(http.statusCode) {
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let value = try decoder.singleValueContainer().decode(String.self)
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = formatter.date(from: value) { return date }
                        formatter.formatOptions = [.withInternetDateTime]
                        guard let date = formatter.date(from: value) else { throw AuthError.apiUnavailable }
                        return date
                    }
                    return try decoder.decode(Response.self, from: data)
                }
                catch { throw AuthError.apiUnavailable }
            }
            let code = (try? JSONDecoder().decode(APIError.self, from: data))?.code
            switch code {
            case "MESSAGE_UNAVAILABLE": throw DirectMessageError.unavailable
            case "MESSAGE_REQUEST_PENDING": throw DirectMessageError.pending
            case "MESSAGE_CONFLICT": throw DirectMessageError.conflict
            case "MESSAGE_LIMIT": throw DirectMessageError.limit
            case "INVALID_MESSAGE": throw SocialError.invalid
            case "VOICE_UNAVAILABLE": throw VoiceError.unavailable
            case "VOICE_FULL": throw VoiceError.full
            case "VOICE_BLOCKED": throw VoiceError.blocked
            case "VOICE_SESSION_ENDED": throw VoiceError.ended
            case "VOICE_SESSION_CONFLICT": throw VoiceError.conflict

            case "LIBRARY_STALE": throw LibraryError.stale
            case "LIST_UNAVAILABLE": throw LibraryError.unavailable
            case "LIBRARY_MUTATION_CONFLICT", "LIBRARY_LIST_CONFLICT": throw LibraryError.conflict
            case "LIBRARY_LISTS_LIMIT": throw LibraryError.listLimit
            case "LIST_ITEMS_LIMIT": throw LibraryError.itemLimit
            case "LIBRARY_ITEMS_LIMIT": throw LibraryError.savedLimit
            case "INVALID_LIBRARY_REQUEST": throw SocialError.invalid

            case "COMMENTS_RESTRICTED": throw SocialError.commentsRestricted
            case "COMMENT_UNAVAILABLE": throw SocialError.commentUnavailable
            case "COMMENT_LIMIT": throw SocialError.commentLimit
            case "COMMENT_CONFLICT": throw SocialError.commentConflict
            case "REACTION_LIMIT": throw SocialError.reactionLimit
            case "POST_STALE": throw CommunityError.stale
            case "INVALID_IMAGE": throw CommunityError.invalidImage
            case "ROOM_PROGRESS_REQUIRED": throw CommunityError.roomProgress
            case "CLUB_FULL", "CLUB_LIMIT", "SCHEDULE_LIMIT", "IMAGE_LIMIT": throw CommunityError.capacity
            case "SCHEDULE_DATE_USED": throw CommunityError.scheduleDate
            case "MENTION_LIMIT": throw CommunityError.mentionLimit
            case "INVALID_DUEL": throw CommunityError.invalidDuel
            case "VOTE_CLOSED": throw CommunityError.closed
            case "CLUB_MEMBERSHIP_REQUIRED": throw CommunityError.membership
            case "CLUB_UNAVAILABLE": throw CommunityError.clubUnavailable
            case "CLUB_OWNER_CANNOT_LEAVE": throw CommunityError.ownerLeave
            case "POST_UNAVAILABLE": throw CommunityError.unavailable
            case "POST_CONFLICT": throw CommunityError.conflict
            case "INVALID_POST_CATALOG": throw CatalogError.changed
            case "REVIEW_UNAVAILABLE": throw SocialError.unavailable
            case "INVALID_SOCIAL_REQUEST", "INVALID_REPORT", "INVALID_BLOCK", "INVALID_FEED_CURSOR": throw SocialError.invalid
            case "REPORT_LIMIT": throw SocialError.reportLimit
            case "PUBLICATION_LIMIT": throw SocialError.publicationLimit
            case "PERSON_UNAVAILABLE": throw PeopleError.unavailable
            case "INVALID_PEOPLE_QUERY": throw PeopleError.invalidSearch
            case "INVALID_FOLLOW", "CANNOT_FOLLOW_SELF", "INVALID_PERSON": throw PeopleError.followFailed
            case "ONBOARDING_REQUIRED": throw PeopleError.onboardingRequired
            case "USERNAME_TAKEN": throw AuthError.usernameTaken
            case "CATALOG_CHANGED": throw CatalogError.changed
            case "INVALID_LOG": throw ActivityError.invalidLog
            case "INVALID_LOG_DATE": throw ActivityError.invalidDate
            case "ITEM_UNAVAILABLE": throw ActivityError.itemUnavailable
            case "EMAIL_NOT_VERIFIED": throw AuthError.emailNotVerified
            case "RECENT_LOGIN_REQUIRED": throw AuthError.recentLoginRequired
            case "STALE_ONBOARDING", "ONBOARDING_COMPLETED": throw AuthError.onboardingConflict
            case "FOLLOWS_REQUIRED", "INVALID_FOLLOWS": throw AuthError.suggestionsChanged
            case "DELETION_PENDING", "ACCOUNT_DELETING": throw AuthError.deletionPending
            default:
                if http.statusCode == 401 { throw AuthError.sessionExpired }
                if http.statusCode == 429 { throw AuthError.tooManyRequests }
                if path.hasPrefix("me/diary/") {
                    if http.statusCode == 413 { throw ActivityError.tooLong }
                    if http.statusCode == 400 { throw ActivityError.invalidLog }
                }
                if http.statusCode == 400 { throw AuthError.invalidProfile }
                throw AuthError.apiUnavailable
            }
        }
        throw AuthError.sessionExpired
    }
}
