import SwiftUI

private let graphHeight: CGFloat = 80
private let xAxisHeight: CGFloat = 14
/// Caps how wide a single bar can get on a short range (e.g. 7 days spread over the full 276pt
/// popover width) — bars center within their lane rather than stretching to fill it.
private let maxBarWidth: CGFloat = 20

/// Daily token volume from permanent rollups — meaningful beyond the `Today`/`7d`/`30d` window
/// that live transcript stats can reach, since rollups outlive Claude Code's transcript
/// retention window and the snapshot ring buffer's cap alike.
struct VolumeGraphView: View {
    let rollups: [String: DailyRollup]
    let timeRange: GraphTimeRange
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @State private var hoveredDay: String?

    private var days: [(day: String, tokens: Int)] {
        let cutoffDay = TranscriptCache.dayKey(for: Date().addingTimeInterval(-timeRange.seconds))
        return rollups
            .filter { $0.key >= cutoffDay }
            .map { (day: $0.key, tokens: $0.value.totalTokens) }
            .sorted { $0.day < $1.day }
    }

    private var maxTokens: Int { days.map(\.tokens).max() ?? 0 }

    private var hoveredEntry: (day: String, tokens: Int)? {
        days.first { $0.day == hoveredDay }
    }

    var body: some View {
        if days.isEmpty {
            Text("No rollup data yet for this range")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(height: graphHeight + xAxisHeight, alignment: .center)
                .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                bars
                dayAxisLabels
            }
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days, id: \.day) { entry in
                bar(for: entry)
            }
        }
        .frame(height: graphHeight, alignment: .bottom)
        // Anchored inside the chart's own top edge, not above it — offsetting further up would
        // push the tooltip past this view's bounds and into the "History" header above it.
        .overlay(alignment: .topLeading) { hoverTooltip }
    }

    private func bar(for entry: (day: String, tokens: Int)) -> some View {
        let isHovered = entry.day == hoveredDay
        return UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.sparkOrange.opacity(isHovered ? 1 : 0.85),
                        Theme.sparkOrange.opacity(isHovered ? 0.7 : 0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: barHeight(for: entry.tokens))
            .frame(maxWidth: maxBarWidth)
            .frame(maxWidth: .infinity)
            .onHover { isHovering in
                hoveredDay = isHovering ? entry.day : (hoveredDay == entry.day ? nil : hoveredDay)
            }
    }

    @ViewBuilder
    private var hoverTooltip: some View {
        if let hoveredEntry {
            HStack(spacing: 4) {
                Text(formatAxisDay(hoveredEntry.day))
                    .foregroundColor(.secondary)
                Text(formatTokenCount(hoveredEntry.tokens))
                    .fontWeight(.semibold)
            }
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .adaptiveBackground(reduceTransparency: reduceTransparency)
            .fixedSize()
        }
    }

    /// First, middle, and last day in the visible range — mirrors `UsageGraphView`'s three-tick
    /// x-axis so both graph modes read consistently.
    private var dayAxisLabels: some View {
        HStack {
            Text(formatAxisDay(days[0].day))
            if days.count > 2 {
                Spacer()
                Text(formatAxisDay(days[days.count / 2].day))
            }
            Spacer()
            Text(formatAxisDay(days[days.count - 1].day))
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundColor(.secondary)
        .frame(height: xAxisHeight)
    }

    private func barHeight(for tokens: Int) -> CGFloat {
        guard maxTokens > 0 else { return 1 }
        return max(1, graphHeight * CGFloat(tokens) / CGFloat(maxTokens))
    }

    /// `day` is always `"yyyy-MM-dd"` (see `TranscriptCache.dayKey`) — sliced directly rather
    /// than round-tripped through `DateFormatter`, since the format never varies.
    private func formatAxisDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[2]).\(parts[1])"
    }
}
