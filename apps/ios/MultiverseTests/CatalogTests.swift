import Foundation
import Testing
@testable import Multiverse

@MainActor
private final class CatalogStub: CatalogAPI {
    var failure: CatalogError?
    var snapshot: CatalogSnapshot
    init(_ snapshot: CatalogSnapshot) { self.snapshot = snapshot }
    func fetchCatalog() async throws -> CatalogSnapshot {
        if let failure { throw failure }
        return snapshot
    }
}

private final class CatalogHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var captured: URLRequest?
    private var error: URLError?
    func reset(status: Int = 200, data: Data = Data(), error: URLError? = nil) { lock.withLock { self.status = status; self.data = data; self.error = error; captured = nil } }
    func response(for request: URLRequest) -> (Int, Data, URLError?) {
        lock.withLock { captured = request; return (status, data, error) }
    }
    var request: URLRequest? { lock.withLock { captured } }
}

private final class CatalogURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = CatalogHTTPFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, error) = Self.fixture.response(for: request)
        if let error { client?.urlProtocol(self, didFailWithError: error); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct CatalogTests {
    private func snapshot() -> CatalogSnapshot {
        let sample = SampleData.load()
        return CatalogSnapshot(version: 1, locale: "pt-BR", universes: [sample.universes[0]],
                               comingSoon: [UpcomingUniverse(id: "upcoming", name: "Upcoming")],
                               items: sample.items.filter { $0.uni == sample.universes[0].id })
    }

    @Test func realCatalogReplacesFixturesAcrossStoreWithoutRequiringThreeUniverses() async {
        let snapshot = snapshot()
        let store = AppStore(catalogAPI: CatalogStub(snapshot))
        await store.bootstrap()
        #expect(store.catalogLoadError == nil)
        #expect(store.universes.map(\.id) == snapshot.universes.map(\.id))
        #expect(store.items == snapshot.items)
        #expect(store.item("w-wotlk") == nil)
        #expect(store.comingSoonUniverses.map(\.name) == ["Upcoming"])
        #expect(store.profileData(for: store.meID).progress.count == 1)
        #expect(store.wrappedData().universe.id == snapshot.universes[0].id)
        #expect(store.onboardingConsumablePicks().allSatisfy { $0.uni == snapshot.universes[0].id })
    }

    @Test func failedCatalogDoesNotFallBackToDemoAndCanBeRetried() async {
        let api = CatalogStub(snapshot())
        api.failure = .unavailable
        let writer = WidgetSnapshotSpy()
        let store = AppStore(widgetWriter: writer, catalogAPI: api)
        await store.bootstrap()
        #expect(store.catalogLoadError != nil)
        #expect(store.items.isEmpty)
        #expect(store.universes.isEmpty)
        #expect(writer.snapshots.isEmpty)
        api.failure = nil
        await store.reloadAccount()
        #expect(store.catalogLoadError == nil)
        #expect(!store.isLoading)
        #expect(!store.items.isEmpty)
    }

    @Test func invalidSnapshotsCannotCrashLookupDictionaries() throws {
        let valid = snapshot()
        #expect(throws: CatalogError.unavailable) {
            try CatalogSnapshot(version: 1, locale: "pt-BR", universes: valid.universes + valid.universes, comingSoon: [], items: valid.items).validate()
        }
        #expect(throws: CatalogError.unavailable) {
            try CatalogSnapshot(version: 1, locale: "pt-BR", universes: valid.universes, comingSoon: [], items: SampleData.load().items).validate()
        }
        #expect(throws: CatalogError.empty) {
            try CatalogSnapshot(version: 1, locale: "pt-BR", universes: [], comingSoon: [], items: []).validate()
        }
        try CatalogSnapshot(version: 1, locale: "pt-BR", universes: valid.universes, comingSoon: [], items: []).validate()
    }

    @Test func emptyCatalogIsAnInformationalStateAndDoesNotShowDemoContent() async {
        let api = CatalogStub(CatalogSnapshot(version: 1, locale: "pt-BR", universes: [], comingSoon: [], items: []))
        let store = AppStore(catalogAPI: api)
        await store.bootstrap()
        #expect(store.catalogIssue == .empty)
        #expect(!store.isLoading)
        #expect(store.items.isEmpty)
        api.snapshot = snapshot()
        await store.reloadAccount()
        #expect(store.catalogIssue == nil)
    }

    @Test func catalogRequestUsesIOSLanguageAndDecodesServerResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogURLProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let api = CatalogAPIClient(baseURL: URL(string: "https://example.test/api/v1"), transport: transport)
        CatalogURLProtocol.fixture.reset(status: 200, data: try JSONEncoder().encode(snapshot()))
        let loaded = try await api.fetchCatalog()
        #expect(loaded.items == snapshot().items)
        #expect(CatalogURLProtocol.fixture.request?.url?.path == "/api/v1/catalog")
        #expect(CatalogURLProtocol.fixture.request?.value(forHTTPHeaderField: "Accept-Language") == L10n.language())
        #expect(CatalogURLProtocol.fixture.request?.value(forHTTPHeaderField: "Authorization") == nil)
        CatalogURLProtocol.fixture.reset(status: 503, data: Data("{}".utf8))
        await #expect(throws: CatalogError.unavailable) { try await api.fetchCatalog() }
        CatalogURLProtocol.fixture.reset(status: 200, data: Data("{}".utf8))
        await #expect(throws: CatalogError.unavailable) { try await api.fetchCatalog() }
        CatalogURLProtocol.fixture.reset(error: URLError(.notConnectedToInternet))
        await #expect(throws: CatalogError.offline) { try await api.fetchCatalog() }
        CatalogURLProtocol.fixture.reset(error: URLError(.timedOut))
        await #expect(throws: CatalogError.timedOut) { try await api.fetchCatalog() }
        CatalogURLProtocol.fixture.reset(error: URLError(.cannotConnectToHost))
        await #expect(throws: CatalogError.unavailable) { try await api.fetchCatalog() }
        CatalogURLProtocol.fixture.reset(error: URLError(.cancelled))
        await #expect(throws: CancellationError.self) { try await api.fetchCatalog() }
    }
}
