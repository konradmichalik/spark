import SwiftUI

/// A micro label over a figure, read as one element by VoiceOver, with the secondary facts in
/// its tooltip. The shape shared by the report's totals and the activity figures.
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

/// A total over a Doto value, with the secondary facts in its tooltip (board 11).
struct ReportTotal: View {
    let label: String
    let parts: NumberParts
    var prefix: String?
    var tooltip: String?
    var spokenValue: String?

    var body: some View {
        ReportFigure(
            label: label, tooltip: tooltip,
            spoken: spokenValue ?? [prefix, parts.number, parts.unit].compactMap { $0 }.joined(separator: " ")
        ) {
            DotoValue(parts: parts, prefix: prefix, size: 40)
        }
    }
}

/// The day peaks as dot columns with the week as the red line, as in History.
struct PaceSection: View {
    let title: String
    let days: [PaceDay]
    let emptyText: String

    var body: some View {
        let columns = PaceColumns.make(days)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MicroLabel(text: title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                legend
            }
            if days.contains(where: \.hasData) {
                DotColumnsChart(columns: columns, isDetailed: true) { PaceColumns.hover($0, in: days) }
                    .frame(height: 140)
                    .accessibilityElement()
                    .accessibilityLabel("Pace")
                    .accessibilityValue(summary)
                HistoryAxisLabels(
                    labels: HistoryAxis.labels(items: HistoryLayout.items(columns), columns: columns, includesDate: true)
                )
            } else {
                DetailNote(text: emptyText)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(Theme.ink.opacity(0.3)).frame(width: 6, height: 6)
                Text("Session")
            }
            HStack(spacing: 5) {
                Capsule().fill(Theme.accent).frame(width: 12, height: 2)
                Text("Week")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityHidden(true)
    }

    private var summary: String {
        let sessions = days.compactMap(\.sessionUtilization)
        let weeks = days.compactMap(\.weeklyUtilization)
        let parts = [
            sessions.max().map { "Highest session peak \(UsageFormat.percent($0))" },
            weeks.last.map { "week at \(UsageFormat.percent($0)) on the last day with data" }
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

/// Each model family's share of the period's tokens as a dot bar.
struct ModelShareSection: View {
    let rows: [ModelRow]
    let emptyText: String

    var body: some View {
        let total = rows.reduce(0) { $0 + $1.tokens }
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "BY MODEL")
                .accessibilityAddTraits(.isHeader)
            if rows.isEmpty {
                DetailNote(text: emptyText)
            }
            ForEach(rows) { row in
                let share = StatisticsText.share(row.tokens, of: total)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.label)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(UsageFormat.percent(share))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    DotBar(value: share, pitch: 4, dotSize: 2.6)
                        .frame(height: 6)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .tooltip(row.versionSummary, title: row.label, delay: .quick)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue("\(UsageFormat.percent(share)), \(formatTokenCount(row.tokens)) tokens")
            }
        }
    }
}

struct ReportEntry: Identifiable {
    let id: String
    let name: String
    var detail: String?
    let value: String
    var tooltip: String?
    var path: String?
}

/// A ranked list, the first entries shown and the rest behind "Show N more"
/// (docs/design/rules.md, "Navigation"). Rows are spaced, not ruled: there is no card to hold
/// hairlines here.
struct ReportList: View {
    let title: String
    let entries: [ReportEntry]

    @State private var isExpanded = false

    var body: some View {
        let more = ShowMore(total: entries.count, limit: ReportText.listLimit)
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel(text: title)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries.prefix(more.visibleCount(expanded: isExpanded))) { entry in
                row(entry)
            }
            ShowMoreRow(more: more, isExpanded: $isExpanded)
        }
        .onChange(of: entries.map(\.id)) { isExpanded = false }
    }

    private func row(_ entry: ReportEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.value)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 34)
        .contentShape(Rectangle())
        .tooltip(entry.tooltip, title: entry.name, delay: .quick)
        .pathActions(entry.path)
        .accessibilityElement(children: .combine)
    }
}
