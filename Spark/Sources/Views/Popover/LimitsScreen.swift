import SwiftUI

/// The All Limits screen (boards 7 and 8): the plan, every limit as a dot bar with its value and
/// time marker, and below a hairline what is paid on top of the plan. Resets live in tooltips.
struct LimitsScreen: View {
    let plan: String?
    let sections: LimitSections
    let emptyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let plan {
                HStack(alignment: .firstTextBaseline) {
                    Text("Plan")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Text(plan.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(sections.limits) { line in
                LimitLineView(line: line)
            }
            if sections.limits.isEmpty, let emptyText {
                DetailNote(text: emptyText)
            }
            if !sections.extras.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                ForEach(sections.extras) { line in
                    LimitLineView(line: line)
                }
            }
        }
    }
}

private struct LimitLineView: View {
    let line: LimitLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            if let value = line.value {
                DotBar(value: value, marker: line.elapsed.map { $0 * 100 }, tone: line.tone, pitch: 4, dotSize: 2.6)
                    .frame(height: 8)
            }
        }
        // A taller hover target than the text and dots themselves.
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .tooltip(line.tooltip, title: line.label, delay: .quick)
        .padding(.vertical, -3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(line.tooltip ?? "")
    }

    @ViewBuilder
    private var trailing: some View {
        if let detail = line.detail {
            Text(detail)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        } else if let value = line.value {
            HStack(spacing: 4) {
                // Ochre text is too light to carry meaning by colour alone at this size.
                if line.tone != .normal {
                    TablerIconView(.alertTriangle, size: 11, color: line.tone.color)
                }
                Text(UsageFormat.percent(value))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(line.tone.color)
            }
        }
    }

    private var accessibilityValue: String {
        let state = switch line.tone {
        case .normal: ""
        case .warning: ", warning"
        case .critical: ", critical"
        }
        return (line.detail ?? line.value.map { UsageFormat.percent($0) } ?? "") + state
    }
}
