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
            captured.append(request)
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
    private func client(_ token: TokenStub) -> (AccountAPIClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountURLProtocol.self]
        let session = URLSession(configuration: config)
        return (AccountAPIClient(baseURL: URL(string: "https://api.example.test/api/v1")!, tokens: token, transport: session), session)
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
}
