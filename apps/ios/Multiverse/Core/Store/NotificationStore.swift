import Foundation
import Observation

@MainActor @Observable final class NotificationStore {
    let api: any NotificationsAPI
    private(set) var entries: [ActivityNotification] = []
    private(set) var users: [String: User] = [:]
    private(set) var unreadCount = 0
    private(set) var nextCursor: String?
    private(set) var preferences: NotificationPreferences?
    private(set) var error: String?
    private(set) var busy = false
    init(api: any NotificationsAPI) { self.api = api }
    func refresh(more: Bool = false) async {
        guard !busy, !more || nextCursor != nil else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let cursor = more ? nextCursor : nil
            let page = try await api.fetchNotifications(after: cursor)
            try Task.checkCancellation(); try page.validate()
            guard page.nextCursor == nil || page.nextCursor != cursor else { throw SocialError.invalid }
            let previous = more ? entries : []
            entries = previous + page.notifications.filter { n in !previous.contains(where: { $0.id == n.id }) }
            for user in page.users { users[user.id] = user }
            unreadCount = page.unreadCount; nextCursor = page.nextCursor
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    func markRead(_ ids: [String]) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        do {
            let result = try await api.readNotifications(Array(ids.prefix(100)))
            guard result.saved else { throw SocialError.invalid }
            for index in entries.indices where ids.contains(entries[index].id) && entries[index].readAt == nil {
                entries[index].readAt = Date(); unreadCount = max(0, unreadCount - 1)
            }
            busy = false
            return true
        } catch { self.error = error.localizedDescription; busy = false; return false }
    }
    func loadPreferences() async {
        do { preferences = try await api.fetchNotificationPreferences() }
        catch { self.error = error.localizedDescription }
    }
    func savePreferences(activity: Bool, push: Bool) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let saved = try await api.saveNotificationPreferences(activity: activity, push: push)
            guard saved.activity == activity, saved.push == push else { throw SocialError.invalid }
            preferences = saved
        } catch { self.error = error.localizedDescription }
    }
}
