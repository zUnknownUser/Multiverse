import Foundation

struct DirectMessage: Codable, Identifiable, Sendable {
    let id: String
    let senderID: String
    let sequence: String
    let createdAt: Date
    let kind: String
    let text: String
    let itemID: String?
    let spoiler: Bool
}
struct DirectConversation: Decodable, Identifiable, Sendable {
    let id: String
    let user: User
    let state: String
    let incomingRequest: Bool
    let unreadCount: Int
    let updatedAt: Date
    let lastMessage: DirectMessage?
}
struct DirectInbox: Decodable, Sendable {
    let conversations: [DirectConversation]
    let unreadCount: Int
    let revision: String
    let nextCursor: String?
    func validate(owner: String) throws {
        guard unreadCount >= 0, UInt64(revision) != nil, conversations.count <= 30,
              Set(conversations.map(\.id)).count == conversations.count,
              Set(conversations.map { $0.user.id }).count == conversations.count,
              conversations.allSatisfy({ UUID(uuidString: $0.id) != nil && $0.user.id != owner && $0.unreadCount >= 0 && ["pending", "accepted"].contains($0.state) && (!$0.incomingRequest || $0.state == "pending") }),
              nextCursor == nil || (!conversations.isEmpty && nextCursor?.isEmpty == false) else { throw SocialError.invalid }
        for c in conversations {
            if let m = c.lastMessage { try DirectHistory.check(m, owner: owner, peer: c.user.id) }
        }
    }
}
struct DirectHistory: Decodable, Sendable {
    let user: User
    let state: String
    let incomingRequest: Bool
    let messages: [DirectMessage]
    let before: String?
    let readThrough: String
    static func check(_ m: DirectMessage, owner: String, peer: String) throws {
        guard UUID(uuidString: m.id) != nil, [owner, peer].contains(m.senderID), (UInt64(m.sequence) ?? 0) > 0,
              ["text", "workCard", "removed"].contains(m.kind), m.text.count <= 2000 else { throw SocialError.invalid }
    }
    func validate(owner: String, peer: String) throws {
        guard user.id == peer, peer != owner, messages.count <= 40, UInt64(readThrough) != nil,
              ["new", "pending", "accepted"].contains(state), !incomingRequest || state == "pending",
              Set(messages.map(\.id)).count == messages.count,
              before == nil || (!messages.isEmpty && before == messages.first?.sequence) else { throw SocialError.invalid }
        var previous: UInt64 = 0
        for m in messages { try Self.check(m, owner: owner, peer: peer); guard let seq = UInt64(m.sequence), seq > previous else { throw SocialError.invalid }; previous = seq }
    }
}
struct DirectMessageInput: Encodable, Equatable, Sendable {
    let kind: String
    let text: String
    let itemID: String?
    let spoiler: Bool
}
struct DirectChanges: Decodable, Sendable { let revision: String }
@MainActor protocol DirectMessagesAPI: Sendable {
    func directInbox(after: String?) async throws -> DirectInbox
    func directHistory(peer: String, before: String?) async throws -> DirectHistory
    func sendDirect(peer: String, id: String, input: DirectMessageInput) async throws -> PostReceipt
    func decideDirect(peer: String, accepted: Bool) async throws -> SavedReceipt
    func readDirect(peer: String, through: String) async throws -> SavedReceipt
    func reportDirect(peer: String, id: String, reason: String, alsoBlock: Bool) async throws -> SavedReceipt
    func directChanges(after: String?) async throws -> DirectChanges
}
extension AccountAPIClient: DirectMessagesAPI {
    func directInbox(after: String?) async throws -> DirectInbox { try await request("me/messages", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? []) }
    func directHistory(peer: String, before: String?) async throws -> DirectHistory { try await request("me/messages/" + peer, query: before.map { [URLQueryItem(name: "before", value: $0)] } ?? []) }
    func sendDirect(peer: String, id: String, input: DirectMessageInput) async throws -> PostReceipt { try await request("me/messages/" + peer + "/messages/" + id, method: "PUT", body: JSONEncoder().encode(input)) }
    func decideDirect(peer: String, accepted: Bool) async throws -> SavedReceipt {
        struct Input: Encodable { let accepted: Bool }
        return try await request("me/messages/" + peer + "/request", method: "PUT", body: JSONEncoder().encode(Input(accepted: accepted)))
    }
    func readDirect(peer: String, through: String) async throws -> SavedReceipt {
        struct Input: Encodable { let through: String }
        return try await request("me/messages/" + peer + "/read", method: "PUT", body: JSONEncoder().encode(Input(through: through)))
    }
    func reportDirect(peer: String, id: String, reason: String, alsoBlock: Bool) async throws -> SavedReceipt {
        struct Input: Encodable { let reason: String; let alsoBlock: Bool }
        return try await request("me/messages/" + peer + "/messages/" + id + "/report", method: "PUT", body: JSONEncoder().encode(Input(reason: reason, alsoBlock: alsoBlock)))
    }
    func directChanges(after: String?) async throws -> DirectChanges { try await request("me/messages/changes", query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [], timeout: 30) }
}
enum DirectMessageError: LocalizedError {
    case unavailable, pending, conflict, limit
    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.text("Esta conversa não está disponível.")
        case .pending: L10n.text("Aguarde o pedido de conversa ser aceito para enviar mais mensagens.")
        case .conflict: L10n.text("Esta mensagem já foi enviada com outro conteúdo. Atualize a conversa.")
        case .limit: L10n.text("Você enviou muitas mensagens. Tente novamente mais tarde.")
        }
    }
}
