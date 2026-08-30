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
    /// lightened one in dark. `sparkOrange` itself is unchanged and still paints the logo, the
    /// tier badge, and the session graph line at their exact brand tone.
    static let sparkOrangeIcon = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.90, green: 0.56, blue: 0.42, alpha: 1)
            : NSColor(red: 0.77, green: 0.39, blue: 0.25, alpha: 1)
    })

    /// History graph lines
    static let graphSession = sparkOrange
    static let graphWeekly = Color(nsColor: NSColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1))
    static let graphSonnet = Color(hue: 0.80, saturation: 0.50, brightness: 0.80)
    static let graphOpus = Color(hue: 0.12, saturation: 0.70, brightness: 0.85)
    static let graphFable = Color(hue: 0.45, saturation: 0.55, brightness: 0.80)

    /// Six-tier color for a `Pace.Tier`, from comfortably under budget to badly overspending.
    static func paceColor(for tier: Pace.Tier) -> Color {
        switch tier {
        case .comfortable: Color(hue: 0.35, saturation: 0.70, brightness: 0.75)
        case .onTrack: Color(hue: 0.50, saturation: 0.65, brightness: 0.75)
        case .warming: Color(hue: 0.14, saturation: 0.80, brightness: 0.90)
        case .pressing: Color(hue: 0.08, saturation: 0.85, brightness: 0.90)
        case .critical: Color(hue: 0.0, saturation: 0.80, brightness: 0.85)
        case .runaway: Color(hue: 0.78, saturation: 0.55, brightness: 0.75)
        }
    }

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

extension View {
    /// Opaque background when Reduce Transparency is on, material otherwise.
    ///
    /// `material` and `opaque` default to the graph surfaces' values; a caller with a different
    /// opaque tone (a card sitting on a window rather than a graph background, say) passes its own
    /// pair rather than duplicating this ternary.
    func adaptiveBackground(
        reduceTransparency: Bool,
        material: some ShapeStyle = .ultraThinMaterial,
        opaque: Color = Color(nsColor: .windowBackgroundColor),
        in shape: some InsettableShape = RoundedRectangle(cornerRadius: 4)
    ) -> some View {
        background(
            reduceTransparency
                ? AnyShapeStyle(opaque)
                : AnyShapeStyle(material),
            in: shape
        )
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
