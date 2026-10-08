import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general, menuBar, display, connection, notifications, status, about
}

/// The design tokens live in `DesignTokens.swift` (docs/design/rules.md, "Colour").
enum Theme {}

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
