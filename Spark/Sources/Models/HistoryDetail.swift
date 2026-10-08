import Foundation

/// The ranges of the history screen.
enum GraphTimeRange: String, CaseIterable {
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"

    var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 3600 * 6
        case .oneDay: 3600 * 24
        case .sevenDays: 3600 * 24 * 7
        case .thirtyDays: 3600 * 24 * 30
        }
    }

    /// Dot columns across the graph. A slot is never shorter than a poll (five minutes), so a
    /// normal pause between polls does not read as a gap.
    var columnCount: Int {
        switch self {
        case .oneHour: 12
        case .sixHours: 36
        case .oneDay: 48
        case .sevenDays: 42
        case .thirtyDays: 45
        }
    }

    var spokenLabel: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .oneDay: "1 day"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        }
    }

    /// Ranges longer than a day label days instead of clock times.
    var spansDays: Bool { seconds > 86_400 }

    /// Rollups have no resolution below a day, and a single day is a single column, so Volume
    /// only offers ranges that plot more than one.
    static let dayGranularityCases: [GraphTimeRange] = [.sevenDays, .thirtyDays]
}

extension GraphTimeRange: SegmentLabeled {
    var segmentLabel: String { rawValue.uppercased() }
}

enum GraphMode: String, CaseIterable {
    case limits = "Limits"
    case volume = "Volume"
}

extension GraphMode: SegmentLabeled {
    var segmentLabel: String { rawValue }
}

/// The two facts under the limits graph: the highest session value in the range, and how many
/// weekly points were added in it. A weekly reset is not subtracted, so the sum stays the usage.
struct HistorySummary: Equatable {
    let peakSession: Double?
    let weekAdded: Double?

    static func make(_ snapshots: [UsageSnapshot]) -> HistorySummary {
        let peak = snapshots.map(\.sessionUtilization).max()
        guard snapshots.count >= 2 else { return HistorySummary(peakSession: peak, weekAdded: nil) }
        let added = zip(snapshots, snapshots.dropFirst()).reduce(0) { sum, pair in
            sum + max(pair.1.weeklyUtilization - pair.0.weeklyUtilization, 0)
        }
        return HistorySummary(peakSession: peak, weekAdded: added)
    }

    /// Weekly points with their sign: "+10" and "pts".
    static func points(_ value: Double) -> NumberParts {
        let rounded = Int(value.rounded())
        return NumberParts(number: rounded > 0 ? "+\(rounded)" : String(rounded), unit: abs(rounded) == 1 ? "pt" : "pts")
    }
}

/// Daily token volume as dot columns on the same scale as the limits graph: the busiest day is
/// full height. A day without a rollup stays empty, so long idle runs collapse like gaps.
enum VolumeColumns {
    static func make(_ days: [VolumeDay], calendar: Calendar = .current) -> [HistoryColumn] {
        let busiest = days.map(\.tokens).max() ?? 0
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return days.map { day in
            let share = day.isEmpty ? nil : busiest > 0 ? Double(day.tokens) / Double(busiest) * 100 : 0
            return HistoryColumn(session: share, weekly: nil, slotStart: parser.date(from: day.day))
        }
    }
}

struct VolumeSummary: Equatable {
    let total: Int
    let dailyAverage: Int?

    static func make(_ days: [VolumeDay]) -> VolumeSummary {
        let active = days.filter { !$0.isEmpty }
        let total = active.reduce(0) { $0 + $1.tokens }
        return VolumeSummary(total: total, dailyAverage: active.isEmpty ? nil : total / active.count)
    }
}

/// The hover readout of the volume graph: the day and its tokens.
enum VolumeHover {
    static func text(
        for item: HistoryItem, days: [VolumeDay], columns: [HistoryColumn], locale: Locale = .current, timeZone: TimeZone = .current
    ) -> (title: String, body: String)? {
        let format = HistoryAxis.formatter(locale: locale, timeZone: timeZone, template: "EEEdMMM")
        switch item {
        case .column(let index):
            guard let day = days[safe: index], let start = columns[safe: index]?.slotStart else { return nil }
            return (format.string(from: start), day.isEmpty ? "No data" : "\(formatTokenCount(day.tokens)) tokens")
        case .gap(let range):
            guard let first = columns[safe: range.lowerBound]?.slotStart,
                  let last = columns[safe: range.upperBound - 1]?.slotStart else { return nil }
            return ("\(format.string(from: first))\u{2013}\(format.string(from: last))", "No data")
        }
    }
}
