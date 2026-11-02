import CoreGraphics

/// Sizes for the usage report window that depend on its content.
enum ReportLayout {
    /// Tokens on the overview, 52 pt unless the number is longer than a compact count ("286.9").
    static func tokensSize(_ number: String) -> CGFloat {
        switch number.count {
        case ...5: 52
        case 6: 44
        default: 36
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
