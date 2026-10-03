import Foundation
import Testing
@testable import Multiverse

@MainActor private final class OrdersStub: ReadingOrdersAPI {
    var order = ReadingOrder(id:"marvel-event-highlights",uni:"marvel",title:"Marvel",by:"multiverse",votes:0,steps:["m-fenix","m-civil","m-secret"],description:"An editorial selection",followers:0,following:false,voted:false)
    var version=0
    var requests:[ReadingOrderMutation]=[]
    var failure:(any Error)?
    var readFailure=false
    var badReceipt=false
    var readHook:(() async throws -> ReadingOrdersSnapshot)?
    func page() -> ReadingOrdersSnapshot { .init(version:version,locale:"en",orders:[order]) }
    func fetchReadingOrders() async throws -> ReadingOrdersSnapshot {
        if readFailure { throw AuthError.networkUnavailable }
        if let readHook { return try await readHook() }
        return page()
    }
    func mutateReadingOrder(_ input:ReadingOrderMutation) async throws -> ReadingOrderReceipt {
        requests.append(input)
        if let failure { throw failure }
        if input.action == "following" { order.following=input.enabled; order.followers=input.enabled ? 1 : 0 }
        else { order.voted=input.enabled; order=ReadingOrder(id:order.id,uni:order.uni,title:order.title,by:order.by,votes:input.enabled ? 1 : 0,steps:order.steps,description:order.description,followers:order.followers,following:order.following,voted:order.voted) }
        version=max(version,input.version+1)
        return .init(mutationID:badReceipt ? "wrong" : input.mutationID,appliedVersion:input.version+1,state:page())
    }
}
@Suite(.serialized) @MainActor struct ReadingOrdersTests {
    @Test func newAccountDoesNotExposeDemoOrdersOrEngagement() async {
        let api=OrdersStub(), store=AppStore(accountAPI:AccountAPIClient(),readingOrdersAPI:api)
        #expect(store.readingOrders.isEmpty && !store.isOrderVoted(api.order.id) && !store.isFollowingOrder(api.order.id))
        await store.readingOrderStore?.refresh()
        #expect(store.readingOrders.count == 1 && store.orderVoteCount(store.readingOrders[0]) == 0)
        #expect(!Route.order(api.order.id).isDemonstration)
        #expect(AppStore(accountAPI:AccountAPIClient(),readingOrdersAPI:OrdersStub()).readingOrders.isEmpty)
    }
    @Test func progressUsesDistinctDiaryWorksAndIgnoresSeenOverrides() async {
        let api=OrdersStub(), store=AppStore(readingOrdersAPI:api)
        await store.bootstrap(); await store.readingOrderStore?.refresh()
        store.diary=[]; store.checks=["m-civil":true,"m-fenix":true]
        #expect(store.orderProgress(api.order).done == 0)
        store.diary=[DiaryEntry(itemId:"m-civil",loggedAt:.now,rating:4),DiaryEntry(itemId:"m-civil",loggedAt:.now,rating:5,rewatch:true)]
        #expect(store.orderProgress(api.order).done == 1 && store.orderProgress(api.order).total == 3)
        store.checks["m-civil"]=false
        #expect(store.isOrderStepRead("m-civil"))
        #expect(api.order.steps.first { !store.isOrderStepRead($0) } == "m-fenix")
        store.diary=[]; #expect(store.orderProgress(api.order).done == 0)
    }
    @Test func followAndVoteChangeOnlyAfterReceiptAndNeverDoubleCount() async {
        let api=OrdersStub(), store=AppStore(readingOrdersAPI:api); let remote=store.readingOrderStore!
        await remote.refresh(); await remote.toggle(api.order.id,action:"following")
        #expect(store.isFollowingOrder(api.order.id) && remote.orders[0].followers == 1)
        await remote.toggle(api.order.id,action:"voted")
        #expect(store.isOrderVoted(api.order.id) && store.orderVoteCount(remote.orders[0]) == 1)
        await remote.toggle(api.order.id,action:"following")
        #expect(!store.isFollowingOrder(api.order.id) && store.isOrderVoted(api.order.id))
    }
    @Test func lostResponseRetainsConfirmedStateAndRetryIdentity() async {
        let api=OrdersStub(), remote=ReadingOrdersStore(api:api); await remote.refresh()
        api.failure=AuthError.networkUnavailable;await remote.toggle(api.order.id,action:"following")
        let pending=remote.pending;#expect(pending != nil && remote.orders[0].following == false && !remote.canMutate)
        api.failure=nil;await remote.retry()
        #expect(api.requests.count == 2 && api.requests[0] == api.requests[1] && remote.pending == nil && remote.orders[0].following == true)
    }
    @Test func mismatchedReceiptRetainsTheSamePendingOperation() async {
        let api=OrdersStub(),remote=ReadingOrdersStore(api:api);await remote.refresh();api.badReceipt=true
        await remote.toggle(api.order.id,action:"voted")
        #expect(remote.orders[0].votes == 0 && remote.pending != nil && remote.error != nil)
        api.badReceipt=false;await remote.retry()
        #expect(remote.orders[0].votes == 1 && api.requests[0].mutationID == api.requests[1].mutationID)
    }
    @Test func staleDeviceRefreshesWithoutReplayingItsChoice() async {
        let api=OrdersStub(), remote=ReadingOrdersStore(api:api);await remote.refresh()
        api.version=2;api.order.following=true;api.failure=ReadingOrdersError.stale
        await remote.toggle(api.order.id,action:"voted")
        #expect(remote.version == 2 && remote.orders[0].following == true && remote.orders[0].voted == false && remote.pending == nil && remote.error != nil)
    }
    @Test func failedRefreshKeepsKnownOrdersAndOldResponsesCannotOverwriteWrites() async {
        let api=OrdersStub(),remote=ReadingOrdersStore(api:api);await remote.refresh()
        api.readFailure=true;await remote.refresh();#expect(remote.orders.count == 1 && remote.error != nil)
        api.readFailure=false;let stale=api.page()
        var continuation:CheckedContinuation<ReadingOrdersSnapshot,Never>?
        api.readHook={await withCheckedContinuation {continuation=$0}}
        let load=Task{await remote.refresh()};while continuation == nil {await Task.yield()}
        await remote.toggle(api.order.id,action:"following")
        continuation?.resume(returning:stale);await load.value
        #expect(remote.version == 1 && remote.orders[0].following == true)
    }
    @Test func invalidCatalogCannotInstallDuplicateStepsOrFakeNegativeCounts() throws {
        let api=OrdersStub();let duplicate=ReadingOrder(id:api.order.id,uni:"marvel",title:"Title",by:"multiverse",votes:0,steps:["m-civil","m-civil"],description:"Description",followers:0,following:false,voted:false)
        #expect(throws:ReadingOrdersError.invalid){try ReadingOrdersSnapshot(version:0,locale:"en",orders:[duplicate]).validate()}
        api.order.followers = -1
        #expect(throws:ReadingOrdersError.invalid){try api.page().validate()}
    }
    @Test func interruptedWriteKeepsAnAccessibleRetryAfterReturningToForeground() async {
        let api=OrdersStub(), remote=ReadingOrdersStore(api:api);await remote.refresh()
        api.failure=CancellationError();await remote.toggle(api.order.id,action:"following")
        #expect(remote.pending != nil && remote.error != nil && remote.orders[0].following == false)
        api.failure=nil;await remote.refresh();#expect(remote.error != nil)
        await remote.retry();#expect(remote.pending == nil && remote.orders[0].following == true)
    }

    @Test func outdatedReadFailureCannotReplaceSuccessfulMutationWithAnError() async {
        let api = OrdersStub(), remote = ReadingOrdersStore(api: api); await remote.refresh()
        var continuation: CheckedContinuation<ReadingOrdersSnapshot, any Error>?
        api.readHook = { try await withCheckedThrowingContinuation { continuation = $0 } }
        let load = Task { await remote.refresh() }
        while continuation == nil { await Task.yield() }
        await remote.toggle(api.order.id, action: "following")
        continuation?.resume(throwing: AuthError.networkUnavailable); await load.value
        #expect(remote.orders[0].following == true && remote.error == nil)
    }

}
