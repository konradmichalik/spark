import SwiftUI

extension StatsPeriod {
    var spokenLabel: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .all: "All time"
        }
    }
}

/// The Claude Statistics screen (board 6): period, four Doto tiles with API cost as an
/// estimate, and the top projects as dot bars.
struct ClaudeStatisticsScreen: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeriodSwitch(period: state.statsPeriod, onSelect: state.setStatsPeriod)
            if let live = state.liveStats {
                Group {
                    StatTileGrid(facts: facts(live))
                    if state.showProjectBreakdown {
                        RankedList(title: "TOP PROJECTS", noun: "projects", entries: projects(live))
                    }
                }
                .opacity(state.isLoadingStats ? 0.5 : 1)
            } else if state.isBuildingTranscriptCache {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    DetailNote(text: "Reading your Claude Code history. The first run can take a minute.")
                }
                .accessibilityElement(children: .combine)
            } else if !state.isLoadingStats {
                DetailNote(text: "No local activity in this period.")
            }
        }
    }

    private func facts(_ live: LiveStats) -> [StatFact] {
        var facts = [
            StatFact(label: "Messages", parts: UsageFormat.count(live.messageCount)),
            StatFact(label: "Sessions", parts: UsageFormat.count(live.sessionCount)),
            StatFact(
                label: "Tokens", parts: UsageFormat.tokens(live.realTokens),
                tooltip: TokenWording.withBreakdown(TokenWording.claude, live.tokenBreakdown)
            )
        ]
        if state.showApiCost, let cost = state.liveCost {
            let parts = UsageFormat.cost(cost.total)
            facts.append(StatFact(
                label: "API cost", parts: parts, prefix: "\u{2248}", tooltip: StatisticsText.costTooltip(cost),
                spokenValue: "about \(formatCost(cost.total))"
            ))
        }
        return facts
    }

    private func projects(_ live: LiveStats) -> [RankedEntry] {
        let ranked = live.topProjects(limit: live.projectTotals.count)
        let largest = ranked.first?.tokens ?? 0
        let costs = state.showApiCost ? state.liveCost?.byProject : nil
        return ranked.map { project in
            RankedEntry(
                id: project.key, name: project.displayName, tokens: project.tokens,
                share: StatisticsText.share(project.tokens, of: largest),
                tooltip: StatisticsText.projectTooltip(tokens: project.tokens, cost: costs?[project.key]), path: project.cwd
            )
        }
    }
}

/// The Codex Statistics screen: the same structure with Codex's own fields, top models in
/// place of top projects. Codex has no price list, so there is no API cost.
struct CodexStatisticsScreen: View {
    @ObservedObject var codex: CodexState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeriodSwitch(period: codex.statsPeriod, onSelect: codex.setStatsPeriod)
            if let stats = codex.stats, stats.fileCount > 0 {
                StatTileGrid(facts: [
                    StatFact(label: "Messages", parts: UsageFormat.count(stats.messageCount)),
                    StatFact(label: "Sessions", parts: UsageFormat.count(stats.sessionCount)),
                    StatFact(label: "Tokens", parts: UsageFormat.tokens(stats.realTokens), tooltip: tokenBreakdown(stats))
                ])
                RankedList(title: "TOP MODELS", noun: "models", entries: models(stats))
            } else {
                DetailNote(text: "No local Codex activity in this period.")
            }
        }
    }

    private func tokenBreakdown(_ stats: CodexSessionStats) -> String {
        let input = "Input \(formatTokenCount(stats.inputTokens)) · Cached \(formatTokenCount(stats.cachedInputTokens))"
        let output = "Output \(formatTokenCount(stats.outputTokens)) · Reasoning \(formatTokenCount(stats.reasoningTokens))"
        return TokenWording.withBreakdown(TokenWording.codex, "\(input)\n\(output)")
    }

    private func models(_ stats: CodexSessionStats) -> [RankedEntry] {
        let ranked = StatisticsText.rankedModels(stats)
        let largest = ranked.first?.tokens ?? 0
        return ranked.map { model in
            RankedEntry(
                id: model.name, name: model.name, tokens: model.tokens, share: StatisticsText.share(model.tokens, of: largest),
                tooltip: StatisticsText.projectTooltip(tokens: model.tokens, cost: nil), path: nil
            )
        }
    }
}

/// Today, 7 days, 30 days or all time. Writes through `onSelect`, which reloads the numbers.
private struct PeriodSwitch: View {
    let period: StatsPeriod
    let onSelect: (StatsPeriod) -> Void

    var body: some View {
        PaperSegments(
            selection: Binding(get: { period }, set: { onSelect($0) }), options: StatsPeriod.allCases,
            fillsWidth: true, label: "Period", spokenLabel: \.spokenLabel
        )
    }
}

/// Stat tiles two to a row; an odd last tile takes the whole row.
private struct StatTileGrid: View {
    let facts: [StatFact]

    var body: some View {
        let rows = stride(from: 0, to: facts.count, by: 2).map { Array(facts[$0..<min($0 + 2, facts.count)]) }
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        PaperCard {
                            rows[row][column]
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }
}

struct RankedEntry: Identifiable {
    let id: String
    let name: String
    let tokens: Int
    let share: Double
    let tooltip: String
    let path: String?
}

/// A ranked list with a dot bar per entry, the first four shown and the rest in place behind
/// "Show N more". A long expanded list scrolls instead of growing the popover.
private struct RankedList: View {
    let title: String
    let noun: String
    let entries: [RankedEntry]

    @State private var isExpanded = false

    private static let visibleLimit = 4
    private static let scrollThreshold = 10

    var body: some View {
        if !entries.isEmpty {
            let more = ShowMore(total: entries.count, limit: Self.visibleLimit)
            let visible = Array(entries.prefix(more.visibleCount(expanded: isExpanded)))
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(text: title)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Top \(noun)")
                if visible.count > Self.scrollThreshold {
                    ScrollView { rows(visible) }.frame(maxHeight: 230)
                } else {
                    rows(visible)
                }
                ShowMoreRow(more: more, isExpanded: $isExpanded)
            }
        }
    }

    private func rows(_ visible: [RankedEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visible) { entry in
                RankedRow(entry: entry)
            }
        }
    }
}

private struct RankedRow: View {
    let entry: RankedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(formatTokenCount(entry.tokens))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
            }
            DotBar(value: entry.share, pitch: 4, dotSize: 2.6)
                .frame(height: 6)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .tooltip(entry.tooltip, title: entry.name, delay: .quick)
        .pathActions(entry.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityValue(entry.tooltip)
    }
}
