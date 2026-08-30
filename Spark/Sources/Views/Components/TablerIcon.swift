import SwiftUI

/// Tabler Icons v3.46.0 (MIT), bundled as template image sets in `Assets.xcassets/Icons`.
/// Regenerate with `scripts/fetch-tabler-icons.sh`.
///
/// The raw value is the asset name. Adding a case without running the script fails
/// `TablerIconTests.testEveryIconResolvesToABundledAsset` rather than rendering an empty frame.
enum TablerIcon: String, CaseIterable {
    case activity
    case adjustmentsHorizontal = "adjustments-horizontal"
    case alertTriangle = "alert-triangle"
    case arrowDown = "arrow-down"
    case arrowRight = "arrow-right"
    case arrowUp = "arrow-up"
    case bell
    case bellBolt = "bell-bolt"
    case bellRinging = "bell-ringing"
    case calendarMonth = "calendar-month"
    case chartBar = "chart-bar"
    case chartLine = "chart-line"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case circleArrowUp = "circle-arrow-up"
    case circleCheck = "circle-check"
    case circlePlus = "circle-plus"
    case circleX = "circle-x"
    case clock
    case download
    case externalLink = "external-link"
    case eyeOff = "eye-off"
    case folders
    case helpCircle = "help-circle"
    case heart
    case history
    case infoCircle = "info-circle"
    case key
    case layoutGrid = "layout-grid"
    case layoutNavbar = "layout-navbar"
    case link
    case linkPlus = "link-plus"
    case moon
    case numbers
    case power
    case refresh
    case refreshAlert = "refresh-alert"
    case reportAnalytics = "report-analytics"
    case rosetteDiscountCheck = "rosette-discount-check"
    case send
    case server
    case settings
    case sparkles
    case terminal2 = "terminal-2"
    case userCircle = "user-circle"
    case world

    var assetName: String { rawValue }
}

/// Renders a bundled Tabler icon at an explicit point size.
///
/// Tabler draws on a 24pt grid with a 2pt stroke, so a 13pt render lands at a ~1.08pt stroke,
/// which sits close to SF Symbols at regular weight. Size is explicit rather than derived from
/// the font, because `.imageScale` on a bitmap-backed template gives inconsistent optical
/// weights across the popover's mix of caption and body text.
struct TablerIconView: View {
    let icon: TablerIcon
    var size: CGFloat = 13
    var color: Color = .secondary

    init(_ icon: TablerIcon, size: CGFloat = 13, color: Color = .secondary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(icon.assetName)
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
