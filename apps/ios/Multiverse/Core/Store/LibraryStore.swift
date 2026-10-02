import Foundation
import Observation

/// Per-account state. Mutations are acknowledged before changing UI; ambiguous retries keep their identity.
@MainActor @Observable final class LibraryStore {
    private let api: any LibraryAPI
    private(set) var snapshot: LibrarySnapshot?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var pending: LibraryMutation?
    var canMutate: Bool { snapshot != nil && !busy && pending == nil }
    var lists: [PersonalList] { snapshot?.lists ?? [] }
    var wantedIDs: [String] { snapshot?.wantedIDs ?? [] }
    var favoriteIDs: [String] { snapshot?.favoriteIDs ?? [] }
    init(api: any LibraryAPI) { self.api = api }
    func refresh() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await api.fetchLibrary(); try Task.checkCancellation(); try result.validate()
            guard result.version >= (snapshot?.version ?? 0) else { throw LibraryError.invalid }
            snapshot = result
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func change(_ action: String, listID: String? = nil, itemID: String? = nil, enabled: Bool? = nil, title: String? = nil, description: String? = nil) async -> Bool {
        guard canMutate, let snapshot else { return false }
        pending = .init(mutationID: UUID().uuidString.lowercased(), version: snapshot.version, action: action, listID: listID, itemID: itemID, enabled: enabled, title: title, description: description)
        return await retry()
    }
    @discardableResult
    func retry() async -> Bool {
        guard !busy, let input = pending else { return false }; busy = true; error = nil
        do {
            let receipt = try await api.mutateLibrary(input)
            try receipt.state.validate()
            guard receipt.mutationID == input.mutationID, receipt.appliedVersion == input.version + 1,
                  receipt.state.version >= receipt.appliedVersion, receipt.state.version >= (snapshot?.version ?? 0) else { throw LibraryError.invalid }
            snapshot = receipt.state; pending = nil; busy = false; return true
        } catch {
            let failure = error
            // Definitive rejections never saved the operation; ambiguous transport/decoding failures retain it.
            if let reason = error as? LibraryError, reason != .invalid {
                pending = nil; busy = false
                await refresh()
            } else if error as? ActivityError == .itemUnavailable || error as? AuthError == .tooManyRequests || error as? SocialError == .invalid {
                pending = nil; busy = false
            }
            self.error = failure.localizedDescription; busy = false; return false
        }
    }
}
