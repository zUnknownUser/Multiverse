import Foundation
import Testing
@testable import Multiverse

@MainActor private final class DirectStub: DirectMessagesAPI {
    let user = User(id: "bob", name: "Bob", handle: "@bob", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: "")
    var messages: [DirectMessage] = []
    var state = "accepted"
    var incoming = false
    var before: String?
    var sent: [(String, DirectMessageInput)] = []
    var reads: [String] = []
    var sendError: (any Error)?
    var historyError: (any Error)?
    var receipt = true
    var historyHook: (() async throws -> DirectHistory)?
    var readHook: (() async throws -> SavedReceipt)?
    var inboxHook: ((String?) async throws -> DirectInbox)?
    var page = DirectInbox(conversations: [], unreadCount: 0, revision: "0", nextCursor: nil)
    func directInbox(after: String?) async throws -> DirectInbox { if let inboxHook { return try await inboxHook(after) }; return page }
    func directHistory(peer: String, before: String?) async throws -> DirectHistory {
        if let historyError { throw historyError }
        if let historyHook { return try await historyHook() }
        return snapshot()
    }
    func snapshot() -> DirectHistory { .init(user: user, state: state, incomingRequest: incoming, messages: messages, before: before, readThrough: "0") }
    func sendDirect(peer: String, id: String, input: DirectMessageInput) async throws -> PostReceipt {
        sent.append((id, input))
        if let sendError { throw sendError }
        if receipt && !messages.contains(where: {$0.id == id}) { messages.append(.init(id: id, senderID: "alice", sequence: String(messages.count + 1), createdAt: .now, kind: input.kind, text: input.text, itemID: input.itemID, spoiler: input.spoiler)) }
        return .init(id: id, saved: receipt)
    }
    func decideDirect(peer: String, accepted: Bool) async throws -> SavedReceipt { if receipt { state = accepted ? "accepted" : "declined"; incoming = false }; return .init(saved: receipt) }
    func readDirect(peer: String, through: String) async throws -> SavedReceipt { reads.append(through); if let readHook { return try await readHook() }; return .init(saved: receipt) }
    func reportDirect(peer: String, id: String, reason: String, alsoBlock: Bool) async throws -> SavedReceipt { .init(saved: receipt) }
    func directChanges(after: String?) async throws -> DirectChanges { throw CancellationError() }
}
@Suite(.serialized) @MainActor struct DirectMessagesTests {
    private func thread(_ api: DirectStub) -> DirectThreadStore { .init(api: api, ownerID: "alice", peerID: "bob") }
    private func message(_ seq: Int, sender: String = "bob") -> DirectMessage { .init(id: UUID().uuidString.lowercased(), senderID: sender, sequence: String(seq), createdAt: .now, kind: "text", text: "Hello", itemID: nil, spoiler: false) }
    @Test func realMessageRoutesAndAccountsStartWithoutSamples() async {
        let api = DirectStub(), store = DirectMessagesStore(api: api, ownerID: "alice")
        await store.refresh()
        #expect(store.conversations.isEmpty && store.unreadCount == 0)
        #expect(store.thread("bob") === store.thread("bob"))
        #expect(!Route.messages.isDemonstration && !Route.conversation("bob").isDemonstration)
        #expect(DirectMessagesStore(api: api, ownerID: "other").conversations.isEmpty)
    }
    @Test func unknownDeliveryRetriesTheSameUUIDAndPayload() async {
        let api = DirectStub(), t = thread(api); await t.refresh(); t.draft = " Hello "; t.spoiler = true
        api.sendError = AuthError.networkUnavailable
        #expect(await t.send() == false); let pending = t.pendingID
        #expect(pending != nil && t.draft == " Hello ")
        api.sendError = nil; #expect(await t.send())
        #expect(api.sent.count == 2 && api.sent[0].0 == api.sent[1].0 && api.sent[0].1 == api.sent[1].1)
        #expect(t.pendingID == nil && t.draft.isEmpty && t.messages.count == 1)
    }
    @Test func falseReceiptKeepsRetryIdentityButDefiniteRejectionUnlocksDraft() async {
        let api = DirectStub(), t = thread(api); await t.refresh(); t.draft = "Read this"; t.attachedItemID = "m-civil"
        api.receipt = false; #expect(await t.send() == false); #expect(t.pendingID != nil && t.attachedItemID == "m-civil")
        api.sendError = ActivityError.itemUnavailable; #expect(await t.send() == false)
        #expect(t.pendingID == nil && t.draft == "Read this" && t.attachedItemID == "m-civil")
    }
    @Test func recoveredHistoryAcknowledgesLostResponse() async {
        let api = DirectStub(), t = thread(api); await t.refresh(); t.draft = "Hi"
        api.sendError = AuthError.networkUnavailable; _ = await t.send()
        let id = t.pendingID!
        api.messages = [.init(id: id, senderID: "alice", sequence: "1", createdAt: .now, kind: "text", text: "Hi", itemID: nil, spoiler: false)]
        api.state = "pending"; await t.refresh()
        #expect(t.pendingID == nil && t.draft.isEmpty && t.messages.count == 1 && !t.canSend)
    }
    @Test func incomingRequestNeedsSuccessfulAcceptanceAndDeclineClearsContent() async {
        let api = DirectStub(); api.state = "pending"; api.incoming = true; api.messages = [message(1)]
        let t = thread(api); await t.refresh(); t.draft = "Hi"; #expect(!t.canSend)
        api.receipt = false; #expect(await t.decide(accepted: true) == false); #expect(t.state == "pending")
        api.receipt = true; #expect(await t.decide(accepted: true)); #expect(t.canSend)
        api.state = "pending"; api.incoming = true; await t.refresh()
        #expect(await t.decide(accepted: false)); #expect(t.unavailable && t.messages.isEmpty)
    }
    @Test func paginationRetainsLoadedHistoryAndRejectsWrongOrder() async {
        let api = DirectStub(); let a=message(1), b=message(2), c=message(3)
        api.messages = [b,c]; api.before = "2"
        let t = thread(api); await t.refresh()
        api.messages = [a]; api.before = nil; await t.refresh(older: true)
        #expect(t.messages.map(\.sequence) == ["1","2","3"])
        api.messages = [b,c]; api.before = "2"; await t.refresh()
        #expect(t.messages.map(\.sequence) == ["1","2","3"])
        api.messages = [c,b]; await t.refresh()
        #expect(t.error != nil && t.messages.map(\.sequence) == ["1","2","3"])
    }
    @Test func blockedRefreshErasesCachedMessages() async {
        let api = DirectStub(); api.messages = [message(1)]; let t = thread(api); await t.refresh()
        api.historyError = DirectMessageError.unavailable; await t.refresh()
        #expect(t.unavailable && t.messages.isEmpty && t.user == nil && !t.canSend)
    }
    @Test func readCursorNeverAdvancesBeyondExplicitlyVisibleMessages() async {
        let api = DirectStub(); api.messages = [message(1),message(2)]; let t=thread(api); await t.refresh()
        #expect(api.reads.isEmpty)
        await t.markVisible(through:"1"); await t.markVisible(through:"1"); await t.markVisible(through:"2")
        #expect(api.reads == ["1","2"])
    }
    @Test func reportHidesOnlyReceivedMessageAndBlockingClearsThread() async {
        let api=DirectStub(), incoming=message(1), own=message(2,sender:"alice"); api.messages=[incoming,own]
        let t=thread(api); await t.refresh()
        #expect(await t.report(own, reason:"spam", alsoBlock:false) == false)
        #expect(await t.report(incoming, reason:"spam", alsoBlock:false))
        #expect(t.messages[0].kind == "removed" && t.messages[0].text.isEmpty && t.messages[1].text == "Hello")
        #expect(await t.report(incoming, reason:"spam", alsoBlock:true)); #expect(t.unavailable && t.messages.isEmpty)
    }
    @Test func staleHistoryCannotOverwriteAConfirmedSend() async {
        let api=DirectStub(), t=thread(api); await t.refresh(); t.draft="Hi"
        let stale=api.snapshot()
        var continuation: CheckedContinuation<DirectHistory,Never>?
        api.historyHook = { await withCheckedContinuation { continuation = $0 } }
        let load=Task { await t.refresh() }
        while continuation == nil { await Task.yield() }
        #expect(await t.send()); api.historyHook=nil
        continuation?.resume(returning:stale); await load.value
        #expect(t.messages.count == 1 && t.messages[0].text == "Hi")
    }
    @Test func inboxRejectsDuplicateThreadsAndKeepsConfirmedUnread() async {
        let api=DirectStub(), store=DirectMessagesStore(api:api,ownerID:"alice")
        let c=DirectConversation(id:UUID().uuidString,user:api.user,state:"accepted",incomingRequest:false,unreadCount:2,updatedAt:.now,lastMessage:message(1))
        api.page = .init(conversations:[c],unreadCount:2,revision:"1",nextCursor:nil); await store.refresh()
        api.page = .init(conversations:[c,c],unreadCount:0,revision:"2",nextCursor:nil); await store.refresh()
        #expect(store.unreadCount == 2 && store.conversations.count == 1 && store.error != nil)
    }
    @Test func olderPagesRemainAccessibleAndMemoryCompactsOnlyOnExit() async {
        let api=DirectStub(), t=thread(api)
        api.messages=(401...440).map { message($0) }; api.before="401"; await t.refresh()
        for start in stride(from:361,through:1,by:-40) {
            api.messages=(start..<(start+40)).map { message($0) }
            api.before=start == 1 ? nil : String(start)
            await t.refresh(older:true)
        }
        #expect(t.messages.count == 440 && t.messages.first?.sequence == "1" && t.before == nil)
        t.compactHistory()
        #expect(t.messages.count == 40 && t.messages.first?.sequence == "401" && t.before == "401")
    }

