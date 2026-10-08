import SwiftUI

/// A notice on a card: an ochre alert icon, one sentence, and at most one action
/// (docs/design/rules.md, "States"). Ochre on its own does not reach 4.5:1 for small text, so
/// the colour stays on the icon and the words stay ink.
struct WarningBanner: View {
    let message: String
    var icon: TablerIcon = .alertTriangle
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        HStack(alignment: .center, spacing: 8) {
            TablerIconView(icon, size: 14, color: Theme.warning)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 26)
                        .background(Theme.hairline, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(Theme.card, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .accessibilityElement(children: .contain)
    }
}
