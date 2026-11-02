import SwiftUI

/// One row of Breakdown or of a level 1 top list: name, tokens and a 4 pt dot bar scaled to the
/// top row. Breakdown adds the provider logos (All only) and the share or session timing.
struct ReportBreakdownRowView: View {
    let row: ReportBreakdownRow
    /// The row's place in the list, which delays its bar's fill.
    let index: Int
    /// Level 1 leaves out logos, shares and the folder actions: the whole card is a button there.
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if !isCompact {
                    ForEach(row.providers, id: \.self) { provider in
                        PopoverHeader.logo(for: provider.usageProvider, size: 11)
                    }
                }
                Text(row.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !isCompact, !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 8)
                Text(formatTokenCount(row.tokens))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize()
            }
            ReportShareBar(percent: row.barPercent, index: index)
        }
        .padding(.vertical, 5)
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .tooltip(row.tooltip, title: row.name, delay: .quick)
        .pathActions(isCompact ? nil : row.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        let providers = isCompact ? [] : row.providers.map(\.usageProvider.segmentLabel)
        let parts: [String?] = [
            providers.isEmpty ? nil : providers.joined(separator: " and "),
            isCompact || row.detail.isEmpty ? nil : row.detail,
            "\(formatTokenCount(row.tokens)) tokens"
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

/// A row's 4 pt dot bar. It fills from the left on appear, each row 25 ms after the one above
/// (docs/design/rules.md, "Motion": Report share bars); under Reduce Motion it shows at once.
struct ReportShareBar: View {
    let percent: Double
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    private static let rowStagger = 25

    var body: some View {
        DotBar(value: isRevealed || reduceMotion ? percent : 0, pitch: 4, dotSize: 2.6, animatesFill: true)
            .frame(height: 6)
            .accessibilityHidden(true)
            .task {
                guard !isRevealed, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(Self.rowStagger * index))
                isRevealed = true
            }
    }
}

extension ReportProvider {
    var usageProvider: UsageProvider {
        switch self {
        case .claude: .claude
        case .codex: .codex
        }
    }
}
