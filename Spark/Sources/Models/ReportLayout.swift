import CoreGraphics

/// Sizes for the usage report window that depend on its content.
enum ReportLayout {
    /// One Doto size for all totals, so the row reads as one line: set by the longest value
    /// (prefix and number, the unit is drawn small and does not count).
    static func totalsSize(_ values: [String]) -> CGFloat {
        switch values.map(\.count).max() ?? 0 {
        case ...4: 40
        case 5: 36
        case 6: 32
        default: 28
        }
    }

    /// The window height that shows the whole report without scrolling: the current height plus
    /// what the scroll view is missing, never taller than the screen and never below the minimum.
    static func windowHeight(
        current: CGFloat, visibleScroll: CGFloat, content: CGFloat, screenHeight: CGFloat, minimum: CGFloat
    ) -> CGFloat {
        min(max(current + content - visibleScroll, minimum), screenHeight)
    }
}
