import Foundation
import Testing
@testable import Multiverse

@MainActor private final class PaginatedCatalogStub: CatalogAPI {
    var usesPagination: Bool { true }
    var bootstrapCalls = 0
    var fullCalls = 0
    var calls: [(CatalogQuery, String?)] = []
    var batches: [[String]] = []
    var failure = false
    var hold = false
    var pending: CheckedContinuation<CatalogItemPage, any Error>?
    var holdReferences = false
    var pendingReferences: CheckedContinuation<CatalogResolution, any Error>?
    let fixture = SampleData.load()
    var result: CatalogItemPage?
    func snapshot() -> CatalogSnapshot {
        .init(version: 1, locale: L10n.language(), universes: fixture.universes, comingSoon: [], items: [fixture.items[0]],
              discoveryIDs: [fixture.items[0].id], onboardingIDs: [fixture.items[0].id], topRatedIDs: [fixture.items[0].id], aggregateAverage: 3)
    }
    func fetchCatalog() async throws -> CatalogSnapshot { fullCalls += 1; throw CatalogError.unavailable }
    func fetchBootstrap() async throws -> CatalogSnapshot { bootstrapCalls += 1; return snapshot() }
    func fetchItems(query: CatalogQuery, after: String?) async throws -> CatalogItemPage {
        calls.append((query, after))
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        if failure { throw CatalogError.offline }
        return result ?? .init(locale: L10n.language(), total: 100, items: [fixture.items[1]], nextCursor: "next")
    }
    func resolveItems(ids: [String]) async throws -> CatalogResolution {
        batches.append(ids)
        if holdReferences { return try await withCheckedThrowingContinuation { pendingReferences = $0 } }
        if failure { throw CatalogError.offline }
        let found = fixture.items.filter { ids.contains($0.id) }
        return .init(locale: L10n.language(), items: found, missingIDs: ids.filter { id in !found.contains { $0.id == id } })
    }
    func fetchSeries(universe: String?, after: String?) async throws -> CatalogSeriesPage {
        if failure { throw CatalogError.offline }
        return .init(locale: L10n.language(), total: 1, series: [.init(id: "example", title: "Example", year: 2025, universe: "marvel", total: 125)], nextCursor: nil)
    }
    func fetchSeries(id: String) async throws -> CatalogSeriesRecord { .init(id: id, title: "Example", year: 2025, universe: "marvel", total: 125) }
}

@MainActor private final class CatalogOnboardingStub: AccountAPI {
    let profile = RemoteProfile(userID: "catalog-owner", username: "owner", displayName: "Owner", avatarColor: "#F4A814", bio: "")
    var progress = OnboardingState(universeIDs: ["marvel"], step: 2)
    func fetchAccount() async throws -> AccountEnvelope { .init(profile: profile, onboarding: progress) }
    func usernameAvailable(_ username: String) async throws -> Bool { true }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String, avatarID: String?) async throws -> RemoteProfile { profile }
    func suggestions() async throws -> FollowSuggestions { .init(users: [], minimumFollows: 0) }
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState { progress = state; return state }
    func deleteAccount() async throws {}
}

