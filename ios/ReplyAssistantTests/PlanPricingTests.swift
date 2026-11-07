import XCTest

final class PlanPricingTests: XCTestCase {
    func testYearlyShownPerWeek() {
        XCTAssertEqual(PlanPricing.perWeek(yearly: 99), Decimal(string: "1.90"))
    }

    func testSavingIsRoundedDown() {
        // 4.99 x 52 = 259.48; 99 is 61.85% less, so the paywall says 61%, never 62%.
        XCTAssertEqual(PlanPricing.savingPercent(weekly: Decimal(string: "4.99")!, yearly: 99), 61)
    }

    func testNoSavingWhenYearlyIsNotCheaper() {
        XCTAssertEqual(PlanPricing.savingPercent(weekly: 1, yearly: 60), 0)
        XCTAssertEqual(PlanPricing.savingPercent(weekly: 0, yearly: 99), 0)
    }

    func testTrialLength() {
        XCTAssertEqual(PlanPricing.trialLength(value: 1, unit: .week), "7-day")
        XCTAssertEqual(PlanPricing.trialLength(value: 3, unit: .day), "3-day")
    }
}
