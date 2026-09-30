import Foundation

@MainActor
final class AccountAPIClient: AccountAPI {
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

    func fetchAccount() async throws -> AccountEnvelope { try await request("me") }
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
    private func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Response {
        guard let baseURL else { throw AuthError.apiNotConfigured }
        guard let uid = tokens.userID, expectedUserID == nil || uid == expectedUserID else { throw AuthError.sessionExpired }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        for attempt in 0...1 {
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + (try await tokens.token(forceRefresh: attempt == 1)), forHTTPHeaderField: "Authorization")
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            request.setValue(L10n.language(), forHTTPHeaderField: "Accept-Language")
            let data: Data
            let response: URLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch { throw AuthError.networkUnavailable }
            guard tokens.userID == uid else { throw AuthError.sessionExpired }
            guard let http = response as? HTTPURLResponse else { throw AuthError.apiUnavailable }
            if http.statusCode == 401 && attempt == 0 { continue }
            if (200..<300).contains(http.statusCode) {
                do { return try JSONDecoder().decode(Response.self, from: data) }
                catch { throw AuthError.apiUnavailable }
            }
            let code = (try? JSONDecoder().decode(APIError.self, from: data))?.code
            switch code {
            case "USERNAME_TAKEN": throw AuthError.usernameTaken
            case "EMAIL_NOT_VERIFIED": throw AuthError.emailNotVerified
            case "RECENT_LOGIN_REQUIRED": throw AuthError.recentLoginRequired
            case "STALE_ONBOARDING", "ONBOARDING_COMPLETED": throw AuthError.onboardingConflict
            case "FOLLOWS_REQUIRED", "INVALID_FOLLOWS": throw AuthError.suggestionsChanged
            case "DELETION_PENDING", "ACCOUNT_DELETING": throw AuthError.deletionPending
            default:
                if http.statusCode == 401 { throw AuthError.sessionExpired }
                if http.statusCode == 400 { throw AuthError.invalidProfile }
                throw AuthError.apiUnavailable
            }
        }
        throw AuthError.sessionExpired
    }
}
