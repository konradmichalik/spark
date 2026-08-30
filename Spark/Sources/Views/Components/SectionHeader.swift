import SwiftUI

/// How much room a section has. `.regular` is the settings window, `.compact` the 300pt popover.
enum SectionDensity {
    case regular
    case compact

    var titleSize: CGFloat { self == .regular ? 12 : 10 }
    var iconSize: CGFloat { self == .regular ? 14 : 13 }
    var cardPadding: CGFloat { self == .regular ? 12 : 10 }
    var cardSpacing: CGFloat { self == .regular ? 8 : 4 }
    var headerGap: CGFloat { self == .regular ? 8 : 6 }

    /// Colour marks a category usefully at four marks on a dense surface read at a glance. Across
    /// fifteen settings headers on seven tabs it marks nothing, and the tab bar already separates
    /// those categories, so settings headers stay `.secondary` there.
    var iconColor: Color { self == .regular ? .secondary : Theme.sparkOrangeIcon }
}

/// A section title: accent icon, uppercase label, optional trailing accessory.
///
/// Uppercase with tracking is what separates a header from the content rows beneath it, and from
/// a tappable disclosure row, without needing a divider or a second colour. Before this, headers,
/// content labels, and disclosure rows all rendered as caption-sized secondary text with an
/// orange icon, which is why the popover read as one flat list.
struct SectionHeader<Accessory: View>: View {
    let title: String
    let icon: TablerIcon
    var density: SectionDensity = .regular
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 5) {
            TablerIconView(icon, size: density.iconSize, color: density.iconColor)
            Text(title)
                .font(.system(size: density.titleSize, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundColor(.secondary)
            Spacer(minLength: 4)
            accessory()
        }
        .frame(minHeight: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, icon: TablerIcon, density: SectionDensity = .regular) {
        self.init(title: title, icon: icon, density: density) { EmptyView() }
    }
}
