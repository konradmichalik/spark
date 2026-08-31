import SwiftUI

/// The container a section's rows sit on. Replaces the popover's dividers: grouping is carried
/// by the card's edge and the gap between sections, not by a line drawn across the full width.
///
/// Mirrors the settings window's former `CardView`, which used the same quaternary fill
/// at the same radius, so both surfaces now read as one system.
struct SectionCard<Content: View>: View {
    var density: SectionDensity = .regular
    @ViewBuilder var content: () -> Content

    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: density.cardSpacing) { content() }
            .padding(density.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveBackground(
                reduceTransparency: reduceTransparency,
                material: .quaternary.opacity(0.3),
                // `.controlBackgroundColor` alone is near-white next to the popover's
                // `.windowBackgroundColor`, a gap Apple picks deliberately for legibility. Blending
                // it down keeps the card readable without the harsh jump.
                opaque: Color(nsColor: .controlBackgroundColor).opacity(0.5),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.black.opacity(0.055))
            )
    }
}
