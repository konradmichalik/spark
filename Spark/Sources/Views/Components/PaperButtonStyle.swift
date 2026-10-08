import SwiftUI

/// The button of every paper surface: `secondary` sits on a hairline fill, `primary` is ink with
/// paper text for the one main action of a screen.
struct PaperButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        PaperButtonBody(label: configuration.label, kind: kind, isPressed: configuration.isPressed)
    }
}

private struct PaperButtonBody<Label: View>: View {
    let label: Label
    let kind: PaperButtonStyle.Kind
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind == .primary ? Theme.paper : Theme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(kind == .primary ? Theme.ink : Theme.hairline, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .opacity(isEnabled ? (isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PaperButtonStyle {
    static var paper: PaperButtonStyle { PaperButtonStyle() }
    static var paperPrimary: PaperButtonStyle { PaperButtonStyle(kind: .primary) }
}
