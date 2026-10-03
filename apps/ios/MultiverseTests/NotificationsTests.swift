import Foundation
import Testing
@testable import Multiverse

@MainActor private final class NotificationsStub: NotificationsAPI {
    var page = NotificationsPage(notifications: [], users: [], unreadCount: 0, nextCursor: nil)
    var fail = false
    var readIDs: [String] = []
    var readBatches: [[String]] = []
    var failReadBatch: Int?
    var preferencesHook: (() async throws -> NotificationPreferences)?
    var pageHook: ((String?) async throws -> NotificationsPage)?
    var receipt = true
    var preferences = NotificationPreferences(activity: true, push: false, pushAvailable: false)
    func fetchNotifications(after: String?) async throws -> NotificationsPage { if let pageHook { return try await pageHook(after) }; if fail { throw AuthError.networkUnavailable }; return page }
    func readNotifications(_ ids: [String]) async throws -> SavedReceipt { readIDs = ids; readBatches.append(ids); if fail || readBatches.count == failReadBatch { throw AuthError.networkUnavailable }; return SavedReceipt(saved: receipt) }
    func fetchNotificationPreferences() async throws -> NotificationPreferences { if let preferencesHook { return try await preferencesHook() }; return preferences }
    func saveNotificationPreferences(activity: Bool, push: Bool) async throws -> NotificationPreferences {
        if fail { throw AuthError.networkUnavailable }
        preferences = .init(activity: activity, push: push, pushAvailable: false); return preferences
    }
    func registerPushDevice(id: String, token: String) async throws -> SavedReceipt { .init(saved: true) }
    func removePushDevice(id: String) async throws -> SavedReceipt { .init(saved: true) }
}
@Suite(.serialized) @MainActor struct NotificationsTests {
    let user = User(id: "alice", name: "Alice", handle: "@alice", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")
    func entry() -> ActivityNotification { .init(id: UUID().uuidString.lowercased(), kind: "follow", targetType: "person", targetID: "alice", commentID: nil, createdAt: .now, readAt: nil, user: "alice") }
    @Test func badgeComesFromServerAndReadFailureKeepsUnread() async {
        let api = NotificationsStub(), first = entry()
        api.page = .init(notifications: [first], users: [user], unreadCount: 7, nextCursor: nil)
        let store = NotificationStore(api: api)
        await store.refresh(); #expect(store.unreadCount == 7)
        api.fail = true
        #expect(await store.markRead([first.id]) == false)
        #expect(store.unreadCount == 7 && store.entries[0].readAt == nil)
        api.fail = false
        #expect(await store.markRead([first.id]))
        #expect(store.unreadCount == 6 && store.entries[0].readAt != nil)
        #expect(api.readIDs == [first.id])
    }
    @Test func failedRefreshPreservesKnownActivityWithoutCreatingSamples() async {
        let api = NotificationsStub(), store = NotificationStore(api: NotificationsStub())
        await store.refresh(); #expect(store.entries.isEmpty && store.unreadCount == 0)
        api.page = .init(notifications: [entry()], users: [user], unreadCount: 1, nextCursor: nil)
        let loaded = NotificationStore(api: api)
        await loaded.refresh(); api.fail = true; await loaded.refresh()
        #expect(loaded.entries.count == 1 && loaded.unreadCount == 1 && loaded.error != nil)
    }
    @Test func invalidServerPayloadDoesNotReplaceConfirmedState() async {
        let api = NotificationsStub(), first = entry(), store = NotificationStore(api: NotificationsStub())
        await store.refresh()
        api.page = .init(notifications: [first], users: [user], unreadCount: 1, nextCursor: nil)
        let loaded = NotificationStore(api: api); await loaded.refresh()
        api.page = .init(notifications: [first, first], users: [], unreadCount: -1, nextCursor: nil)
        await loaded.refresh()
        #expect(loaded.entries.count == 1 && loaded.unreadCount == 1 && loaded.error != nil)
    }
    @Test func preferencesOnlyChangeAfterConfirmationAndNewAccountStartsEmpty() async {
        let api = NotificationsStub(), store = NotificationStore(api: NotificationsStub())
        let active = NotificationStore(api: api); await active.loadPreferences()
        api.fail = true; await active.savePreferences(activity: false, push: false)
        #expect(active.preferences?.activity == true && active.error != nil)
        #expect(store.entries.isEmpty && store.unreadCount == 0)
    }
    private func loadedNotifications(_ api: NotificationsStub) async -> NotificationStore {
        let store = NotificationStore(api: api)
        for page in 0..<4 {
            api.page = .init(notifications: (0..<30).map { _ in entry() }, users: [user], unreadCount: 120, nextCursor: page == 3 ? nil : "page-\(page)")
            await store.refresh(more: page > 0)
        }
        return store
    }
    @Test func readingMoreThan100NotificationsAcknowledgesEveryBatch() async {
        let api = NotificationsStub(), store = await loadedNotifications(api)
        let ids = store.entries.map(\.id)
        #expect(await store.markRead(ids + ids))
        #expect(api.readBatches.map(\.count) == [100, 20])
        #expect(Set(api.readBatches.flatMap { $0 }) == Set(ids))
        #expect(store.unreadCount == 0 && store.entries.allSatisfy { $0.readAt != nil })
    }
    @Test func failureInSecondReadBatchLeavesOnlyUnacknowledgedAlertsUnread() async {
        let api = NotificationsStub(), store = await loadedNotifications(api)
        api.failReadBatch = 2
        #expect(await store.markRead(store.entries.map(\.id)) == false)
        #expect(store.unreadCount == 20 && store.entries.filter { $0.readAt == nil }.count == 20)
        api.failReadBatch = nil
        #expect(await store.markRead(store.entries.filter { $0.readAt == nil }.map(\.id)))
        #expect(store.unreadCount == 0)
    }
    @Test func delayedPreferenceReadCannotUndoAConfirmedSetting() async {
        let api = NotificationsStub(), store = NotificationStore(api: api)
        let old = api.preferences
        var continuation: CheckedContinuation<NotificationPreferences, any Error>?
        api.preferencesHook = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let load = Task { await store.loadPreferences() }
        while continuation == nil { await Task.yield() }
        await store.savePreferences(activity: false, push: false)
        continuation?.resume(returning: old); await load.value
        #expect(store.preferences?.activity == false && store.error == nil)
    }

    @Test func refreshKeepsTheLoadedRangeAndDoesNotPartiallyReplacePagesOnFailure() async {
        let api = NotificationsStub(), store = NotificationStore(api: api)
        let alerts = (0..<60).map { _ in entry() }; let actor = user
        var failSecond = false
        api.pageHook = { cursor in
            if cursor != nil && failSecond { throw AuthError.networkUnavailable }
            return .init(notifications: cursor == nil ? Array(alerts.prefix(30)) : Array(alerts.suffix(30)), users: [actor], unreadCount: 60, nextCursor: cursor == nil ? "older" : nil)
        }
        await store.refresh(); await store.refresh(more: true); await store.refresh()
        #expect(store.entries.map(\.id) == alerts.map(\.id))
        failSecond = true; await store.refresh()
        #expect(store.entries.map(\.id) == alerts.map(\.id) && store.error != nil)
    }

}
