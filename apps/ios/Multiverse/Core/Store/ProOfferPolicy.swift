import Foundation
import StoreKit

struct ProPlanPrice {
    let amount: Decimal
    let currency: String
    let unit: Product.SubscriptionPeriod.Unit?
    let periodCount: Int
}

extension ProPlanPrice {
    init(_ product: Product) {
        amount = product.price
        currency = product.priceFormatStyle.currencyCode
        unit = product.subscription?.subscriptionPeriod.unit
        periodCount = product.subscription?.subscriptionPeriod.value ?? 0
    }
}

struct ProTrial: Equatable {
    enum Unit: Equatable { case day, month, year }
    let unit: Unit
    let count: Int

    var buttonTitle: String {
        switch unit {
        case .day: return L10n.format("pro.trialDays", count)
        case .month: return L10n.format("pro.trialMonths", count)
        case .year: return L10n.format("pro.trialYears", count)
        }
    }
}

/// Offer text must describe the actual StoreKit offer and comparable billing periods.
enum ProOfferPolicy {
    static func trial(
        isEligible: Bool, paymentMode: Product.SubscriptionOffer.PaymentMode,
        unit: Product.SubscriptionPeriod.Unit, value: Int, periodCount: Int
    ) -> ProTrial? {
        guard isEligible, paymentMode == .freeTrial, value > 0, periodCount > 0 else { return nil }
        let (quantity, overflow) = value.multipliedReportingOverflow(by: periodCount)
        guard !overflow else { return nil }
        switch unit {
        case .day: return ProTrial(unit: .day, count: quantity)
        case .week:
            let (days, overflow) = quantity.multipliedReportingOverflow(by: 7)
            return overflow ? nil : ProTrial(unit: .day, count: days)
        case .month: return ProTrial(unit: .month, count: quantity)
        case .year: return ProTrial(unit: .year, count: quantity)
        @unknown default: return nil
        }
    }

    static func annualSavingsPercent(annual: ProPlanPrice, monthly: ProPlanPrice) -> Int? {
        guard annual.unit == .year, annual.periodCount == 1,
              monthly.unit == .month, monthly.periodCount == 1,
              annual.currency == monthly.currency,
              !annual.amount.isNaN, !monthly.amount.isNaN,
              annual.amount > 0, monthly.amount > 0 else { return nil }
        let monthlyYear = monthly.amount * 12
        guard !monthlyYear.isNaN, annual.amount < monthlyYear else { return nil }
        var percentage = (1 - annual.amount / monthlyYear) * 100
        guard !percentage.isNaN else { return nil }
        var rounded = Decimal()
        // Never advertise a larger saving than the actual price difference.
        NSDecimalRound(&rounded, &percentage, 0, .down)
        let result = NSDecimalNumber(decimal: rounded).intValue
        return result > 0 ? result : nil
    }
}
