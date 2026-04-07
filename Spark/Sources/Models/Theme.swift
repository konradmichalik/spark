import AppKit
import SwiftUI

enum Theme {
    static let sparkOrange = Color(nsColor: sparkOrangeNS)
    static let sparkOrangeNS = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)

    /// Returns the threshold-based color for a usage ring, with opacity abstufung per ring index.
    /// ringIndex: 0 = outermost (Session), 1 = middle (Weekly), 2 = innermost (Sonnet)
    static func ringColor(
        utilization: Double,
        warningThreshold: Double,
        criticalThreshold: Double,
        ringIndex: Int
    ) -> Color {
        let baseColor: Color
        if utilization >= criticalThreshold {
            baseColor = .red
        } else if utilization >= warningThreshold {
            baseColor = .orange
        } else {
            baseColor = .green
        }

        let opacityLevels: [Double] = [1.0, 0.7, 0.45]
        let opacity = ringIndex < opacityLevels.count ? opacityLevels[ringIndex] : 0.45
        return baseColor.opacity(opacity)
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