    @Test func newerVisibleMessageQueuesBehindAnInFlightReadEvenIfViewTaskIsReplaced() async {
        let api = DirectStub(), t = thread(api); api.messages = [message(1), message(2)]; await t.refresh()
        var continuation: CheckedContinuation<SavedReceipt, any Error>?
        api.readHook = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let first = Task { await t.markVisible(through: "1") }
        while continuation == nil { await Task.yield() }
        first.cancel()
        let second = Task { await t.markVisible(through: "2") }
        await Task.yield()
        api.readHook = nil; continuation?.resume(returning: .init(saved: true))
        await first.value; await second.value
        #expect(api.reads == ["1", "2"])
        await t.markVisible(through: "2"); #expect(api.reads.count == 2)
    }
    @Test func outdatedUnavailableHistoryCannotEraseAConfirmedSend() async {
        let api = DirectStub(), t = thread(api); await t.refresh(); t.draft = "Hi"
        var continuation: CheckedContinuation<DirectHistory, any Error>?
        api.historyHook = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let load = Task { await t.refresh() }
        while continuation == nil { await Task.yield() }
        #expect(await t.send()); api.historyHook = nil
        continuation?.resume(throwing: DirectMessageError.unavailable); await load.value
        #expect(!t.unavailable && t.messages.count == 1 && t.error == nil)
    }

