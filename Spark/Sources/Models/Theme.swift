import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, menuBar, display, connection, notifications, status, about
}

enum Theme {
    static let sparkOrange = Color(nsColor: sparkOrangeNS)
    static let sparkOrangeNS = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)

    /// Icon tint. The brand orange sits at roughly 2.4:1 on a light window background, below the
    /// 3:1 that non-text UI elements need, so icons use a darkened variant in light mode and a
    /// lightened one in dark. `sparkOrange` itself is unchanged and still paints the tier badge
    /// and the session graph line at their exact tone until those screens move to the new tokens.
    static let sparkOrangeIcon = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.90, green: 0.56, blue: 0.42, alpha: 1)
            : NSColor(red: 0.77, green: 0.39, blue: 0.25, alpha: 1)
    })

    /// Trend-down accent (Weekly Report). Paired with `sparkOrangeIcon` for trend-up so both
    /// directions read as an intentional accent rather than one themed color and one raw SwiftUI
    /// `.orange`/`.green`. Same contrast-safe per-appearance construction as `sparkOrangeIcon`.
    static let trendDown = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.45, green: 0.72, blue: 0.55, alpha: 1)
            : NSColor(red: 0.20, green: 0.50, blue: 0.32, alpha: 1)
    })

    /// History graph lines
    static let graphSession = sparkOrange
    static let graphWeekly = Color(nsColor: NSColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1))
    static let graphSonnet = Color(hue: 0.80, saturation: 0.50, brightness: 0.80)
    static let graphOpus = Color(hue: 0.12, saturation: 0.70, brightness: 0.85)
    static let graphFable = Color(hue: 0.45, saturation: 0.55, brightness: 0.80)
}

extension Date {
    /// The detail line of a reset tooltip, e.g. "Wednesday, 7 October at 13:10".
    var resetDescription: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())
    }
}

extension TimeInterval {
    var shortDuration: String {
        let totalMinutes = Int(self) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
