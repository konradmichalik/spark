import SwiftUI

protocol SegmentLabeled: Hashable {
    var segmentLabel: String { get }
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
                    Text(option.segmentLabel)
                        .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)
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
