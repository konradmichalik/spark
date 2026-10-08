import SwiftUI

/// The history screen (board 4): Limits or Volume, a range, the dot column graph with a
/// crosshair readout, and two facts about the range below.
struct HistoryScreen: View {
    let history: [UsageSnapshot]
    let rollups: [String: DailyRollup]

    @State private var mode: GraphMode = .limits
    @State private var range: GraphTimeRange = .sixHours

    private static let chartHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PaperSegments(selection: modeBinding, options: GraphMode.allCases, label: "Graph")
                Spacer(minLength: 8)
                PaperSegments(
                    selection: $range, options: mode == .volume ? GraphTimeRange.dayGranularityCases : GraphTimeRange.allCases,
                    style: .chips, label: "Range", spokenLabel: \.spokenLabel
                )
            }
            switch mode {
            case .limits: limits
            case .volume: volume
            }
        }
    }

    /// Volume has no range below a day, so switching to it moves a shorter range to seven days
    /// in the same change instead of one render later.
    private var modeBinding: Binding<GraphMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                if newMode == .volume, !GraphTimeRange.dayGranularityCases.contains(range) {
                    range = .sevenDays
                }
            }
        )
    }

    // MARK: - Limits

    @ViewBuilder
    private var limits: some View {
        let now = Date()
        let snapshots = history.filter { $0.timestamp > now.addingTimeInterval(-range.seconds) && $0.timestamp <= now }
        if snapshots.isEmpty {
            DetailNote(text: "No history for this range yet. Spark records a point with every update.")
        } else {
            let columns = HistoryColumns.make(snapshots, now: now, window: range.seconds, count: range.columnCount)
            let summary = HistorySummary.make(snapshots)
            VStack(alignment: .leading, spacing: 8) {
                DotColumnsChart(columns: columns, isDetailed: true) {
                    HistoryHover.text(for: $0, in: columns, includesDate: range.spansDays)
                }
                .frame(height: Self.chartHeight)
                .accessibilityElement()
                .accessibilityLabel("Usage history, \(range.spokenLabel)")
                .accessibilityValue(limitsValue(snapshots, summary))
                HistoryAxisLabels(labels: HistoryAxis.labels(
                    items: HistoryLayout.items(columns), columns: columns, includesDate: range.spansDays
                ))
                HistoryLegend().padding(.top, 2)
            }
            summaryCard(limitsFacts(summary))
        }
    }

    private func limitsValue(_ snapshots: [UsageSnapshot], _ summary: HistorySummary) -> String {
        let parts = [
            snapshots.last.map { "Session now \(UsageFormat.percent($0.sessionUtilization)), week \(UsageFormat.percent($0.weeklyUtilization))" },
            summary.peakSession.map { "Session peak \(UsageFormat.percent($0))" }
        ]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }

    private func limitsFacts(_ summary: HistorySummary) -> [StatFact] {
        var facts: [StatFact] = []
        if let peak = summary.peakSession {
            facts.append(StatFact(
                label: "Peak session", parts: NumberParts(number: String(Int(peak.rounded())), unit: "%"),
                tooltip: "The highest session value in this range."
            ))
        }
        if let peak = summary.peakWeek {
            facts.append(StatFact(
                label: "Peak week", parts: NumberParts(number: String(Int(peak.rounded())), unit: "%"),
                tooltip: "The highest weekly value in this range. A weekly reset does not lower it."
            ))
        }
        return facts
    }

    // MARK: - Volume

    @ViewBuilder
    private var volume: some View {
        let days = VolumeDaySeries.build(rollups: rollups, timeRange: range)
        if days.allSatisfy(\.isEmpty) {
            DetailNote(text: "No daily totals for this range yet. A day is added once it has ended.")
        } else {
            let columns = VolumeColumns.make(days)
            let summary = VolumeSummary.make(days)
            VStack(alignment: .leading, spacing: 8) {
                DotColumnsChart(columns: columns, isDetailed: true) {
                    VolumeHover.text(for: $0, days: days, columns: columns)
                }
                .frame(height: Self.chartHeight)
                .accessibilityElement()
                .accessibilityLabel("Daily tokens, \(range.spokenLabel)")
                .accessibilityValue("\(formatTokenCount(summary.total)) tokens in total")
                HistoryAxisLabels(labels: HistoryAxis.labels(items: HistoryLayout.items(columns), columns: columns, includesDate: true))
            }
            summaryCard(volumeFacts(summary))
        }
    }

    private func volumeFacts(_ summary: VolumeSummary) -> [StatFact] {
        var facts = [StatFact(
            label: "Tokens", parts: UsageFormat.tokens(summary.total),
            tooltip: TokenWording.volume
        )]
        if let average = summary.dailyAverage {
            facts.append(StatFact(label: "Daily average", parts: UsageFormat.tokens(average)))
        }
        return facts
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryCard(_ facts: [StatFact]) -> some View {
        if !facts.isEmpty {
            PaperCard {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in fact }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }
}
