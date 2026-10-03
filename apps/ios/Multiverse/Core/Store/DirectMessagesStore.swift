import Foundation
import Observation

@MainActor @Observable final class DirectMessagesStore {
    let api: any DirectMessagesAPI
    let ownerID: String
    private(set) var conversations: [DirectConversation] = []
    private(set) var unreadCount = 0
    private(set) var nextCursor: String?
    private(set) var error: String?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var epoch = 0
    private var threads: [String: DirectThreadStore] = [:]
    var activePeer: String?
    init(api: any DirectMessagesAPI, ownerID: String) {
        self.api = api
        self.ownerID = ownerID
    }
    func thread(_ peer: String) -> DirectThreadStore {
        if let existing = threads[peer] { return existing }
        let thread = DirectThreadStore(api: api, ownerID: ownerID, peerID: peer)
        threads[peer] = thread
        return thread
    }
    func refresh(more: Bool = false) async {
        guard !loading, !more || nextCursor != nil else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            // Refresh the same number of pages the user has opened. A live event
            // must not collapse a long inbox back to its first 30 conversations.
            let pageCount = more ? 1 : max(1, (conversations.count + 29) / 30)
            var cursor = more ? nextCursor : nil
            var visitedCursors = Set<String>()
            var refreshed = more ? conversations : []
            var knownIDs = Set(refreshed.map(\.id))
            var unread = unreadCount
            for _ in 0..<pageCount {
                if let cursor { visitedCursors.insert(cursor) }
                let page = try await api.directInbox(after: cursor)
                try Task.checkCancellation()
                try page.validate(owner: ownerID)
                guard page.nextCursor.map({ !visitedCursors.contains($0) }) ?? true else {
                    throw SocialError.invalid
                }
                refreshed += page.conversations.filter { knownIDs.insert($0.id).inserted }
                unread = page.unreadCount
                cursor = page.nextCursor
                if cursor == nil { break }
            }
            conversations = refreshed
            nextCursor = cursor
            unreadCount = unread
            loaded = true
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    /// One cancellable long poll for this signed-in session, only while foregrounded.
    func run() async {
        var revision: String?
        var delay = 1
        while !Task.isCancelled {
            do {
                let change = try await api.directChanges(after: revision)
                try Task.checkCancellation()
                guard UInt64(change.revision) != nil else { throw SocialError.invalid }
                revision = change.revision
                await refresh()
                if let activePeer { await threads[activePeer]?.refresh() }
                epoch += 1
                delay = 1
            } catch is CancellationError { break } catch {
                self.error = error.localizedDescription
                do { try await Task.sleep(for: .seconds(delay)) } catch { break }
                delay = min(20, delay * 2)
            }
        }
    }
}

@MainActor @Observable final class DirectThreadStore {
    let api: any DirectMessagesAPI
    let ownerID: String
    let peerID: String
    private(set) var user: User?
    private(set) var messages: [DirectMessage] = []
    private(set) var state = "new"
    private(set) var incomingRequest = false
    private(set) var readThrough: UInt64 = 0
    private(set) var before: String?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var sending = false
    private(set) var unavailable = false
    private(set) var error: String?
    var draft = ""
    var spoiler = false
    var attachedItemID: String?
    private(set) var pendingID: String?
    private var pendingInput: DirectMessageInput?
    private var markedThrough: UInt64 = 0
    private var requestedReadThrough: UInt64 = 0
    private var readTask: Task<Void, Never>?
    private var mutationEpoch = 0
    private var refreshAgain = false
    var canSend: Bool {
        loaded && !unavailable && (state != "pending" || pendingID != nil) && !sending
            && (pendingID != nil || attachedItemID != nil
                || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && draft.count <= 2000
    }
    init(api: any DirectMessagesAPI, ownerID: String, peerID: String) {
        self.api = api
        self.ownerID = ownerID
        self.peerID = peerID
    }
    func refresh(older: Bool = false) async {
        guard !loading else {
            if !older { refreshAgain = true }
            return
        }
        guard !older || before != nil else { return }
        loading = true
        let epoch = mutationEpoch
        do {
            let cursor = older ? before : nil
            let page = try await api.directHistory(peer: peerID, before: cursor)
            try Task.checkCancellation()
            try page.validate(owner: ownerID, peer: peerID)
            guard epoch == mutationEpoch else {
                loading = false
                refreshAgain = false
                await refresh()
                return
            }
            if let cursor {
                guard page.messages.allSatisfy({ (UInt64($0.sequence) ?? .max) < (UInt64(cursor) ?? 0) })
                else { throw SocialError.invalid }
            }
            user = page.user
            state = page.state
            incomingRequest = page.incomingRequest
            readThrough = UInt64(page.readThrough) ?? 0
            if older {
                let ids = Set(messages.map(\.id))
                messages = page.messages.filter { !ids.contains($0.id) } + messages
                before = page.before
            } else {
                let first = page.messages.first.flatMap { UInt64($0.sequence) } ?? 0
                let overlap = page.messages.contains { m in messages.contains { $0.id == m.id } }
                let retained = overlap ? messages.filter { (UInt64($0.sequence) ?? 0) < first } : []
                messages = retained + page.messages
                if retained.isEmpty { before = page.before }
            }
            loaded = true
            unavailable = false
            error = nil
            if let pendingID, messages.contains(where: { $0.id == pendingID }) { clearPending() }
        } catch is CancellationError {} catch {
            if epoch == mutationEpoch { fail(error) } else { refreshAgain = true }
        }
        loading = false
        if refreshAgain && !Task.isCancelled {
            refreshAgain = false
            await refresh()
        }
    }
    /// Keep the active scroll position intact; compact only after leaving the screen.
    func compactHistory() {
        if messages.count > 40 {
            messages = Array(messages.suffix(40))
            before = messages.first?.sequence
        }
    }
    @discardableResult func send() async -> Bool {
        guard canSend else { return false }
        let input =
            pendingInput
            ?? DirectMessageInput(
                kind: attachedItemID == nil ? "text" : "workCard",
                text: draft.trimmingCharacters(in: .whitespacesAndNewlines), itemID: attachedItemID,
                spoiler: spoiler)
        let id = pendingID ?? UUID().uuidString.lowercased()
        pendingID = id
        pendingInput = input
        sending = true
        error = nil
        do {
            let receipt = try await api.sendDirect(peer: peerID, id: id, input: input)
            try Task.checkCancellation()
            guard receipt.saved, receipt.id == id else { throw SocialError.invalid }
            mutationEpoch += 1
            clearPending()
            sending = false
            await refresh()
            return true
        } catch {
            sending = false
            // A definitive rejection keeps the editable draft. Network/unknown
            // outcomes retain the same UUID and payload for a safe retry.
            if error is DirectMessageError || error is ActivityError {
                pendingID = nil
                pendingInput = nil
            }
            fail(error)
            return false
        }
    }
    private func clearPending() {
        pendingID = nil
        pendingInput = nil
        draft = ""
        attachedItemID = nil
        spoiler = false
    }
    private func fail(_ error: Error) {
        if error is CancellationError { return }
        self.error = error.localizedDescription
        if case DirectMessageError.unavailable = error {
            messages = []
            user = nil
            unavailable = true
            before = nil
        }
    }
    func decide(accepted: Bool) async -> Bool {
        guard incomingRequest, !sending else { return false }
        sending = true
        defer { sending = false }
        do {
            guard try await api.decideDirect(peer: peerID, accepted: accepted).saved else {
                throw SocialError.invalid
            }
            mutationEpoch += 1
            if !accepted {
                messages = []
                unavailable = true
            } else {
                state = "accepted"
                incomingRequest = false
            }
            return true
        } catch {
            fail(error)
            return false
        }
    }
    func markVisible(through: String) async {
        guard !unavailable, let seq = UInt64(through), seq > markedThrough else { return }
        requestedReadThrough = max(requestedReadThrough, seq)
        // SwiftUI replaces its visibility task when a newer message appears.
        // Keep one drain independent of that cancellation and coalesce visible cursors.
        if readTask == nil {
            readTask = Task { await drainReadCursor() }
        }
        await readTask?.value
    }
    private func drainReadCursor() async {
        defer { readTask = nil }
        while !unavailable && markedThrough < requestedReadThrough {
            let through = requestedReadThrough
            let epoch = mutationEpoch
            do {
                guard try await api.readDirect(peer: peerID, through: String(through)).saved else {
                    throw SocialError.invalid
                }
                markedThrough = max(markedThrough, through)
            } catch {
                if epoch == mutationEpoch { fail(error) }
                return
            }
        }
    }
    func report(_ message: DirectMessage, reason: String, alsoBlock: Bool) async -> Bool {
        guard message.senderID == peerID, !sending else { return false }
        sending = true
        defer { sending = false }
        do {
            guard
                try await api.reportDirect(
                    peer: peerID, id: message.id, reason: reason, alsoBlock: alsoBlock
                ).saved
            else { throw SocialError.invalid }
            mutationEpoch += 1
            if alsoBlock {
                unavailable = true
                messages = []
                user = nil
            } else {
                messages = messages.map {
                    $0.id == message.id
                        ? DirectMessage(
                            id: $0.id, senderID: $0.senderID, sequence: $0.sequence, createdAt: $0.createdAt,
                            kind: "removed", text: "", itemID: nil, spoiler: false) : $0
                }
            }
            return true
        } catch {
            fail(error)
            return false
        }
    }
}
