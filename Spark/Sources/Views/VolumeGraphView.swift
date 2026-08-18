import SwiftUI

private let graphHeight: CGFloat = 80

/// Daily token volume from permanent rollups — meaningful beyond the `Today`/`7d`/`30d` window
/// that live transcript stats can reach, since rollups outlive Claude Code's transcript
/// retention window and the snapshot ring buffer's cap alike.
struct VolumeGraphView: View {
    let rollups: [String: DailyRollup]
    let timeRange: GraphTimeRange

    private var days: [(day: String, tokens: Int)] {
        let cutoffDay = TranscriptCache.dayKey(for: Date().addingTimeInterval(-timeRange.seconds))
        return rollups
            .filter { $0.key >= cutoffDay }
            .map { (day: $0.key, tokens: $0.value.totalTokens) }
            .sorted { $0.day < $1.day }
    }

    private var maxTokens: Int { days.map(\.tokens).max() ?? 0 }

    var body: some View {
        if days.isEmpty {
            Text("No rollup data yet for this range")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(height: graphHeight, alignment: .center)
                .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(days, id: \.day) { entry in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.sparkOrange)
                        .frame(height: barHeight(for: entry.tokens))
                        .frame(maxWidth: .infinity)
                        .help("\(entry.day): \(formatTokenCount(entry.tokens))")
                }
            }
            .frame(height: graphHeight, alignment: .bottom)
        }
    }

    private func barHeight(for tokens: Int) -> CGFloat {
        guard maxTokens > 0 else { return 1 }
        return max(1, graphHeight * CGFloat(tokens) / CGFloat(maxTokens))
    }
}
