import StoreKit

/// Assinatura Multiverse PRO via StoreKit 2. Testável no Simulator com
/// `Configuration/Products.storekit` (Xcode → Scheme → Options → StoreKit Configuration) —
/// não precisa de App Store Connect pra isso. Não passa pelo `MultiverseRepository`:
/// direito de compra é uma preocupação de sistema (como `AuthRepository`), não conteúdo.
@MainActor
@Observable
final class ProStore {
    static let monthlyID = "com.multiverse.pro.monthly"
    static let annualID = "com.multiverse.pro.annual"

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoadingProducts = true
    var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in await self?.observeTransactionUpdates() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.annualID])
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Não deu pra carregar os planos agora."
        }
        await refreshEntitlement()
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Não deu pra concluir a compra."
        }
    }

    func restorePurchases() async {
        // Nome completo pra não colidir com o `AppStore` (nosso store de conteúdo) do módulo.
        try? await StoreKit.AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyID || transaction.productID == Self.annualID,
               transaction.revocationDate == nil {
                isPro = true
                return
            }
        }
        isPro = false
    }

    private func observeTransactionUpdates() async {
        for await update in StoreKit.Transaction.updates {
            if case .verified(let transaction) = update { await transaction.finish() }
            await refreshEntitlement()
        }
    }
}
