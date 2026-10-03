import Foundation
import Observation
import UserNotifications

@MainActor protocol AppBadgeClient {
    func isEnabled() async -> Bool
    func requestPermission() async throws -> Bool
    func setCount(_ count: Int) async throws
}

@MainActor struct SystemAppBadgeClient: AppBadgeClient {
    func isEnabled() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().badgeSetting == .enabled
    }
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge])
    }
    func setCount(_ count: Int) async throws {
        try await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

/// Local icon badges also work in Personal Team builds, independently of APNs.
/// Serialize writes so a delayed response cannot restore a previous account's count.
@MainActor @Observable final class AppBadgeCoordinator {
    static let shared = AppBadgeCoordinator()
    private(set) var enabled = false
    private(set) var requesting = false
    private let client: any AppBadgeClient
    private let defaults: UserDefaults
    private var pending: Task<Void, Never>?
    private var revision = 0

    init(client: any AppBadgeClient = SystemAppBadgeClient(), defaults: UserDefaults = .standard) {
        self.client = client; self.defaults = defaults
    }

    func enable() async throws -> Bool {
        guard !requesting else { return enabled }
        requesting = true
        defer { requesting = false }
        _ = try await client.requestPermission()
        enabled = await client.isEnabled()
        return enabled
    }

    func sync(userID: String?, unreadCount: Int?) async {
        revision += 1
        let epoch = revision, previous = pending
        let task = Task { @MainActor in
            await previous?.value
            guard epoch == revision else { return }
            enabled = await client.isEnabled()
            guard epoch == revision else { return }
            let owner = defaults.string(forKey: "mv-badge-owner")
            // Keep the last synchronized count during same-account startup/offline loading.
            // Clear immediately for logout or a different account, even before its first fetch.
            let count = userID == nil || owner != userID ? (unreadCount ?? 0) : unreadCount
            if let count {
                do { try await client.setCount(userID == nil ? 0 : max(0, count)) }
                catch { return } // Retry on the next refresh/foreground transition.
            }
            if let userID { defaults.set(userID, forKey: "mv-badge-owner") }
            else { defaults.removeObject(forKey: "mv-badge-owner") }
        }
        pending = task
        await task.value
        if epoch == revision { pending = nil }
    }
}
