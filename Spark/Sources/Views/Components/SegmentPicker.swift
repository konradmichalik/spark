import SwiftUI

/// Every conformer today implements `segmentLabel` as `{ rawValue }`, which looks like it could
/// collapse to a `RawRepresentable where RawValue == String` constraint on `SegmentPicker`. It
/// can't: at least one conformer's `rawValue` is also an `@AppStorage` persistence key, so welding
/// label to raw value would mean a future display-string rename silently migrates (or breaks)
/// every user's stored preference. This protocol is the seam that keeps the two separable.
protocol SegmentLabeled: Hashable {
    var segmentLabel: String { get }
    var segmentIcon: SegmentIcon? { get }
}

extension SegmentLabeled {
    var segmentIcon: SegmentIcon? { nil }
}

/// A small mark in front of a segment's label. The Claude mark is a vector shape rather than a
/// Tabler asset, so it gets its own case.
enum SegmentIcon {
    case tabler(TablerIcon)
    case claudeLogo

    @ViewBuilder
    func view(isSelected: Bool) -> some View {
        switch self {
        case .tabler(let icon):
            TablerIconView(icon, size: 10, color: isSelected ? .primary : .secondary)
        case .claudeLogo:
            ClaudeLogoShape()
                .fill(Theme.sparkOrange)
                .frame(width: 9, height: 9)
                .opacity(isSelected ? 1 : 0.7)
                .accessibilityHidden(true)
        }
    }
}

/// The one segmented control in the app.
///
/// Replaces three hand-rolled button rows that differed in size, padding, and placement, and one
/// of which used icon-only buttons. Drawn as a trough with the selected segment as a raised tile,
/// which is how AppKit draws a real segmented control, so the group reads as one control rather
/// than as loose buttons.
struct SegmentPicker<T: SegmentLabeled>: View {
    @Binding var selection: T
    let options: [T]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    selection = option
                } label: {
                    HStack(spacing: 3) {
                        option.segmentIcon?.view(isSelected: isSelected)
                        Text(option.segmentLabel)
                            .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 3)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlColor))
                                .shadow(color: .black.opacity(0.16), radius: 0.75, y: 0.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.segmentLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.055))
        )
    }
}
