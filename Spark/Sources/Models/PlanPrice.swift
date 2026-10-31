import Foundation

/// What the Claude plan costs per month, in dollars without tax like the API cost estimate.
enum PlanPrice {
    static let daysPerMonth = 365.25 / 12

    /// Monthly list prices from claude.com/pricing. Team and Enterprise depend on the seat, so
    /// they only count once the user enters a price.
    static func listPrice(for tier: AccountTier) -> Double? {
        switch tier.plan {
        case "Pro": 20
        case "Max": 100
        case "Ultra": 200
        default: nil
        }
    }

    /// `setting` is the price entered in Settings, 0 while the user keeps the list price.
    static func monthly(setting: Double, tier: AccountTier) -> Double? {
        setting > 0 ? setting : listPrice(for: tier)
    }

    /// The calendar days a Statistics period's cost covers. The scan keeps the whole cutoff day,
    /// so 7d spans eight of them. All time starts at the first day with tokens.
    static func days(for period: StatsPeriod, dayTokens: [String: Int], now: Date, calendar: Calendar) -> Int? {
        switch period {
        case .today: 1
        case .week: 8
        case .month: 31
        case .all:
            dayTokens.filter { $0.value > 0 }.keys.min()
                .flatMap { date(fromDayKey: $0, calendar: calendar) }
                .map { PeriodReport.dayCount(from: $0, to: now, calendar: calendar) }
        }
    }

    private static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: key)
    }
}

/// The API cost of a stretch of days against the part of the plan price those days take up.
struct PlanValue: Equatable {
    let multiple: Double
    let planShare: Double
    let days: Int
    let monthlyPrice: Double

    init?(apiCost: Double, monthlyPrice: Double?, days: Int?) {
        guard let monthlyPrice, monthlyPrice > 0, let days, days > 0 else { return nil }
        planShare = monthlyPrice * Double(days) / PlanPrice.daysPerMonth
        multiple = apiCost / planShare
        self.days = days
        self.monthlyPrice = monthlyPrice
    }
}
