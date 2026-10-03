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
    private var preferencesRevision = 0
    private var savingPreferences = false
    init(api: any NotificationsAPI) { self.api = api }
    func refresh(more: Bool = false) async {
        guard !busy, !more || nextCursor != nil else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let pageCount = more ? 1 : max(1, (entries.count + 29) / 30)
            var cursor = more ? nextCursor : nil
            var visitedCursors = Set<String>()
            var refreshed = more ? entries : []
            var refreshedUsers = more ? users : [:]
            var knownIDs = Set(refreshed.map(\.id))
            var unread = unreadCount
            for _ in 0..<pageCount {
                if let cursor { visitedCursors.insert(cursor) }
                let page = try await api.fetchNotifications(after: cursor)
                try Task.checkCancellation()
                try page.validate()
                guard page.nextCursor.map({ !visitedCursors.contains($0) }) ?? true else {
                    throw SocialError.invalid
                }
                refreshed += page.notifications.filter { knownIDs.insert($0.id).inserted }
                for user in page.users { refreshedUsers[user.id] = user }
                unread = page.unreadCount
                cursor = page.nextCursor
                if cursor == nil { break }
            }
            // Commit the refreshed pages together; a failed later page keeps known data.
            entries = refreshed
            users = refreshedUsers
            unreadCount = unread
            nextCursor = cursor
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func markRead(_ ids: [String]) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        defer { busy = false }
        // The endpoint accepts at most 100 IDs. Apply only each acknowledged batch,
        // leaving later notifications unread if a subsequent request fails.
        var seen = Set<String>()
        let requested = ids.filter { seen.insert($0).inserted }
        do {
            for start in stride(from: 0, to: requested.count, by: 100) {
                let batch = Array(requested[start..<min(start + 100, requested.count)])
                let result = try await api.readNotifications(batch)
                try Task.checkCancellation()
                guard result.saved else { throw SocialError.invalid }
                let acknowledged = Set(batch)
                for index in entries.indices
                where acknowledged.contains(entries[index].id) && entries[index].readAt == nil {
                    entries[index].readAt = Date()
                    unreadCount = max(0, unreadCount - 1)
                }
            }
            return true
        } catch is CancellationError { return false } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func loadPreferences() async {
        guard !savingPreferences else { return }
        preferencesRevision += 1
        let revision = preferencesRevision
        do {
            let incoming = try await api.fetchNotificationPreferences()
            try Task.checkCancellation()
            guard revision == preferencesRevision else { return }
            preferences = incoming
        } catch is CancellationError {} catch {
            if revision == preferencesRevision { self.error = error.localizedDescription }
        }
    }
    func savePreferences(activity: Bool, push: Bool) async {
        guard !busy else { return }
        busy = true
        error = nil
        preferencesRevision += 1
        savingPreferences = true
        defer {
            busy = false
            savingPreferences = false
        }
        do {
            let saved = try await api.saveNotificationPreferences(activity: activity, push: push)
            guard saved.activity == activity, saved.push == push else { throw SocialError.invalid }
            preferences = saved
        } catch { self.error = error.localizedDescription }
    }
}
