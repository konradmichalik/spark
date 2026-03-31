import AppKit
import SwiftUI

enum Theme {
    static let sparkOrange = Color(nsColor: sparkOrangeNS)
    static let sparkOrangeNS = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
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