    @Test func liveInboxRefreshPreservesLoadedPagesAndRemovesUnavailablePeers() async {
        let api = DirectStub(), store = DirectMessagesStore(api: api, ownerID: "alice")
        let rows = (0..<60).map { index in
            DirectConversation(id: UUID().uuidString, user: User(id: "peer-\(index)", name: "Peer", handle: "@peer\(index)", avatarColor: "#F4A814", bio: "", followers: nil, badgeUniverse: ""), state: "accepted", incomingRequest: false, unreadCount: 0, updatedAt: .now, lastMessage: nil)
        }
        var removeLast = false
        var failSecond = false
        var calls: [String?] = []
        api.inboxHook = { cursor in
            calls.append(cursor)
            if cursor != nil && failSecond { throw AuthError.networkUnavailable }
            let page = cursor == nil ? Array(rows.prefix(30)) : Array(rows.suffix(removeLast ? 29 : 30))
            return .init(conversations: page, unreadCount: 0, revision: "1", nextCursor: cursor == nil ? "older" : nil)
        }
        await store.refresh(); await store.refresh(more: true)
        #expect(store.conversations.count == 60)
        await store.refresh()
        #expect(store.conversations.count == 60 && calls == [nil, "older", nil, "older"])
        failSecond = true; await store.refresh()
        #expect(store.conversations.count == 60 && store.error != nil)
        failSecond = false; removeLast = true; await store.refresh()
        #expect(store.conversations.count == 59 && !store.conversations.contains { $0.id == rows[30].id })
    }

}
