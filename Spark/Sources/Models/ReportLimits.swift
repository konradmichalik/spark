import Foundation

/// One provider's limits over the report's range (docs/design/rules.md, "Windows", Limits): each
/// day's session peak and weekly value, and the summaries beside them.
struct ReportLimits: Equatable, Sendable {
    static let noHistoryText = "No limit history for that period."

    let provider: ReportProvider
    /// One per calendar day of the range, as `PaceDaySeries` builds them.
    let days: [PaceDay]
    /// The highest weekly value of the range. `nil` without a weekly window in it.
    let weekMax: Double?
    /// Days whose session peak reached 100 %.
    let daysAtLimit: Int
    /// "up to 100% · 4× at limit", for the overview row.
    let summary: String
    /// "Week up to 100% · 4 days at the session limit", for the Limits screen.
    let longSummary: String

    /// False when no snapshot falls into the range: history reaches back only about 30 days.
    var hasHistory: Bool { days.contains(where: \.hasData) }

    static func make(
        provider: ReportProvider, snapshots: [UsageSnapshot], start: Date, end: Date,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> ReportLimits {
        let days = PaceDaySeries.build(snapshots: snapshots, start: start, end: end, calendar: calendar)
        let weekMax = days.compactMap(\.weeklyUtilization).max()
        let atLimit = days.filter { ($0.sessionUtilization ?? 0) >= 100 }.count
        guard days.contains(where: \.hasData) else {
            return ReportLimits(
                provider: provider, days: days, weekMax: nil, daysAtLimit: 0, summary: noHistoryText, longSummary: noHistoryText
            )
        }
        let week = weekMax.map { UsageFormat.percent($0, locale: locale) }
        let short = [week.map { "up to \($0)" }, atLimit > 0 ? "\(atLimit)\u{00D7} at limit" : "never at limit"]
        let long = [
            week.map { "Week up to \($0)" },
            atLimit > 0 ? "\(atLimit) \(atLimit == 1 ? "day" : "days") at the session limit" : "Session limit never reached"
        ]
        return ReportLimits(
            provider: provider, days: days, weekMax: weekMax, daysAtLimit: atLimit,
            summary: short.compactMap { $0 }.joined(separator: " \u{00B7} "),
            longSummary: long.compactMap { $0 }.joined(separator: " \u{00B7} ")
        )
    }
}
