import Foundation
import Testing
@testable import Multiverse

@MainActor private final class LibraryStub: LibraryAPI {
    var state = LibrarySnapshot(version: 0, wantedIDs: [], favoriteIDs: [], lists: [])
    var writes: [LibraryMutation] = []
    var receipts: [String: LibraryReceipt] = [:]
    var loseResponse = false
    var reject: LibraryError?
    var readFailure = false
    func fetchLibrary() async throws -> LibrarySnapshot {
        if readFailure { throw AuthError.networkUnavailable }
        return state
    }
    func mutateLibrary(_ input: LibraryMutation) async throws -> LibraryReceipt {
        writes.append(input)
        if let reject { throw reject }
        if let receipt = receipts[input.mutationID] { return .init(mutationID: input.mutationID, appliedVersion: receipt.appliedVersion, state: state) }
        guard input.version == state.version else { throw LibraryError.stale }
        var wanted = state.wantedIDs, favorites = state.favoriteIDs, lists = state.lists
        if let item = input.itemID {
            if input.action == "wanted" { wanted = input.enabled == true ? [item] : [] }
            if input.action == "favorite" { favorites = input.enabled == true ? [item] : [] }
        }
        if input.action == "create_list" { lists.append(.init(id: input.listID!, title: input.title!, description: input.description!, itemIDs: [], createdAt: .now, updatedAt: .now)) }
        state = .init(version: state.version + 1, wantedIDs: wanted, favoriteIDs: favorites, lists: lists)
        let receipt = LibraryReceipt(mutationID: input.mutationID, appliedVersion: state.version, state: state)
        receipts[input.mutationID] = receipt
        if loseResponse { throw AuthError.networkUnavailable }
        return receipt
    }
}
@Suite(.serialized) @MainActor struct LibraryTests {
    @Test func emptyLibraryIsRealAndFailureNeverCreatesSampleLists() async {
        let api = LibraryStub(), library = LibraryStore(api: LibraryStub())
        await library.refresh(); #expect(library.lists.isEmpty && library.canMutate)
        api.readFailure = true
        let failed = LibraryStore(api: api); await failed.refresh()
        #expect(failed.snapshot == nil && !failed.canMutate && failed.error != nil)
    }
    @Test func failedResponsePreservesRetryIdentityAndDoesNotCreateAnotherList() async {
        let api = LibraryStub(), id = UUID().uuidString.lowercased()
        let library = LibraryStore(api: api); await library.refresh(); api.loseResponse = true
        #expect(await library.change("create_list", listID: id, title: "My list", description: "") == false)
        #expect(library.lists.isEmpty && library.pending != nil && !library.canMutate)
        #expect(await library.change("wanted", itemID: "m-civil", enabled: true) == false)
        #expect(await library.retry())
        #expect(library.lists.map(\.id) == [id] && library.pending == nil)
        #expect(api.writes.count == 2 && api.writes[0].mutationID == api.writes[1].mutationID)
    }
    @Test func staleDeviceIsRefreshedAndRequiresANewUserAction() async {
        let api = LibraryStub()
        let active = LibraryStore(api: api); await active.refresh()
        api.state = .init(version: 7, wantedIDs: ["m-civil"], favoriteIDs: [], lists: [])
        #expect(await active.change("favorite", itemID: "m-civil", enabled: true) == false)
        #expect(active.snapshot?.version == 7 && active.pending == nil && active.error != nil)
        #expect(await active.change("favorite", itemID: "m-civil", enabled: true))
        #expect(api.writes[1].version == 7 && api.writes[0].mutationID != api.writes[1].mutationID)
        #expect(active.wantedIDs == ["m-civil"] && active.favoriteIDs == ["m-civil"])
    }
    @Test func retryAcceptsNewerStateWithoutRevertingAnotherDevice() async {
        let api = LibraryStub()
        let active = LibraryStore(api: api); await active.refresh(); api.loseResponse = true
        #expect(await active.change("wanted", itemID: "m-civil", enabled: true) == false)
        api.state = .init(version: 2, wantedIDs: [], favoriteIDs: ["m-civil"], lists: [])
        #expect(await active.retry())
        #expect(active.wantedIDs.isEmpty && active.favoriteIDs == ["m-civil"] && active.snapshot?.version == 2)
    }
    @Test func failedAndOlderRefreshKeepConfirmedState() async {
        let api = LibraryStub()
        let active = LibraryStore(api: api); await active.refresh()
        #expect(await active.change("wanted", itemID: "m-civil", enabled: true))
        api.readFailure = true; await active.refresh()
        #expect(active.wantedIDs == ["m-civil"])
        api.readFailure = false; api.state = .init(version: 0, wantedIDs: [], favoriteIDs: [], lists: [])
        await active.refresh(); #expect(active.wantedIDs == ["m-civil"] && active.error != nil)
    }
    @Test func anotherAccountStartsWithNoPrivateLibraryAndDemoRoutesAreHidden() async {
        let api = LibraryStub(), a = LibraryStore(api: LibraryStub())
        await a.refresh()
        let b = LibraryStore(api: api)
        #expect(b.snapshot == nil && b.wantedIDs.isEmpty && b.lists.isEmpty)
        let store = AppStore(accountAPI: AccountAPIClient(), libraryAPI: api)
        #expect(!store.showsDemoFeatures)
        for route in [Route.messages, .club("demo"), .wrapped, .room("demo"), .theories, .pro] { store.push(route) }
        #expect(store.homePath.isEmpty)
        store.push(.library); #expect(store.homePath == [.library])
        store.goToTab(.library); store.push(.item("m-civil")); #expect(store.libraryPath == [.item("m-civil")])
        store.goToTab(.library); #expect(store.libraryPath.isEmpty)
    }
}
