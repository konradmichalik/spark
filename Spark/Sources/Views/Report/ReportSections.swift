import SwiftUI

/// One section of the report on its own card, so the sections read as separate things: the same
/// `card` with a hairline outline as the popover's cards (docs/design/rules.md, "Windows").
struct ReportCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        PaperCard {
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// A micro label over a figure, read as one element by VoiceOver, with the secondary facts in
/// its tooltip. The shape shared by the report's totals and the activity tiles.
struct ReportFigure<Content: View>: View {
    let label: String
    var tooltip: String?
    var spoken: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: label)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tooltip(tooltip, title: label, delay: .quick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(spoken ?? "")
        .accessibilityHint(tooltip ?? "")
    }
}

/// Each weekday's average tokens as a dot bar against the busiest weekday.
struct WeekdaySection: View {
    let profile: WeekdayProfile
    /// `nil` where the surrounding card already names the view.
    var title: String? = "BY WEEKDAY \u{00B7} AVERAGE"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                MicroLabel(text: title)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 6) {
                ForEach(profile.entries, id: \.name) { entry in
                    HStack(spacing: 10) {
                        Text(entry.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 34, alignment: .leading)
                        DotBar(value: entry.share, pitch: 4, dotSize: 2.6)
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        Text(formatTokenCount(entry.average))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .frame(minHeight: 20)
                    .contentShape(Rectangle())
                    .tooltip(entry.tooltip, title: entry.fullName, delay: .quick)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.fullName)
                    .accessibilityValue(entry.tooltip)
                }
            }
        }
    }
}
