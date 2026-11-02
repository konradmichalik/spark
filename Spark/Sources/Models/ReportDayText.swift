import Foundation

/// The words around the report's day columns: the day tooltip, the graph's VoiceOver value and
/// the tiles under it (docs/design/rules.md, "Windows", Activity).
enum ReportDayText {
    static func title(_ day: ReportDay, calendar: Calendar, locale: Locale = .current) -> String {
        ReportText.format(day.date, template: "EEEdMMM", locale: locale, timeZone: calendar.timeZone)
    }

    /// Fresh tokens or "No use", the provider split in All, and the comparison with the average.
    static func body(_ day: ReportDay, scope: ReportScope) -> String {
        guard day.total > 0 else { return "No use" }
        let split = scope == .all ? "Claude \(formatTokenCount(day.claude)) \u{00B7} Codex \(formatTokenCount(day.codex))" : nil
        return ["\(formatTokenCount(day.total)) tokens", split, day.note].compactMap { $0 }.joined(separator: "\n")
    }

    static func summary(_ series: ReportDaySeries, calendar: Calendar, locale: Locale = .current) -> String {
        guard let busiest = series.busiest else { return "No use in this period" }
        let busiestText = "\(title(busiest, calendar: calendar, locale: locale)) with \(formatTokenCount(busiest.total)) tokens"
        return "Used on \(series.activeDays) \(activeDaysUnit(series)), busiest day \(busiestText)"
    }

    /// The line under the overview's columns: "21 of 31 days active · busiest Tue, Oct 14, 1.2M tokens".
    static func overviewLine(_ series: ReportDaySeries, calendar: Calendar, locale: Locale = .current) -> String {
        guard let busiest = series.busiest else { return "No use in this period" }
        let busiestText = "busiest \(title(busiest, calendar: calendar, locale: locale)), \(formatTokenCount(busiest.total)) tokens"
        return "\(activeDaysText(series)) \u{00B7} \(busiestText)"
    }

    /// "21 of 31 days active".
    static func activeDaysText(_ series: ReportDaySeries) -> String {
        "\(series.activeDays) \(activeDaysUnit(series)) active"
    }

    /// The words after the active days' number: "of 31 days".
    static func activeDaysUnit(_ series: ReportDaySeries) -> String {
        "of \(series.daysUpToToday) days"
    }
}
