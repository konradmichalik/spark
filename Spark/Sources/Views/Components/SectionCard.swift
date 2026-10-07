import SwiftUI

/// The container a section's rows sit on. Grouping is carried by the card's edge and the gap
/// between sections, not by dividers (docs/design/rules.md, "Layout"). Opaque `card` on
/// `paper`, so it reads the same with Reduce Transparency on or off.
struct SectionCard<Content: View>: View {
    var density: SectionDensity = .regular
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        VStack(alignment: .leading, spacing: density.cardSpacing) { content() }
            .padding(density.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }
}
