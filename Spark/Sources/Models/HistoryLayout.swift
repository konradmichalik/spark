import CoreGraphics
import Foundation

struct HistoryColumn: Equatable {
    let session: Double?
    let weekly: Double?
    var time: Date?
    var slotStart: Date?

    var hasValue: Bool { session != nil || weekly != nil }
}

/// Buckets snapshots of the last `window` into `count` equal slots, oldest first, keeping the
/// latest snapshot per slot. Slots without a snapshot stay empty instead of being stretched.
enum HistoryColumns {
    static func make(_ snapshots: [UsageSnapshot], now: Date, window: TimeInterval = 6 * 3600, count: Int = 34) -> [HistoryColumn] {
        guard count > 0, window > 0 else { return [] }
        let start = now.addingTimeInterval(-window)
        let slot = window / Double(count)
        var latest = [Int: UsageSnapshot]()
        for snapshot in snapshots where snapshot.timestamp >= start && snapshot.timestamp <= now {
            let index = min(Int(snapshot.timestamp.timeIntervalSince(start) / slot), count - 1)
            if let existing = latest[index], existing.timestamp > snapshot.timestamp { continue }
            latest[index] = snapshot
        }
        return (0..<count).map { index in
            let slotStart = start.addingTimeInterval(Double(index) * slot)
            guard let snapshot = latest[index] else { return HistoryColumn(session: nil, weekly: nil, slotStart: slotStart) }
            return HistoryColumn(
                session: snapshot.sessionUtilization, weekly: snapshot.weeklyUtilization,
                time: snapshot.timestamp, slotStart: slotStart
            )
        }
    }
}

/// One horizontal unit of the history card: a column, or a run of empty columns collapsed into
/// one grey band, as in the full history graph.
enum HistoryItem: Equatable {
    case column(Int)
    case gap(Range<Int>)
}

enum HistoryLayout {
    /// Shorter runs of empty columns stay as they are; a missing poll or two is not a gap.
    static let minimumGap = 3

    static func items(_ columns: [HistoryColumn]) -> [HistoryItem] {
        var items: [HistoryItem] = []
        var index = 0
        while index < columns.count {
            guard !columns[index].hasValue else {
                items.append(.column(index))
                index += 1
                continue
            }
            var end = index
            while end < columns.count, !columns[end].hasValue { end += 1 }
            if end - index >= minimumGap {
                items.append(.gap(index..<end))
            } else {
                items.append(contentsOf: (index..<end).map(HistoryItem.column))
            }
            index = end
        }
        return items
    }

    static func index(x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard width > 0, count > 0 else { return nil }
        return min(max(Int(x / width * CGFloat(count)), 0), count - 1)
    }
}

/// The hover readout of the history card.
enum HistoryHover {
    static func text(
        for item: HistoryItem, in columns: [HistoryColumn], locale: Locale = .current, timeZone: TimeZone = .current
    ) -> (title: String, body: String)? {
        let format = HistoryAxis.formatter(locale: locale, timeZone: timeZone)
        switch item {
        case .column(let index):
            guard columns.indices.contains(index), columns[index].hasValue else { return nil }
            let column = columns[index]
            let lines = [
                column.session.map { "Session \(UsageFormat.percent($0, locale: locale))" },
                column.weekly.map { "Week \(UsageFormat.percent($0, locale: locale))" }
            ]
            return ((column.time ?? column.slotStart).map(format.string) ?? "", lines.compactMap { $0 }.joined(separator: "\n"))
        case .gap(let range):
            guard let start = columns[safe: range.lowerBound]?.slotStart, let end = gapEnd(range, columns) else { return nil }
            return ("\(format.string(from: start))\u{2013}\(format.string(from: end))", "No data. The Mac was asleep or Spark was closed")
        }
    }

    private static func gapEnd(_ range: Range<Int>, _ columns: [HistoryColumn]) -> Date? {
        if let next = columns[safe: range.upperBound]?.slotStart { return next }
        guard let last = columns[safe: range.upperBound - 1]?.slotStart,
              let before = columns[safe: range.upperBound - 2]?.slotStart else { return nil }
        return last.addingTimeInterval(last.timeIntervalSince(before))
    }
}

/// Clock times under the history card: at the first, middle and last item of the compressed axis.
enum HistoryAxis {
    static func labels(
        items: [HistoryItem], columns: [HistoryColumn], locale: Locale = .current, timeZone: TimeZone = .current
    ) -> [String] {
        guard !items.isEmpty else { return [] }
        let format = formatter(locale: locale, timeZone: timeZone)
        let picks = [(items[0], false), (items[items.count / 2], false), (items[items.count - 1], true)]
        return picks.compactMap { item, isLast in
            let index: Int
            switch item {
            case .column(let column): index = column
            case .gap(let range): index = range.lowerBound
            }
            guard let column = columns[safe: index] else { return nil }
            let date = isLast ? (column.time ?? column.slotStart) : column.slotStart
            return date.map(format.string)
        }
    }

    static func formatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
