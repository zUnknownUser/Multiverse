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
    private(set) var annualTrial: ProTrial?
    @ObservationIgnored private var productRequestID = UUID()
    var annualSavingsPercent: Int? {
        guard let annual = products.first(where: { $0.id == Self.annualID }),
              let monthly = products.first(where: { $0.id == Self.monthlyID }) else { return nil }
        return ProOfferPolicy.annualSavingsPercent(annual: ProPlanPrice(annual), monthly: ProPlanPrice(monthly))
    }
    private(set) var isPro = false
    private(set) var isLoadingProducts = true
    private(set) var isProcessingPurchase = false
    private let entitlements: any ProEntitlementClient
    @ObservationIgnored private var entitlementRequestID = UUID()
    var purchaseError: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(entitlements: (any ProEntitlementClient)? = nil) {
        let client = entitlements ?? StoreKitProEntitlementClient(productIDs: [Self.monthlyID, Self.annualID])
        self.entitlements = client
        let updates = client.updates()
        updatesTask = Task { [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { break }
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        let requestID = UUID()
        productRequestID = requestID
        isLoadingProducts = true
        annualTrial = nil
        purchaseError = nil
        defer { if requestID == productRequestID { isLoadingProducts = false } }
        do {
            let loaded = try await Product.products(for: [Self.monthlyID, Self.annualID])
                .sorted { $0.price < $1.price }
            guard !Task.isCancelled, requestID == productRequestID else { return }
            products = loaded
        } catch {
            guard !Task.isCancelled, requestID == productRequestID else { return }
            products = []
            purchaseError = L10n.text("Não deu pra carregar os planos agora.")
        }
        await refreshEntitlement()
    }

    func purchase(_ product: Product) async {
        guard !isProcessingPurchase, !isLoadingProducts else { return }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await refreshEntitlement()
                    await transaction.finish()
                } else {
                    purchaseError = L10n.text("Não deu pra concluir a compra.")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = L10n.text("Não deu pra concluir a compra.")
        }
    }

    func restorePurchases() async {
        guard !isProcessingPurchase else { return }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }
        purchaseError = nil
        do { try await entitlements.restore() }
        catch StoreKitError.userCancelled { /* Closing the App Store sheet isn't a failure. */ }
        catch { purchaseError = L10n.text("Não deu pra restaurar as compras. Tente novamente.") }
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        let requestID = UUID()
        entitlementRequestID = requestID
        annualTrial = nil
        let active = await entitlements.hasEntitlement()
        guard !Task.isCancelled, requestID == entitlementRequestID else { return }
        isPro = active
        guard let subscription = products.first(where: { $0.id == Self.annualID })?.subscription,
              let offer = subscription.introductoryOffer else { return }
        let eligible = await subscription.isEligibleForIntroOffer
        guard !Task.isCancelled, requestID == entitlementRequestID else { return }
        annualTrial = ProOfferPolicy.trial(isEligible: eligible, paymentMode: offer.paymentMode,
                                           unit: offer.period.unit, value: offer.period.value, periodCount: offer.periodCount)
    }
}
