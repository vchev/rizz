import Foundation

/// The paywall's price maths, kept pure so it can be tested.
///
/// Vanessa, Nov 7: lead with the lower number. Both plans are shown per week
/// ($4.99/wk and $1.90/wk), and the full yearly price stays visible, as Apple requires.
enum PlanPricing {
    /// The yearly price as a weekly amount, rounded down to the cent (99.00 -> 1.90).
    static func perWeek(yearly: Decimal) -> Decimal {
        var weekly = yearly / 52
        var rounded = Decimal()
        NSDecimalRound(&rounded, &weekly, 2, .down)
        return rounded
    }

    /// Whole percent saved by paying yearly instead of weekly (4.99 vs 99.00 -> 61).
    /// Rounded down, so the claim is never larger than the real saving.
    static func savingPercent(weekly: Decimal, yearly: Decimal) -> Int {
        guard weekly > 0 else { return 0 }
        let fullYear = weekly * 52
        guard yearly < fullYear else { return 0 }
        let saving = NSDecimalNumber(decimal: (fullYear - yearly) / fullYear * 100).doubleValue
        return Int(saving.rounded(.down))
    }

    /// "7-day" for a 7-day period, "1-week" for a week, used in "Start 7-day free trial".
    static func trialLength(value: Int, unit: TrialUnit) -> String {
        switch unit {
        case .day: return "\(value)-day"
        case .week: return value == 1 ? "7-day" : "\(value * 7)-day"
        case .month: return "\(value)-month"
        case .year: return "\(value)-year"
        }
    }

    enum TrialUnit { case day, week, month, year }
}
