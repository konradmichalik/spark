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

    /// Midnight of the first of `days` calendar days that end today.
    static func start(days: Int, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
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
    /// Nil when extra usage is billed in dollars but the history does not cover the period.
    let extraSpend: Double?

    init?(apiCost: Double, monthlyPrice: Double?, days: Int?, extraSpend: Double? = 0) {
        guard let monthlyPrice, monthlyPrice > 0, let days, days > 0 else { return nil }
        planShare = monthlyPrice * Double(days) / PlanPrice.daysPerMonth
        self.extraSpend = extraSpend.map { max($0, 0) }
        multiple = apiCost / (planShare + (self.extraSpend ?? 0))
        self.days = days
        self.monthlyPrice = monthlyPrice
    }
}

/// Extra usage spent in a stretch of time, from the running monthly totals the history records.
enum ExtraUsageSpend {
    /// `history` is in time order, as `AppState` records it. Nil when it starts after `start`, since
    /// the spend before its first snapshot is unknown. A snapshot without a spend is skipped: it can
    /// be a response without `extra_usage` as well as a month with nothing spent.
    static func spent(in history: [UsageSnapshot], from start: Date, to end: Date) -> Double? {
        guard let first = history.first, first.timestamp <= start else { return nil }
        var previous = history.last { $0.timestamp <= start && $0.extraUsageSpend != nil }?.extraUsageSpend ?? 0
        var total = 0.0
        for snapshot in history where snapshot.timestamp > start && snapshot.timestamp <= end {
            guard let current = snapshot.extraUsageSpend else { continue }
            // A lower total means the monthly spend reset, so all of the new total is new spend.
            total += current >= previous ? current - previous : current
            previous = current
        }
        return total
    }
}
