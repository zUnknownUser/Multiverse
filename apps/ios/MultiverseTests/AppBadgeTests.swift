import Foundation
import Testing
@testable import Multiverse

@MainActor private final class BadgeStub: AppBadgeClient {
    var allowed = true
    var counts: [Int] = []
    var requests = 0
    var failure = false
    var writeHook: (() async -> Void)?
    func isEnabled() async -> Bool { allowed }
    func requestPermission() async throws -> Bool { requests += 1; return allowed }
    func setCount(_ count: Int) async throws {
        if let writeHook { await writeHook() }
        if failure { throw AuthError.networkUnavailable }
        counts.append(count)
    }
}
@Suite(.serialized) @MainActor struct AppBadgeTests {
    private func make(_ client: BadgeStub) -> AppBadgeCoordinator {
        AppBadgeCoordinator(client: client, defaults: UserDefaults(suiteName: "badge-test-" + UUID().uuidString)!)
    }
    @Test func countsFollowConfirmedActivityAndClearAtZero() async {
        let client = BadgeStub()
        let subject = make(client)
        await subject.sync(userID: "alice", unreadCount: 7)
        await subject.sync(userID: "alice", unreadCount: 6)
        await subject.sync(userID: "alice", unreadCount: 0)
        #expect(client.counts == [7, 6, 0])
        #expect(client.requests == 0)
    }
    @Test func offlineStartupPreservesCountButAccountChangeAndLogoutClearIt() async {
        let client = BadgeStub(), subject = make(client)
        await subject.sync(userID: "alice", unreadCount: 5)
        await subject.sync(userID: "alice", unreadCount: nil)
        #expect(client.counts == [5])
        await subject.sync(userID: "bob", unreadCount: nil)
        await subject.sync(userID: "bob", unreadCount: 2)
        await subject.sync(userID: nil, unreadCount: nil)
        #expect(client.counts == [5, 0, 2, 0])
    }
    @Test func deniedPermissionDoesNotPretendToEnableBadges() async throws {
        let client = BadgeStub(), subject = make(client)
        client.allowed = false
        #expect(try await subject.enable() == false)
        #expect(!subject.enabled && !subject.requesting && client.requests == 1)
    }
    @Test func failedWriteCanBeRetried() async {
        let client = BadgeStub(), subject = make(client)
        client.failure = true
        await subject.sync(userID: "alice", unreadCount: 4)
        client.failure = false
        await subject.sync(userID: "alice", unreadCount: 4)
        #expect(client.counts == [4])
    }
    @Test func logoutCannotBeOverwrittenByAnInFlightWrite() async {
        let client = BadgeStub(), subject = make(client)
        var started = false
        var release: CheckedContinuation<Void, Never>?
        client.writeHook = {
            started = true
            await withCheckedContinuation { release = $0 }
            client.writeHook = nil
        }
        let old = Task { await subject.sync(userID: "alice", unreadCount: 8) }
        while !started { await Task.yield() }
        let logout = Task { await subject.sync(userID: nil, unreadCount: nil) }
        await Task.yield()
        release?.resume()
        await old.value; await logout.value
        #expect(client.counts.last == 0)
    }
}
