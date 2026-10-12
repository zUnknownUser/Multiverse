import Foundation
import Testing
@testable import Multiverse

@MainActor private final class LoadingCatalogStub: CatalogAPI {
    var calls = 0
    var hold = false
    var failure: (any Error)?
    var pending: CheckedContinuation<CatalogSnapshot, any Error>?
    var snapshot: CatalogSnapshot = {
        let sample = SampleData.load()
        return .init(version: 1, locale: "pt-BR", universes: sample.universes, comingSoon: [], items: sample.items)
    }()
    func fetchCatalog() async throws -> CatalogSnapshot {
        calls += 1
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let failure { throw failure }
        return snapshot
    }
    func release() { hold = false; pending?.resume(returning: snapshot); pending = nil }
}

@MainActor private final class LoadingAccountStub: AccountAPI {
    var calls = 0
    var hold = false
    var pending: CheckedContinuation<AccountEnvelope, any Error>?
    let envelope = AccountEnvelope(profile: .init(userID: "loading-owner", username: "owner", displayName: "Owner", avatarColor: "#F4A814", bio: ""), onboarding: .init(completed: true))
    func fetchAccount() async throws -> AccountEnvelope {
        calls += 1
        if hold { return try await withCheckedThrowingContinuation { pending = $0 } }
        return envelope
    }
    func release() { hold = false; pending?.resume(returning: envelope); pending = nil }
    func usernameAvailable(_ username: String) async throws -> Bool { true }
    func saveProfile(name: String, username: String, avatarColor: String, bio: String, avatarID: String?) async throws -> RemoteProfile { envelope.profile! }
    func suggestions() async throws -> FollowSuggestions { .init(users: [], minimumFollows: 0) }
    func saveOnboarding(_ state: OnboardingState) async throws -> OnboardingState { state }
    func deleteAccount() async throws {}
}

@MainActor private final class LoadingActivityStub: ActivityAPI {
    var cancelled = true
    func fetchActivity() async throws -> ActivitySnapshot {
        if cancelled { throw CancellationError() }
        return .init(entries: [], reviews: [], items: [], universes: [], followerCount: 0)
    }
    func saveLog(id: UUID, input: SaveLogInput) async throws -> ActivitySnapshot { throw AuthError.unavailable }
}

