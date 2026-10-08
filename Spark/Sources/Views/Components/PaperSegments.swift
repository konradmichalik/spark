import SwiftUI

/// The segmented control of the popover's detail screens (boards 4 and 6). `trough` sits in a
/// hairline trough with the selected segment raised as a card, like the provider tabs; `chips`
/// are small mono labels with the selected one set in ink.
struct PaperSegments<T: SegmentLabeled>: View {
    enum Style { case trough, chips }

    @Binding var selection: T
    let options: [T]
    var style: Style = .trough
    var fillsWidth = false
    let label: String
    /// What VoiceOver reads for a segment whose label is an abbreviation, such as "7D".
    var spokenLabel: (T) -> String = { $0.segmentLabel }

    var body: some View {
        HStack(spacing: style == .trough ? 2 : 3) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(style == .trough ? 2 : 0)
        .background {
            if style == .trough {
                RoundedRectangle(cornerRadius: 9).fill(Theme.hairline)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: T) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(option.segmentLabel)
                .font(font(isSelected: isSelected))
                .foregroundStyle(textColor(isSelected: isSelected))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, style == .chips ? 6 : 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: style == .chips ? 24 : 26)
                .background {
                    if isSelected { selectedBackground }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel(option))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func font(isSelected: Bool) -> Font {
        switch style {
        case .trough: .system(size: 11.5, weight: isSelected ? .semibold : .medium)
        case .chips: .system(size: 10.5, weight: .medium, design: .monospaced)
        }
    }

    private func textColor(isSelected: Bool) -> Color {
        switch style {
        case .trough: Theme.ink
        case .chips: isSelected ? Theme.paper : Theme.inkSecondary
        }
    }

    @ViewBuilder
    private var selectedBackground: some View {
        switch style {
        case .trough:
            let shape = RoundedRectangle(cornerRadius: 7)
            shape.fill(Theme.card).overlay(shape.strokeBorder(Theme.hairline))
        case .chips:
            RoundedRectangle(cornerRadius: 5).fill(Theme.ink)
        }
    }
}
