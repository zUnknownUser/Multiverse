import Foundation
import Testing
@testable import Multiverse

@MainActor private final class NotificationsStub: NotificationsAPI {
    var page = NotificationsPage(notifications: [], users: [], unreadCount: 0, nextCursor: nil)
    var fail = false
    var readIDs: [String] = []
    var receipt = true
    var preferences = NotificationPreferences(activity: true, push: false, pushAvailable: false)
    func fetchNotifications(after: String?) async throws -> NotificationsPage { if fail { throw AuthError.networkUnavailable }; return page }
    func readNotifications(_ ids: [String]) async throws -> SavedReceipt { readIDs = ids; if fail { throw AuthError.networkUnavailable }; return SavedReceipt(saved: receipt) }
    func fetchNotificationPreferences() async throws -> NotificationPreferences { preferences }
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
}
