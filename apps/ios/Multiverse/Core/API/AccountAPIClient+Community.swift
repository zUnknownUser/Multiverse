import Foundation

extension AccountAPIClient {
    func fetchPosts(universe: String?, item: String?, after: String?) async throws -> CommunityPage {
        try await request("posts", query: [("universe", universe), ("item", item), ("after", after)].compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } })
    }
    func fetchPost(_ id: String) async throws -> CommunityPage { try await request("posts/" + id) }
    func publishPost(id: String, input: PostInput) async throws -> PostReceipt { try await request("posts/" + id, method: "PUT", body: JSONEncoder().encode(input)) }
    func deletePost(_ id: String) async throws -> PostDeletion { try await request("posts/" + id, method: "DELETE") }
    func fetchPostComments(_ id: String, after: String?) async throws -> CommentsPage {
        try await request("posts/" + id + "/comments", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }
    func postReply(post: String, id: String, text: String, spoiler: Bool) async throws -> CommentReceipt {
        struct Input: Encodable { let text: String; let spoiler: Bool }
        return try await request("posts/" + post + "/comments/" + id, method: "PUT", body: JSONEncoder().encode(Input(text: text, spoiler: spoiler)))
    }
    func reactToPost(_ id: String, comment: String?, reaction: String?, liked: Bool) async throws -> InteractionSummary {
        let body: [String: Any] = ["reaction": reaction as Any? ?? NSNull(), "liked": liked]
        return try await request("posts/" + id + (comment.map { "/comments/" + $0 } ?? "") + "/reaction", method: "PUT", body: JSONSerialization.data(withJSONObject: body))
    }
    func reportPost(_ id: String, reason: String, alsoBlock: Bool) async throws -> ReportReceipt {
        try await request("posts/" + id + "/report", method: "PUT", body: JSONSerialization.data(withJSONObject: ["reason": reason, "alsoBlock": alsoBlock]))
    }
    func reportPostComment(_ id: String, comment: String, reason: String, alsoBlock: Bool) async throws -> CommentReportReceipt {
        try await request("posts/" + id + "/comments/" + comment + "/report", method: "PUT", body: JSONSerialization.data(withJSONObject: ["reason": reason, "alsoBlock": alsoBlock]))
    }
    func fetchNotifications(after: String?) async throws -> NotificationsPage {
        try await request("me/notifications", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }
    func readNotifications(_ ids: [String]) async throws -> SavedReceipt {
        try await request("me/notifications/read", method: "PUT", body: JSONSerialization.data(withJSONObject: ["ids": ids]))
    }
    func fetchNotificationPreferences() async throws -> NotificationPreferences { try await request("me/notification-preferences") }
    func saveNotificationPreferences(activity: Bool, push: Bool) async throws -> NotificationPreferences {
        try await request("me/notification-preferences", method: "PUT", body: JSONSerialization.data(withJSONObject: ["activity": activity, "push": push]))
    }
    func registerPushDevice(id: String, token: String) async throws -> SavedReceipt {
        try await request("me/push-devices/" + id, method: "PUT", body: JSONSerialization.data(withJSONObject: ["token": token]))
    }
    func removePushDevice(id: String) async throws -> SavedReceipt { try await request("me/push-devices/" + id, method: "DELETE") }
}
