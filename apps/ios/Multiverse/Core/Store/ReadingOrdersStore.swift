import Foundation
import Observation

@MainActor @Observable final class ReadingOrdersStore {
    private let api: any ReadingOrdersAPI
    private(set) var orders: [ReadingOrder] = []
    private(set) var version: Int?
    private(set) var loading = false
    private(set) var mutating = false
    private(set) var error: String?
    private(set) var pending: ReadingOrderMutation?
    private var epoch = 0
    private var refreshID: UUID?
    var canMutate: Bool { version != nil && !mutating && pending == nil }
    init(api: any ReadingOrdersAPI) { self.api = api }
    private func apply(_ page: ReadingOrdersSnapshot) throws {
        try page.validate()
        guard page.version >= (version ?? 0) else { throw ReadingOrdersError.invalid }
        orders = page.orders; version = page.version
    }
    func refresh(force: Bool = false) async {
        guard force || (!loading && !mutating) else { return }; loading = true
        let revision = epoch; let id = UUID(); refreshID = id
        defer { if refreshID == id { loading = false } }
        do {
            let page = try await api.fetchReadingOrders()
            try Task.checkCancellation(); guard revision == epoch && refreshID == id else { return }
            try apply(page)
            if pending == nil { error = nil }
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    func toggle(_ id: String, action: String) async {
        guard canMutate, let order = orders.first(where: { $0.id == id }), let version, ["following", "voted"].contains(action) else { return }
        let enabled = !(action == "following" ? order.following! : order.voted!)
        pending = ReadingOrderMutation(mutationID: UUID().uuidString.lowercased(), version: version, orderID: id, action: action, enabled: enabled)
        await retry()
    }
    func retry() async {
        guard !mutating, let input = pending else { return }
        mutating = true; error = nil; epoch += 1
        defer { mutating = false }
        do {
            let receipt = try await api.mutateReadingOrder(input)
            try Task.checkCancellation()
            guard receipt.mutationID == input.mutationID, receipt.appliedVersion == input.version + 1, receipt.state.version >= receipt.appliedVersion else { throw ReadingOrdersError.invalid }
            try apply(receipt.state)
            pending = nil
        } catch is CancellationError { self.error = ReadingOrdersError.conflict.localizedDescription }
        catch {
            self.error = error.localizedDescription
            if let failure = error as? ReadingOrdersError, failure != .invalid {
                pending = nil
                if failure == .stale || failure == .unavailable { await refresh(force: true); self.error = error.localizedDescription }
            }
        }
    }
}