@MainActor struct CatalogStoreTests {
    @Test func startupUsesOnlyBootstrapAndPageFailureKeepsLastConfirmedResults() async {
        let api = PaginatedCatalogStub()
        // Verify the actual injected instance, independently of demo repository support.
        let app = AppStore(catalogAPI: api)
        await app.bootstrap()
        #expect(api.bootstrapCalls == 1 && api.fullCalls == 0)
        #expect(app.items.count == 1)
        let catalog = app.catalogStore, query = CatalogQuery(text: "Batman")
        await catalog.load(query)
        #expect(catalog.page(query).values.count == 1 && catalog.page(query).total == 100)
        #expect(app.item(api.fixture.items[1].id) != nil)
        #expect(app.homeDiscoveryItems.map(\.id) == [api.fixture.items[0].id])
        api.failure = true
        await catalog.load(query, more: true)
        #expect(catalog.page(query).values.count == 1 && catalog.page(query).nextCursor == "next")
        #expect(catalog.page(query).error != nil)
        api.failure = false
        api.result = .init(locale: L10n.language(), total: 100, items: [api.fixture.items[1],api.fixture.items[2]], nextCursor: nil)
        await catalog.load(query, more: true)
        #expect(catalog.page(query).values.count == 2 && catalog.page(query).error == nil)
        #expect(api.calls.last?.1 == "next")
    }
    @Test func repeatedCursorAndInvalidReferencesCannotReplaceAValidPage() async {
        let api = PaginatedCatalogStub()
        let actual = CatalogStore(api: api); actual.install(api.snapshot())
        await actual.load(.init())
        await actual.load(.init(), more: true)
        #expect(actual.page(.init()).error != nil && actual.page(.init()).values.count == 1)
        api.result = .init(locale: L10n.language(), total: 0, items: [api.fixture.items[1]], nextCursor: nil)
        await actual.load(.init(), refresh: true)
        #expect(actual.page(.init()).total == 100)
    }
    @Test func latePageCannotRepopulateAnInvalidatedCatalog() async throws {
        let api = PaginatedCatalogStub(), query = CatalogQuery(text: "old")
        let catalog = CatalogStore(api: api); catalog.install(api.snapshot()); api.hold = true
        let read = Task { await catalog.load(query) }
        for _ in 0..<100 where api.pending == nil { await Task.yield() }
        let pending = try #require(api.pending)
        catalog.install(api.snapshot())
        pending.resume(returning: .init(locale: L10n.language(), total: 1, items: [api.fixture.items[2]], nextCursor: nil))
        await read.value
        #expect(catalog.itemsByID[api.fixture.items[2].id] == nil)
        #expect(!catalog.page(query).loaded)
    }
    @Test func referenceResolutionBatchesDoesNotTreatNetworkErrorsAsMissing() async {
        let api = PaginatedCatalogStub()
        let actual = CatalogStore(api: api); actual.install(api.snapshot())
        let known = api.fixture.items[2].id
        api.failure = true; await actual.resolve([known])
        #expect(actual.itemErrors[known] != nil && !actual.missingIDs.contains(known))
        api.failure = false
        let ids = (0..<101).map { "missing-\($0)" } + [known,known]
        await actual.resolve(ids)
        #expect(api.batches.suffix(3).map(\.count) == [50,50,2])
        #expect(actual.itemsByID[known] != nil && actual.itemErrors[known] == nil)
        #expect(actual.missingIDs.count == 101 && actual.resolvingIDs.isEmpty)
    }
    @Test func returningToAnInFlightQueryDoesNotLoseTheNewResult() async throws {
        let api = PaginatedCatalogStub(), query = CatalogQuery(text: "return")
        let catalog = CatalogStore(api: api); catalog.install(api.snapshot()); api.hold = true
        let old = Task { await catalog.load(query) }
        for _ in 0..<100 where api.pending == nil { await Task.yield() }
        let pending = try #require(api.pending)
        old.cancel(); api.hold = false
        await catalog.load(query)
        pending.resume(throwing: CatalogError.offline)
        await old.value
        #expect(catalog.page(query).loaded && !catalog.page(query).loading)
        #expect(catalog.page(query).error == nil)
        #expect(catalog.page(query).values.map(\.id) == [api.fixture.items[1].id])
    }
    @Test func sharedReferencesFinishWhenTheOriginatingScreenCloses() async throws {
        let api = PaginatedCatalogStub()
        let actual = CatalogStore(api: api); actual.install(api.snapshot())
        api.holdReferences = true
        let item = api.fixture.items[1]
        let origin = Task { await actual.resolve([item.id]) }
        for _ in 0..<100 where api.pendingReferences == nil { await Task.yield() }
        let pending = try #require(api.pendingReferences)
        origin.cancel()
        await actual.resolve([item.id])
        pending.resume(returning: .init(locale: L10n.language(), items: [item], missingIDs: []))
        await origin.value
        #expect(api.batches.count == 1 && actual.itemsByID[item.id] != nil)
        #expect(actual.resolvingIDs.isEmpty)
    }
    @Test func onboardingRetainsPublishedOffPageSelectionsAndDropsOnlyConfirmedRetirements() async {
        let api = PaginatedCatalogStub(), account = CatalogOnboardingStub()
        let selected = api.fixture.items.first { $0.id != api.fixture.items[0].id && $0.type != "Personagem" }!.id
        account.progress.seenItemIDs = [selected, "retired-work"]
        let session = AuthSession(userID: account.profile.userID, email: "test@example.com", handle: "owner", displayName: "Owner")
        let app = AppStore(session: session, accountAPI: account, catalogAPI: api)
        api.failure = true
        await app.bootstrap()
        #expect(app.accountLoadError != nil && app.checks[selected] == nil)
        api.failure = false
        await app.reloadAccount()
        #expect(app.accountLoadError == nil && app.checks[selected] == true)
        #expect(app.checks["retired-work"] == nil && app.items.count == 1)
    }
    @Test func seriesProgressUsesWholeMembershipRatherThanVisibleEditions() async {
        let api = PaginatedCatalogStub()
        let app = AppStore(catalogAPI: api)
        await app.bootstrap()
        let id = "unloaded-issue"
        app.diary = [.init(itemId: id, loggedAt: .now, rating: 4)]
        app.catalogStore.applyReferences([.init(id: id, uni: "marvel", type: "HQ", seriesID: "example")])
        await app.catalogStore.loadSeries()
        let group = app.catalogSeries()[0]
        #expect(group.itemCount == 125 && group.items.isEmpty)
        #expect(app.registeredIssueCount(in: group) == 1)
        let total = app.universe("marvel")!.total
        #expect(app.universePercent("marvel") == min(100,100/total))
        #expect(api.fullCalls == 0)
    }
}
