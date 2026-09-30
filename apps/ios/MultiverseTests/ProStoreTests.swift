import Foundation
import StoreKit
import Testing
@testable import Multiverse

@MainActor
private final class ProEntitlementStub: ProEntitlementClient {
    enum Failure: Error { case offline }
    var active = false
    var readCount = 0
    var restoreCount = 0
    var restoreError: (any Error)?
    var suspendRestore = false
    var restoreContinuation: CheckedContinuation<Void, Never>?
    var suspendReads = false
    var reads: [CheckedContinuation<Bool, Never>] = []
    var terminated = false
    private let stream: AsyncStream<Void>
    let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.terminated = true }
        }
    }
    func hasEntitlement() async -> Bool {
        readCount += 1
        if suspendReads { return await withCheckedContinuation { reads.append($0) } }
        return active
    }
    func restore() async throws {
        restoreCount += 1
        if suspendRestore { await withCheckedContinuation { restoreContinuation = $0 } }
        if let restoreError { throw restoreError }
    }
    func resumeRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }
    func updates() -> AsyncStream<Void> { stream }
}

@MainActor
struct ProStoreTests {
    @Test func restoreFailureIsVisibleAndRetryClearsTheError() async {
        let client = ProEntitlementStub()
        let store = ProStore(entitlements: client)
        client.active = true
        client.restoreError = ProEntitlementStub.Failure.offline
        await store.restorePurchases()
        #expect(store.purchaseError != nil)
        #expect(store.isPro)
        #expect(!store.isProcessingPurchase)
        client.restoreError = nil
        await store.restorePurchases()
        #expect(store.purchaseError == nil)
        #expect(client.restoreCount == 2)
    }

    @Test func cancellingRestoreDoesNotReportAPurchaseFailure() async {
        let client = ProEntitlementStub()
        client.restoreError = StoreKitError.userCancelled
        let store = ProStore(entitlements: client)
        await store.restorePurchases()
        #expect(store.purchaseError == nil)
        #expect(!store.isProcessingPurchase)
    }

    @Test func repeatedRestoreTapsStartOnlyOneOperation() async throws {
        let client = ProEntitlementStub()
        client.suspendRestore = true
        let store = ProStore(entitlements: client)
        let first = Task { await store.restorePurchases() }
        defer { client.resumeRestore(); first.cancel() }
        try await waitUntil { client.restoreContinuation != nil }
        await store.restorePurchases()
        #expect(client.restoreCount == 1)
        #expect(store.isProcessingPurchase)
        client.resumeRestore()
        await first.value
        #expect(!store.isProcessingPurchase)
    }

    @Test func transactionUpdatesRemoveInactiveAccessAndObserverDoesNotRetainStore() async throws {
        let client = ProEntitlementStub()
        client.active = true
        var store: ProStore? = ProStore(entitlements: client)
        weak let weakStore = store
        client.continuation.yield(())
        try await waitUntil { store?.isPro == true }
        client.active = false
        client.continuation.yield(())
        try await waitUntil { store?.isPro == false }
        store = nil
        try await waitUntil { weakStore == nil && client.terminated }
    }

    @Test func olderEntitlementReadCannotRestoreAccessAfterANewerRevocation() async throws {
        let client = ProEntitlementStub()
        client.active = true
        let store = ProStore(entitlements: client)
        await store.refreshEntitlement()
        client.suspendReads = true
        let earlier = Task { await store.refreshEntitlement() }
        try await waitUntil { client.reads.count == 1 }
        let later = Task { await store.refreshEntitlement() }
        try await waitUntil { client.reads.count == 2 }
        client.reads[1].resume(returning: false)
        await later.value
        client.reads[0].resume(returning: true)
        await earlier.value
        #expect(!store.isPro)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}
