import CoreGraphics
import Foundation

/// A day column's dots split by provider, Claude's at the bottom.
struct ReportColumnStack: Equatable {
    let claude: Int
    let codex: Int

    var total: Int { claude + codex }
}

/// Geometry of the report's day and limit columns (docs/design/rules.md, "Dot language").
enum ReportColumnLayout {
    static let rowPitch: CGFloat = 6
    static let dotSize: CGFloat = 4
    static let overviewHeight: CGFloat = 60
    static let detailHeight: CGFloat = 156
    /// The height of a limit column at 100 %.
    static let limitHeight: CGFloat = 96

    /// The dots a column of `height` holds, the lowest one resting on the baseline.
    static func maxRows(height: CGFloat) -> Int {
        max(Int(((height - dotSize) / rowPitch).rounded(.down)) + 1, 1)
    }

    /// A day's dots against the busiest day's `peak`. Any use shows at least one dot.
    static func rows(tokens: Int, peak: Int, maxRows: Int) -> Int {
        guard tokens > 0, peak > 0 else { return 0 }
        return min(max(Int((Double(tokens) / Double(peak) * Double(maxRows)).rounded()), 1), maxRows)
    }

    /// The column of a day in All. While both providers were used, each keeps at least one dot.
    static func stack(claude: Int, codex: Int, peak: Int, maxRows: Int) -> ReportColumnStack {
        let total = rows(tokens: claude + codex, peak: peak, maxRows: maxRows)
        guard total > 0 else { return ReportColumnStack(claude: 0, codex: 0) }
        let share = Int((Double(total) * Double(claude) / Double(claude + codex)).rounded())
        let claudeRows = claude > 0 && codex > 0 && total >= 2 ? min(max(share, 1), total - 1) : share
        return ReportColumnStack(claude: claudeRows, codex: total - claudeRows)
    }

    /// A limit column: 100 % fills it, a recorded 0 % still shows one dot, a day without data none.
    static func percentRows(_ value: Double?, maxRows: Int) -> Int {
        guard let value else { return 0 }
        let clamped = min(max(value.isFinite ? value : 0, 0), 100)
        return max(Int((clamped / 100 * Double(maxRows)).rounded()), 1)
    }

    static func centerX(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return width / CGFloat(count) * (CGFloat(index) + 0.5)
    }
}

/// Timing of the report's columns: they grow from the bottom, left to right with the dot bar's
/// spacing, within the dot bar's 300 ms (docs/design/rules.md, "Motion").
enum ReportColumnMotion {
    static let lineDuration = 0.45
    static let lineDelay = 0.15

    /// When column `index` starts, in seconds. The starts take at most half the fill, so the last
    /// column still has time to grow.
    static func start(index: Int, count: Int) -> Double {
        Double(index) * stagger(count: count)
    }

    /// Dots of column `index` shown at `progress` (0 to 1) of a fill from `from` to `to` dots.
    /// A fall shows at once.
    static func shown(from: Int, to: Int, index: Int, count: Int, progress: Double) -> Int {
        guard to > from, progress < 1 else { return to }
        let growth = DotFillSequence.duration - Double(max(count - 1, 0)) * stagger(count: count)
        let local = min(max((progress * DotFillSequence.duration - start(index: index, count: count)) / growth, 0), 1)
        return from + Int((Double(to - from) * local).rounded(.up))
    }

    /// Where each column starts when the values change: the lower of old and new, so a fall
    /// shows at once. `nil` when nothing rose. Different days start from empty.
    static func starts(old: [Int], new: [Int]) -> [Int]? {
        guard old.count == new.count else { return Array(repeating: 0, count: new.count) }
        guard zip(old, new).contains(where: { $1 > $0 }) else { return nil }
        return zip(old, new).map { min($0, $1) }
    }

    private static func stagger(count: Int) -> Double {
        guard count > 1 else { return 0 }
        return min(DotFillSequence.maxStagger, DotFillSequence.duration / 2 / Double(count - 1))
    }
}

struct ReportLinePoint: Equatable {
    let index: Int
    /// Percent, 0 to 100.
    let value: Double
}

/// The weekly line of the report's Limits: it breaks on a day without a weekly value.
enum ReportWeekLine {
    static func segments(_ values: [Double?]) -> [[ReportLinePoint]] {
        values.enumerated().reduce(into: [[ReportLinePoint]]()) { segments, entry in
            guard let value = entry.element else {
                if segments.last?.isEmpty == false { segments.append([]) }
                return
            }
            let point = ReportLinePoint(index: entry.offset, value: min(max(value, 0), 100))
            if segments.isEmpty { segments.append([]) }
            segments[segments.count - 1].append(point)
        }
        .filter { !$0.isEmpty }
    }
}

/// The labels under the report's columns: every day for a week, the 1st, 8th, 15th, 22nd and
/// 29th for a month.
enum ReportDayAxis {
    struct Label: Equatable {
        let index: Int
        let text: String
    }

    static func labels(dates: [Date], period: ReportPeriod, calendar: Calendar, locale: Locale) -> [Label] {
        dates.enumerated().compactMap { index, date in
            switch period {
            case .week:
                let weekday = ReportText.format(date, template: "EEE", locale: locale, timeZone: calendar.timeZone)
                let day = calendar.component(.day, from: date)
                return Label(index: index, text: "\(weekday) \(day)")
            case .month:
                let day = calendar.component(.day, from: date)
                return (day - 1) % 7 == 0 ? Label(index: index, text: String(day)) : nil
            }
        }
    }
}
