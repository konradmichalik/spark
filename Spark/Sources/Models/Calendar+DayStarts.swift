import Foundation

extension Calendar {
    /// Every midnight from `first` through `last`. Each day is re-normalized to midnight:
    /// `date(byAdding:)` keeps the wall-clock time, so across a DST change the raw result drifts off
    /// midnight and the `<= last` check would end one day early, dropping the last day.
    func dayStarts(from first: Date, through last: Date) -> [Date] {
        var days: [Date] = []
        var day = first
        while day <= last {
            days.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = startOfDay(for: next)
        }
        return days
    }
}
