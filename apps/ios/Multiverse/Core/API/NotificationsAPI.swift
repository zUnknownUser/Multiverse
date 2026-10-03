import Foundation

struct ActivityNotification: Codable, Identifiable, Sendable {
    let id: String; let kind: String; let targetType: String; let targetID: String; let commentID: String?
    let createdAt: Date; var readAt: Date?; let user: String
    var label: String {
        switch kind {
        case "message": L10n.text("enviou uma mensagem privada.")
        case "follow": L10n.text("começou a seguir você.")
        case "mention": L10n.text("mencionou você em uma conversa.")
        case "reply": L10n.text("respondeu ao seu comentário.")
        case "comment": L10n.text("comentou na sua publicação.")
        default: L10n.text("reagiu à sua publicação ou comentário.")
        }
    }
}
struct NotificationsPage: Codable, Sendable {
    let notifications: [ActivityNotification]; let users: [User]; let unreadCount: Int; let nextCursor: String?
    func validate() throws {
        guard unreadCount >= 0, notifications.count <= 30, Set(notifications.map(\.id)).count == notifications.count,
              notifications.allSatisfy({ n in UUID(uuidString: n.id) != nil && ["follow", "comment", "reaction", "mention", "reply", "message"].contains(n.kind) && ["person", "review", "post", "message"].contains(n.targetType) && (n.targetType == "person" || UUID(uuidString: n.targetID) != nil) && users.contains(where: { $0.id == n.user }) }),
              nextCursor == nil || (!notifications.isEmpty && !(nextCursor?.isEmpty ?? true)) else { throw SocialError.invalid }
    }
}
struct NotificationPreferences: Codable, Sendable { let activity: Bool; let push: Bool; let pushAvailable: Bool }
@MainActor protocol NotificationsAPI: Sendable {
    func fetchNotifications(after: String?) async throws -> NotificationsPage
    func readNotifications(_ ids: [String]) async throws -> SavedReceipt
    func fetchNotificationPreferences() async throws -> NotificationPreferences
    func saveNotificationPreferences(activity: Bool, push: Bool) async throws -> NotificationPreferences
    func registerPushDevice(id: String, token: String) async throws -> SavedReceipt
    func removePushDevice(id: String) async throws -> SavedReceipt
}
