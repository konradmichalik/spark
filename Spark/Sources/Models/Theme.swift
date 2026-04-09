import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, menuBar, display, connection, notifications, status, about
}

enum Theme {
    static let sparkOrange = Color(nsColor: sparkOrangeNS)
    static let sparkOrangeNS = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)

    /// Returns a distinct color per ring, based on utilization thresholds.
    /// ringIndex: 0 = outermost (Session), 1 = middle (Weekly), 2 = innermost (Sonnet)
    static func ringColor(
        utilization: Double,
        warningThreshold: Double,
        criticalThreshold: Double,
        ringIndex: Int
    ) -> Color {
        let palette = RingPalette.forIndex(ringIndex)
        if utilization >= criticalThreshold { return palette.critical }
        if utilization >= warningThreshold { return palette.warning }
        return palette.ok
    }
}

// Distinct hues per ring (Activity Rings style)
private struct RingPalette {
    let ok: Color
    let warning: Color
    let critical: Color

    // Session: teal-green / warm orange / red
    static let session = RingPalette(
        ok: Color(hue: 0.35, saturation: 0.75, brightness: 0.75),
        warning: Color(hue: 0.08, saturation: 0.85, brightness: 0.95),
        critical: Color(hue: 0.0, saturation: 0.80, brightness: 0.90)
    )
    // Weekly: blue / amber / rose
    static let weekly = RingPalette(
        ok: Color(hue: 0.55, saturation: 0.60, brightness: 0.80),
        warning: Color(hue: 0.12, saturation: 0.75, brightness: 0.90),
        critical: Color(hue: 0.95, saturation: 0.75, brightness: 0.85)
    )
    // Sonnet: purple / gold / pink
    static let sonnet = RingPalette(
        ok: Color(hue: 0.80, saturation: 0.50, brightness: 0.80),
        warning: Color(hue: 0.15, saturation: 0.65, brightness: 0.85),
        critical: Color(hue: 0.98, saturation: 0.65, brightness: 0.80)
    )

    static func forIndex(_ index: Int) -> RingPalette {
        switch index {
        case 0: .session
        case 1: .weekly
        default: .sonnet
        }
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
