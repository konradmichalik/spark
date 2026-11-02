import Foundation

/// The report's two levels: the overview, and the screens its cards open (docs/design/rules.md,
/// "Navigation").
enum ReportScreen: Hashable {
    case overview, activity, limits, breakdown

    /// The breadcrumb's last part on level 2.
    var title: String {
        switch self {
        case .overview: ""
        case .activity: "Activity"
        case .limits: "Limits"
        case .breakdown: "Breakdown"
        }
    }
}

/// What VoiceOver reads for the report's level 1 cards: the screen the card opens and its key
/// figure, since the whole card is one button (docs/design/rules.md, "Accessibility").
enum ReportCardText {
    static func activity(_ series: ReportDaySeries, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Open Activity, \(ReportDayText.overviewLine(series, calendar: calendar, locale: locale))"
    }

    static func limits(_ limits: [ReportLimits]) -> String {
        let summaries = limits.map { "\($0.provider.name): \($0.summary)" }
        return (["Open Limits"] + (summaries.isEmpty ? [] : [summaries.joined(separator: "; ")])).joined(separator: ", ")
    }

    static func breakdown(_ tab: ReportBreakdownTab, rows: [ReportBreakdownRow]) -> String {
        let top = rows.first.map { "top \($0.name) with \(formatTokenCount($0.tokens)) tokens" }
        return ["Open Breakdown", tab.segmentLabel, top].compactMap { $0 }.joined(separator: ", ")
    }
}