@MainActor struct AppLoadingTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition())
    }
    private var session: AuthSession { .init(userID: "loading-owner", email: "test@example.com", handle: "@owner") }

    @Test func concurrentBootstrapAndRetryOnlyLoadOnce() async throws {
        let catalog = LoadingCatalogStub(), account = LoadingAccountStub(), writer = WidgetSnapshotSpy()
        catalog.hold = true
        let store = AppStore(session: session, accountAPI: account, widgetWriter: writer, catalogAPI: catalog)
        let first = Task { await store.bootstrap() }
        defer { catalog.release(); first.cancel() }
        try await waitUntil { catalog.pending != nil }
        await store.bootstrap()
        await store.reloadAccount()
        #expect(catalog.calls == 1 && account.calls == 0 && store.isLoading)
        catalog.release(); await first.value
        #expect(account.calls == 1 && !store.isLoading && store.catalogIssue == nil)
        #expect(writer.snapshots.isEmpty) // Real accounts never publish the demo widget.
        await store.bootstrap()
        #expect(catalog.calls == 1 && account.calls == 1 && writer.snapshots.isEmpty)
    }

    @Test(arguments: [false, true]) func cancelledInitialLoadCanBeRetried(useReload: Bool) async {
        let catalog = LoadingCatalogStub(), writer = WidgetSnapshotSpy()
        catalog.failure = CancellationError()
        let store = AppStore(widgetWriter: writer, catalogAPI: catalog)
        await store.bootstrap()
        #expect(!store.isLoading && store.catalogIssue == .unavailable)
        #expect(store.items.isEmpty && writer.snapshots.isEmpty)
        catalog.failure = nil
        if useReload { await store.reloadAccount() } else { await store.bootstrap() }
        #expect(catalog.calls == 2 && !store.isLoading && store.catalogIssue == nil)
        #expect(!store.items.isEmpty && writer.snapshots.count == 1)
    }

    @Test func cancelledTaskDiscardsCatalogEvenIfProviderReturnsSuccess() async throws {
        let catalog = LoadingCatalogStub(), writer = WidgetSnapshotSpy()
        catalog.hold = true
        let store = AppStore(widgetWriter: writer, catalogAPI: catalog)
        let first = Task { await store.bootstrap() }
        defer { catalog.release(); first.cancel() }
        try await waitUntil { catalog.pending != nil }
        first.cancel(); catalog.release(); await first.value
        #expect(!store.isLoading && store.items.isEmpty && writer.snapshots.isEmpty)
        #expect(store.catalogIssue == .unavailable)
        await store.reloadAccount()
        #expect(!store.isLoading && store.catalogIssue == nil && !store.items.isEmpty)
    }

    @Test func cancelledRefreshKeepsConfirmedCatalogAndCanRefreshAgain() async throws {
        let catalog = LoadingCatalogStub(), writer = WidgetSnapshotSpy()
        let store = AppStore(widgetWriter: writer, catalogAPI: catalog)
        await store.bootstrap()
        let oldItems = store.items, oldWrites = writer.snapshots.count
        catalog.snapshot = .init(version: 1, locale: "pt-BR", universes: catalog.snapshot.universes, comingSoon: [], items: [])
        catalog.hold = true
        let refresh = Task { await store.reloadAccount() }
        defer { catalog.release(); refresh.cancel() }
        try await waitUntil { catalog.pending != nil }
        refresh.cancel(); catalog.release(); await refresh.value
        #expect(!store.isLoading && store.catalogIssue == nil && store.items == oldItems)
        #expect(writer.snapshots.count == oldWrites)
        await store.reloadAccount()
        #expect(!store.isLoading && store.items.isEmpty && catalog.calls == 3)
    }

    @Test func accountPhaseAlsoPreventsConcurrentReloads() async throws {
        let catalog = LoadingCatalogStub(), account = LoadingAccountStub()
        let store = AppStore(session: session, accountAPI: account, catalogAPI: catalog)
        await store.bootstrap()
        account.hold = true
        let refresh = Task { await store.reloadAccount() }
        defer { account.release(); refresh.cancel() }
        try await waitUntil { account.pending != nil }
        await store.reloadAccount(); await store.bootstrap()
        #expect(catalog.calls == 2 && account.calls == 2 && store.isLoading)
        account.release(); await refresh.value
        #expect(!store.isLoading && store.accountLoadError == nil)
    }

    @Test func cancelledAccountResponseCannotPublishProfileOrWidgets() async throws {
        let account = LoadingAccountStub(), writer = WidgetSnapshotSpy()
        account.hold = true
        let store = AppStore(session: session, accountAPI: account, widgetWriter: writer)
        let first = Task { await store.bootstrap() }
        defer { account.release(); first.cancel() }
        try await waitUntil { account.pending != nil }
        first.cancel(); account.release(); await first.value
        #expect(!store.isLoading && store.catalogIssue == .unavailable && store.accountLoadError == nil)
        #expect(store.user(session.userID)?.name != "Owner" && writer.snapshots.isEmpty)
        await store.reloadAccount()
        #expect(store.user(session.userID)?.name == "Owner" && !store.isLoading && store.catalogIssue == nil)
    }

    @Test func activityCancellationAlsoReleasesLoadingWithoutPublishingWidgets() async {
        let activity = LoadingActivityStub(), writer = WidgetSnapshotSpy()
        let store = AppStore(widgetWriter: writer, activityAPI: activity)
        await store.bootstrap()
        #expect(!store.isLoading && store.catalogIssue == .unavailable && writer.snapshots.isEmpty)
        activity.cancelled = false
        await store.reloadAccount()
        #expect(!store.isLoading && store.catalogIssue == nil && store.activityLoadError == nil)
        #expect(writer.snapshots.count == 1)
    }

    @Test func failedRefreshClearsItsIssueOnSuccessfulRetry() async {
        let catalog = LoadingCatalogStub()
        let store = AppStore(catalogAPI: catalog)
        await store.bootstrap()
        catalog.failure = CatalogError.unavailable
        await store.reloadAccount()
        #expect(!store.isLoading && store.catalogIssue == .unavailable)
        catalog.failure = nil
        await store.reloadAccount()
        #expect(!store.isLoading && store.catalogIssue == nil && catalog.calls == 3)
    }
}
