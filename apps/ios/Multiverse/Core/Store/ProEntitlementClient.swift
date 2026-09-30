import StoreKit

@MainActor
protocol ProEntitlementClient {
    func hasEntitlement() async -> Bool
    func restore() async throws
    func updates() -> AsyncStream<Void>
}

@MainActor
final class StoreKitProEntitlementClient: ProEntitlementClient {
    private let productIDs: Set<String>
    init(productIDs: Set<String>) { self.productIDs = productIDs }

    func hasEntitlement() async -> Bool {
        // StoreKit includes subscriptions in their billing grace period here.
        // Filtering expirationDate ourselves would incorrectly remove that access.
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func restore() async throws { try await StoreKit.AppStore.sync() }

    func updates() -> AsyncStream<Void> {
        let productIDs = productIDs
        return AsyncStream { continuation in
            let task = Task {
                for await update in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    if case .verified(let transaction) = update, productIDs.contains(transaction.productID) {
                        await transaction.finish()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
