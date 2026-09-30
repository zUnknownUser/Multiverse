import Foundation
import StoreKit
import Testing
@testable import Multiverse

struct ProOfferPolicyTests {
    private func price(_ amount: String, currency: String = "BRL", unit: Product.SubscriptionPeriod.Unit, count: Int = 1) throws -> ProPlanPrice {
        ProPlanPrice(amount: try #require(Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))), currency: currency, unit: unit, periodCount: count)
    }

    @Test func annualSavingsUseConfiguredPricesAndNeverRoundUp() throws {
        let monthly = try price("12.90", unit: .month)
        let annual = try price("99.90", unit: .year)
        #expect(ProOfferPolicy.annualSavingsPercent(annual: annual, monthly: monthly) == 35)
        #expect(ProOfferPolicy.annualSavingsPercent(annual: try price("100", unit: .year), monthly: try price("10", unit: .month)) == 16)
        #expect(ProOfferPolicy.annualSavingsPercent(annual: try price("0.299", unit: .year), monthly: try price("0.025", unit: .month)) == nil)
    }

    @Test func incomparableOrNonDiscountedPlansDoNotAdvertiseSavings() throws {
        let monthly = try price("10", unit: .month)
        for annual in [
            try price("120", unit: .year), try price("121", unit: .year),
            try price("0", unit: .year), try price("-1", unit: .year),
            try price("99", currency: "USD", unit: .year),
            try price("99", unit: .month), try price("99", unit: .year, count: 2),
            ProPlanPrice(amount: .nan, currency: "BRL", unit: .year, periodCount: 1)
        ] {
            #expect(ProOfferPolicy.annualSavingsPercent(annual: annual, monthly: monthly) == nil)
        }
        #expect(ProOfferPolicy.annualSavingsPercent(annual: try price("99", unit: .year), monthly: try price("10", unit: .month, count: 3)) == nil)
    }

    @Test func freeTrialRequiresBothEligibilityAndAFreeOffer() {
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .week, value: 1, periodCount: 1) == ProTrial(unit: .day, count: 7))
        #expect(ProOfferPolicy.trial(isEligible: false, paymentMode: .freeTrial, unit: .week, value: 1, periodCount: 1) == nil)
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .payAsYouGo, unit: .week, value: 1, periodCount: 1) == nil)
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .payUpFront, unit: .week, value: 1, periodCount: 1) == nil)
    }

    @Test func trialDurationUsesOfferUnitsAndRejectsInvalidLengths() {
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .day, value: 3, periodCount: 2) == ProTrial(unit: .day, count: 6))
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .month, value: 1, periodCount: 1) == ProTrial(unit: .month, count: 1))
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .year, value: 1, periodCount: 1) == ProTrial(unit: .year, count: 1))
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .day, value: 0, periodCount: 1) == nil)
        #expect(ProOfferPolicy.trial(isEligible: true, paymentMode: .freeTrial, unit: .week, value: Int.max, periodCount: 1) == nil)
    }

    @Test func trialLabelsUseSingularAndPluralInPortugueseAndEnglish() {
        #expect(L10n.format("pro.trialDays", arguments: [7], preferredLanguages: ["pt-BR"]) == "TESTAR 7 DIAS GRÁTIS")
        #expect(L10n.format("pro.trialDays", arguments: [7], preferredLanguages: ["en"]) == "TRY 7 DAYS FREE")
        #expect(L10n.format("pro.trialMonths", arguments: [1], preferredLanguages: ["pt-BR"]) == "TESTAR 1 MÊS GRÁTIS")
        #expect(L10n.format("pro.trialMonths", arguments: [1], preferredLanguages: ["en"]) == "TRY 1 MONTH FREE")
        #expect(L10n.format("pro.trialYears", arguments: [2], preferredLanguages: ["en"]) == "TRY 2 YEARS FREE")
    }
}
