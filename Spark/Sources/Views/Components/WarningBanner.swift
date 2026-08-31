import SwiftUI

/// A tinted callout for connectivity/API errors. Unlike a `SectionCard`, which groups a titled
/// section of otherwise-neutral rows, this exists to pull a single message out of the popover's
/// flat caption-and-secondary-color rhythm so an outage reads as urgent rather than as one more
/// line of metadata.
struct WarningBanner: View {
    let message: String
    var icon: TablerIcon = .alertTriangle

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            TablerIconView(icon, size: 12, color: Theme.sparkOrangeIcon)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sparkOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.sparkOrange.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}
