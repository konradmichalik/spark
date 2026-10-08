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
        let averages = StatisticsAverages(
            activeDays: live.activeDayCount, messages: live.messageCount, sessions: live.sessionCount, tokens: live.realTokens
        )
        var facts = [
            StatFact(label: "Messages", parts: UsageFormat.count(live.messageCount), tooltip: averages.messages ?? ""),
            StatFact(label: "Sessions", parts: UsageFormat.count(live.sessionCount), tooltip: averages.sessions ?? ""),
            StatFact(
                label: "Tokens", parts: UsageFormat.tokens(live.realTokens),
                tooltip: TokenWording.withBreakdown(TokenWording.claude, live.tokenBreakdown, average: averages.tokens)
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
        let costs = state.showApiCost ? state.liveCost?.byProject : nil
        return ranked.map { project in
            RankedEntry(
                id: project.key, name: project.displayName, tokens: project.tokens,
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
                StatTileGrid(facts: facts(stats))
                RankedList(title: "TOP MODELS", noun: "models", entries: models(stats))
            } else {
                DetailNote(text: "No local Codex activity in this period.")
            }
        }
    }

    private func facts(_ stats: CodexSessionStats) -> [StatFact] {
        let averages = StatisticsAverages(
            activeDays: stats.activeDays.count, messages: stats.messageCount, sessions: stats.sessionCount, tokens: stats.realTokens
        )
        return [
            StatFact(label: "Messages", parts: UsageFormat.count(stats.messageCount), tooltip: averages.messages ?? ""),
            StatFact(label: "Sessions", parts: UsageFormat.count(stats.sessionCount), tooltip: averages.sessions ?? ""),
            StatFact(
                label: "Tokens", parts: UsageFormat.tokens(stats.realTokens),
                tooltip: tokenBreakdown(stats, average: averages.tokens)
            )
        ]
    }

    private func tokenBreakdown(_ stats: CodexSessionStats, average: String?) -> String {
        let input = "Input \(formatTokenCount(stats.inputTokens)) · Cached \(formatTokenCount(stats.cachedInputTokens))"
        let output = "Output \(formatTokenCount(stats.outputTokens)) · Reasoning \(formatTokenCount(stats.reasoningTokens))"
        return TokenWording.withBreakdown(TokenWording.codex, "\(input)\n\(output)", average: average)
    }

    private func models(_ stats: CodexSessionStats) -> [RankedEntry] {
        let ranked = StatisticsText.rankedModels(stats)
        return ranked.map { model in
            RankedEntry(
                id: model.name, name: model.name, tokens: model.tokens,
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
    let tooltip: String
    let path: String?
}

/// A ranked list in a card, laid out like the Active Sessions rows: name left, tokens right,
/// hairlines between rows. The first four show and the rest sit in place behind "Show N more".
/// A long expanded list scrolls instead of growing the popover.
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
                PaperCard {
                    VStack(spacing: 0) {
                        if visible.count > Self.scrollThreshold {
                            ScrollView { rows(visible) }.frame(maxHeight: 230)
                        } else {
                            rows(visible)
                        }
                        if more.isNeeded {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            ShowMoreRow(more: more, isExpanded: $isExpanded)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func rows(_ visible: [RankedEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                RankedRow(entry: entry)
            }
        }
    }
}

private struct RankedRow: View {
    let entry: RankedEntry

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(formatTokenCount(entry.tokens))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(isHovered ? Theme.dotTrack.opacity(0.35) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .tooltip(entry.tooltip, title: entry.name, delay: .quick)
        .pathActions(entry.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityValue(entry.tooltip)
    }
}
