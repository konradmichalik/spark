import Foundation

/// The words and numbers of the usage report window.
enum ReportText {
    /// "October 2026", or "5 Oct – 11 Oct" for a week.
    static func periodTitle(
        _ period: ReportPeriod, start: Date, end: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        switch period {
        case .month:
            return format(start, template: "MMMMyyyy", locale: locale, timeZone: timeZone)
        case .week:
            let day = { format($0, template: "dMMM", locale: locale, timeZone: timeZone) }
            return "\(day(start)) \u{2013} \(day(end))"
        }
    }

    /// The line under Tokens: "+9% vs. September", "+4% vs. 1–14 Oct" for a month still running,
    /// "-6% vs. last week". Neutral, the words carry it (docs/design/rules.md, "Averages"). `nil`
    /// without earlier use to compare with.
    static func comparison(
        _ percent: Double?, period: ReportPeriod, previousStart: Date, previousEnd: Date?,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String? {
        guard let percent, percent.isFinite else { return nil }
        let rounded = Int(percent.rounded())
        let change = (rounded > 0 ? "+" : rounded < 0 ? "-" : "") + UsageFormat.percent(Double(abs(rounded)), locale: locale)
        return "\(change) vs. \(comparisonTarget(period, previousStart: previousStart, previousEnd: previousEnd, locale: locale, timeZone: timeZone))"
    }

    private static func comparisonTarget(
        _ period: ReportPeriod, previousStart: Date, previousEnd: Date?, locale: Locale, timeZone: TimeZone
    ) -> String {
        guard period == .month else { return "last week" }
        let text = { (template: String, date: Date) in format(date, template: template, locale: locale, timeZone: timeZone) }
        guard let previousEnd else { return text("MMMM", previousStart) }
        let first = text("d", previousStart)
        let last = text("d", previousEnd)
        return "\(first == last ? first : "\(first)\u{2013}\(last)") \(text("MMM", previousStart))"
    }

    /// The comparison's tooltip. `partialDays` is set while a running month is compared with the
    /// first days of the month before.
    static func previousTokens(_ tokens: Int, period: ReportPeriod, partialDays: Int?) -> String {
        let amount = "\(formatTokenCount(tokens)) tokens"
        if let partialDays {
            return "\(amount) in the first \(partialDays) \(partialDays == 1 ? "day" : "days") of the month before"
        }
        return "\(amount) the \(period == .month ? "month" : "week") before"
    }

    /// The line under the totals. With a single active day it would repeat the total, so it waits
    /// for a second one.
    static func dailyAverage(total: Int, activeDays: Int) -> String? {
        guard activeDays > 1, total > 0 else { return nil }
        return "Average \(formatTokenCount(Int((Double(total) / Double(activeDays)).rounded()))) tokens per active day"
    }

    static func format(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        HistoryAxis.formatter(locale: locale, timeZone: timeZone, template: template).string(from: date)
    }
}
