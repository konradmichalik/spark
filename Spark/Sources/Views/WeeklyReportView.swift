import SwiftUI

/// A dedicated window (opened alongside Settings) summarizing the current week's local token
/// usage against the previous week — built from the same persisted `DailyRollup` data the Volume
/// chart uses, so it needs no live re-scan beyond the top-projects lookup.
struct WeeklyReportView: View {
    static let windowID = "weeklyReport"

    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let report = state.weeklyReport, report.hasData {
                totalsSection(report)
                Divider()
                modelSplitSection(report)
                if !report.topProjects.isEmpty {
                    Divider()
                    topProjectsSection(report)
                }
            } else if state.weeklyReport == nil {
                // Covers both the gap before `.task` fires and the load itself — the request
                // never resolves to an empty report, only to nil-until-loaded or a real one.
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                Text("No usage data yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 420)
        // Dims stale numbers while a reopen re-scans, instead of showing them un-dimmed.
        .opacity(state.isLoadingWeeklyReport ? 0.5 : 1)
        .task {
            state.loadWeeklyReport()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .foregroundColor(Theme.sparkOrange)
            Text("Weekly Report")
                .font(.custom("InstrumentSerif-Regular", size: 15))
            Spacer()
        }
    }

    private func totalsSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Week")
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatTokenCount(report.currentWeekTokens))
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                if let trend = report.trendPercent {
                    TrendBadge(percent: trend)
                }
            }
            Text("tokens vs. \(formatTokenCount(report.previousWeekTokens)) last week")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func modelSplitSection(_ report: WeeklyReport) -> some View {
        let rows = Self.modelRows(from: report.modelTotals)

        return VStack(alignment: .leading, spacing: 6) {
            Text("By Model")
                .font(.caption2)
                .foregroundColor(.secondary)
            if rows.isEmpty {
                Text("No model usage this week")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTokenCount(row.tokens))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
        }
    }

    private struct ModelRow: Identifiable {
        let id: String
        let label: String
        let tokens: Int
    }

    private static func modelRows(from modelTotals: [String: Int]) -> [ModelRow] {
        let families: [(ModelFamily, String)] = [(.sonnet, "Sonnet"), (.opus, "Opus"), (.fable, "Fable")]
        var rows: [ModelRow] = []
        for (family, label) in families {
            var tokens = 0
            for (rawId, value) in modelTotals where ModelFamily.family(forRawModelId: rawId) == family {
                tokens += value
            }
            if tokens > 0 {
                rows.append(ModelRow(id: label, label: label, tokens: tokens))
            }
        }
        return rows
    }

    private func topProjectsSection(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Projects")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(report.topProjects) { project in
                HStack {
                    Text(project.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(formatTokenCount(project.tokens))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

private struct TrendBadge: View {
    let percent: Double

    private enum Direction { case up, down, flat }

    /// Direction is decided from the rounded, displayed value, not the raw percent — otherwise
    /// e.g. -0.3% rounds to "0%" in the label while still rendering a down arrow.
    private var roundedPercent: Int { Int(percent.rounded()) }

    private var direction: Direction {
        if roundedPercent > 0 { return .up }
        if roundedPercent < 0 { return .down }
        return .flat
    }

    private var symbolName: String {
        switch direction {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "arrow.right"
        }
    }

    private var accessibilityText: String {
        switch direction {
        case .up: "Up \(roundedPercent)% from last week"
        case .down: "Down \(abs(roundedPercent))% from last week"
        case .flat: "Unchanged from last week"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbolName)
            Text("\(abs(roundedPercent))%")
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}
