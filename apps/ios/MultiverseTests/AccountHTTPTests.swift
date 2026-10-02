import Foundation
import Testing
@testable import Multiverse

private final class HTTPResponses: @unchecked Sendable {
    let lock = NSLock()
    private var responses: [(Int, String)] = []
    private var captured: [URLRequest] = []
    func reset(_ values: [(Int, String)]) { lock.withLock { responses = values; captured = [] } }
    func next(_ request: URLRequest) -> (Int, String) {
        lock.withLock {
            var copy = request
            if copy.httpBody == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                copy.httpBody = data
            }
            captured.append(copy)
            return responses.isEmpty ? (500, "{}") : responses.removeFirst()
        }
    }
    var requests: [URLRequest] { lock.withLock { captured } }
}

private final class AccountURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = HTTPResponses()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, json) = Self.fixture.next(request)
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class TokenStub: APITokenProvider {
    var userID: String? = "owner"
    var refreshes: [Bool] = []
    var switchAccount = false
    func token(forceRefresh: Bool) async throws -> String {
        refreshes.append(forceRefresh)
        if switchAccount { userID = "other-account" }
        return forceRefresh ? "refreshed-token" : "original-token"
    }
}

@Suite(.serialized)
@MainActor
struct AccountHTTPTests {
    @Test func communityPublicationEncodesOptionalItemAndUsesIdempotentRoute() async throws {
        let id = UUID().uuidString.lowercased()
        AccountURLProtocol.fixture.reset([(200, "{\"id\":\"\(id)\",\"saved\":true}")])
        let (api, transport) = client(TokenStub()); defer { transport.invalidateAndCancel() }
        let result = try await api.publishPost(id: id, input: .init(universeID: "wow", itemID: nil, title: "Title", text: "Body", spoiler: true))
        #expect(result.saved && result.id == id)
        let request = try #require(AccountURLProtocol.fixture.requests.first)
        #expect(request.url?.path == "/api/v1/posts/\(id)" && request.httpMethod == "PUT")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["itemID"] is NSNull && body["spoiler"] as? Bool == true)
    }
    @Test func notificationReadsSendOnlyExplicitIDsAndCannotUseAnotherAccount() async throws {
        let id = UUID().uuidString.lowercased(), tokens = TokenStub()
        AccountURLProtocol.fixture.reset([(200, "{\"saved\":true}")])
        let (api, transport) = client(tokens); defer { transport.invalidateAndCancel() }
        #expect(try await api.readNotifications([id]).saved)
        let request = try #require(AccountURLProtocol.fixture.requests.first)
        #expect(request.url?.path == "/api/v1/me/notifications/read")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["ids"] as? [String] == [id])
        tokens.switchAccount = true
        await #expect(throws: AuthError.sessionExpired) { try await api.fetchNotifications(after: nil) }
        #expect(AccountURLProtocol.fixture.requests.count == 1)
    }
    @Test func reactionRemovalSendsExplicitNullAndCommentErrorsPreserveTheirMeaning() async throws {
        let reviewID = UUID().uuidString.lowercased(), commentID = UUID().uuidString.lowercased()
        let json = """
        {"id":"\(commentID)","likes":0,"liked":false,"myReaction":null,"reactions":{"POW!":0,"ZAP!":0,"KRAK!":0,"HEH":0}}
        """
        AccountURLProtocol.fixture.reset([(200, json), (403, "{\"code\":\"COMMENTS_RESTRICTED\"}"), (429, "{\"code\":\"COMMENT_LIMIT\"}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        let result = try await api.setReaction(reviewID: reviewID, commentID: commentID, reaction: nil, liked: false)
        #expect(result.id == commentID && result.myReaction == nil)
        let request = try #require(AccountURLProtocol.fixture.requests.first)
        #expect(request.url?.path == "/api/v1/reviews/\(reviewID)/comments/\(commentID)/reaction")
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        #expect(body["reaction"] is NSNull)
        #expect(body["liked"] as? Bool == false)
        await #expect(throws: SocialError.commentsRestricted) { try await api.postComment(reviewID: reviewID, id: commentID, text: "Draft", spoiler: false) }
        await #expect(throws: SocialError.commentLimit) { try await api.postComment(reviewID: reviewID, id: commentID, text: "Draft", spoiler: false) }
        #expect(AccountURLProtocol.fixture.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer original-token" })
    }
    @Test func socialRoutesUseAuthenticatedRequestsAndMapVisibilityFailures() async throws {
        AccountURLProtocol.fixture.reset([(200, "{\"publicDiary\":false}"), (200, "{\"publicDiary\":true}"), (404, "{\"code\":\"REVIEW_UNAVAILABLE\"}"), (429, "{\"code\":\"REPORT_LIMIT\"}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        #expect(try await api.fetchPrivacy().publicDiary == false)
        #expect(try await api.savePrivacy(publicDiary: true).publicDiary)
        let id = UUID().uuidString.lowercased()
        await #expect(throws: SocialError.unavailable) { try await api.fetchReview(id: id) }
        await #expect(throws: SocialError.reportLimit) { try await api.reportReview(id: id, reason: "spam", alsoBlock: true) }
        let requests = AccountURLProtocol.fixture.requests
        #expect(requests.map(\.httpMethod) == ["GET", "PUT", "GET", "PUT"])
        #expect(requests.last?.url?.path == "/api/v1/reviews/\(id)/report")
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer original-token" })
    }
    @Test func peopleSearchEncodesHandleAndCursorWithoutLosingAuthentication() async throws {
        AccountURLProtocol.fixture.reset([(200, "{\"users\":[],\"nextCursor\":null,\"state\":{\"version\":0,\"followingIDs\":[],\"followerCount\":0}}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        let page = try await api.searchPeople(query: "@Álice & Bob", after: "alice")
        #expect(page.users.isEmpty)
        let request = try #require(AccountURLProtocol.fixture.requests.first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/v1/people")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "@Álice & Bob")
        #expect(components.queryItems?.first { $0.name == "after" }?.value == "alice")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer original-token")
    }

    @Test func followRefreshesTokenOnceAndTranslatesUnavailableProfile() async throws {
        let person = PersonSummary(userID: "alice", username: "alice", displayName: "Alice", avatarColor: "#F4A814", bio: "", logCount: 0, followerCount: 1, followingCount: 0)
        let payload = PersonEnvelope(person: person, state: SocialState(version: 1, followingIDs: ["alice"], followerCount: 0))
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        AccountURLProtocol.fixture.reset([(401, "{}"), (200, json)])
        let token = TokenStub()
        let (api, transport) = client(token)
        defer { transport.invalidateAndCancel() }
        let result = try await api.setFollowing(id: "alice", following: true)
        #expect(result.state.followingIDs == ["alice"])
        #expect(token.refreshes == [false, true])
        #expect(AccountURLProtocol.fixture.requests.allSatisfy { $0.httpMethod == "PUT" && $0.url?.path == "/api/v1/me/follows/alice" })
        AccountURLProtocol.fixture.reset([(404, "{\"code\":\"PERSON_UNAVAILABLE\"}")])
        await #expect(throws: PeopleError.unavailable) { try await api.fetchPerson(id: "alice") }
        #expect(AccountURLProtocol.fixture.requests.count == 1)
    }

    @Test func followCannotWriteForAnAccountThatHasSignedOut() async {
        AccountURLProtocol.fixture.reset([])
        let api = AccountAPIClient(baseURL: URL(string: "https://api.example.test/api/v1"), tokens: TokenStub(), expectedUserID: "previous-owner")
        await #expect(throws: AuthError.sessionExpired) { try await api.setFollowing(id: "alice", following: true) }
        #expect(AccountURLProtocol.fixture.requests.isEmpty)
    }

    private func client(_ token: TokenStub) -> (AccountAPIClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountURLProtocol.self]
        let session = URLSession(configuration: config)
        return (AccountAPIClient(baseURL: URL(string: "https://api.example.test/api/v1")!, tokens: token, transport: session), session)
    }

    @Test func diaryRequestUsesStableIDAndDecodesPostgresTimestamp() async throws {
        let id = UUID()
        let json = """
        {"entries":[{"id":"\(id.uuidString)","itemId":"m-civilwar","loggedAt":"2026-09-30T12:00:00.123Z","rating":4.5,"liked":true,"rewatch":false}],"reviews":[],"items":[],"universes":[],"followerCount":0}
        """
        AccountURLProtocol.fixture.reset([(200, json), (409, "{\"code\":\"ITEM_UNAVAILABLE\"}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        let input = SaveLogInput(itemId: "m-civilwar", loggedAt: .now, rating: 4.5, liked: true, rewatch: false, spoiler: true, text: "Review")
        let result = try await api.saveLog(id: id, input: input)
        #expect(result.entries.first?.id == id)
        #expect(result.entries.first?.rating == 4.5)
        let request = try #require(AccountURLProtocol.fixture.requests.first)
        #expect(request.url?.path.lowercased() == "/api/v1/me/diary/\(id.uuidString.lowercased())")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer original-token")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == L10n.language())
        await #expect(throws: ActivityError.itemUnavailable) { try await api.saveLog(id: id, input: input) }
    }

    @Test func expiredTokenRefreshesOnceAndPreservesAuthenticatedRequest() async throws {
        AccountURLProtocol.fixture.reset([(401, "{}"), (200, "{\"available\":true}")])
        let token = TokenStub()
        let (api, transport) = client(token)
        defer { transport.invalidateAndCancel() }
        #expect(try await api.usernameAvailable("real.name"))
        #expect(token.refreshes == [false, true])
        let requests = AccountURLProtocol.fixture.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/api/v1/me/username-availability")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer original-token")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
        #expect(requests.last?.value(forHTTPHeaderField: "Accept-Language") == L10n.language())
    }

    @Test func rejectedRefreshEndsSessionWithoutInfiniteRetries() async {
        AccountURLProtocol.fixture.reset([(401, "{}"), (401, "{}")])
        let token = TokenStub()
        let (api, transport) = client(token)
        defer { transport.invalidateAndCancel() }
        await #expect(throws: AuthError.sessionExpired) { try await api.fetchAccount() }
        #expect(AccountURLProtocol.fixture.requests.count == 2)
    }

    @Test func usernameConflictIsTranslatedToDomainError() async {
        AccountURLProtocol.fixture.reset([(409, "{\"code\":\"USERNAME_TAKEN\"}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        await #expect(throws: AuthError.usernameTaken) {
            try await api.saveProfile(name: "Real Name", username: "real.name", avatarColor: "#F4A814", bio: "")
        }
        #expect(AccountURLProtocol.fixture.requests.first?.httpMethod == "PUT")
    }

    @Test func removedCatalogSelectionRequestsARefresh() async {
        AccountURLProtocol.fixture.reset([(409, "{\"code\":\"CATALOG_CHANGED\"}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        await #expect(throws: CatalogError.changed) { try await api.saveOnboarding(OnboardingState()) }
    }

    @Test(arguments: [false, true]) func deletionRequiresPositiveServerConfirmation(deleted: Bool) async throws {
        AccountURLProtocol.fixture.reset([(200, "{\"deleted\":\(deleted)}")])
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        if deleted {
            try await api.deleteAccount()
        } else {
            await #expect(throws: AuthError.deletionPending) { try await api.deleteAccount() }
        }
        #expect(AccountURLProtocol.fixture.requests.first?.httpMethod == "DELETE")
    }

    @Test func queuedWriteForPreviousAccountCannotRunAfterSignInWithAnotherAccount() async {
        AccountURLProtocol.fixture.reset([])
        let api = AccountAPIClient(baseURL: URL(string: "https://api.example.test/api/v1"), tokens: TokenStub(), expectedUserID: "previous-owner")
        await #expect(throws: AuthError.sessionExpired) { try await api.saveOnboarding(OnboardingState()) }
        #expect(AccountURLProtocol.fixture.requests.isEmpty)
    }

    @Test func accountSwitchWhileLoadingTokenCannotWriteIntoAnotherAccount() async {
        AccountURLProtocol.fixture.reset([])
        let token = TokenStub()
        token.switchAccount = true
        let (api, transport) = client(token)
        defer { transport.invalidateAndCancel() }
        await #expect(throws: AuthError.sessionExpired) { try await api.saveOnboarding(OnboardingState()) }
        #expect(AccountURLProtocol.fixture.requests.isEmpty)
    }

    @Test func diaryFailuresHaveRelevantMessagesAndNeverAutomaticallyRepeatWrites() async {
        let input = SaveLogInput(itemId: "m-civilwar", loggedAt: .now, rating: 4, liked: false, rewatch: false, spoiler: false, text: "Review")
        let (api, transport) = client(TokenStub())
        defer { transport.invalidateAndCancel() }
        for (status, expected) in [(400, ActivityError.invalidLog), (413, .tooLong), (-1001, .timedOut)] {
            AccountURLProtocol.fixture.reset([(status, "{}")])
            await #expect(throws: expected) { try await api.saveLog(id: UUID(), input: input) }
            #expect(AccountURLProtocol.fixture.requests.count == 1)
        }
        AccountURLProtocol.fixture.reset([(429, "{}")])
        await #expect(throws: AuthError.tooManyRequests) { try await api.saveLog(id: UUID(), input: input) }
        AccountURLProtocol.fixture.reset([(-1009, "{}")])
        await #expect(throws: AuthError.networkUnavailable) { try await api.saveLog(id: UUID(), input: input) }
        AccountURLProtocol.fixture.reset([(-999, "{}")])
        await #expect(throws: CancellationError.self) { try await api.fetchActivity() }
    }
}
