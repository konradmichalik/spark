import AppKit
import SwiftUI

private let claudeOrange = Theme.sparkOrange

// MARK: - Stats Row

struct StatsRow: View {
    let liveStats: LiveStats?
    let period: StatsPeriod
    let isLoading: Bool
    let isBuildingCache: Bool
    let showProjectBreakdown: Bool
    let cost: CostSummary?
    let onSelectPeriod: (StatsPeriod) -> Void

    private static let density = SectionDensity.compact

    private static func costTooltip(_ cost: CostSummary) -> String {
        let estimate = "Estimated at public pay-as-you-go API prices, not what the subscription costs."
        guard !cost.unpricedModels.isEmpty else { return estimate }
        return estimate + " No price for \(cost.unpricedModels.joined(separator: ", ")), not included."
    }

    var body: some View {
        if liveStats != nil || isLoading {
            VStack(alignment: .leading, spacing: Self.density.headerGap) {
                header
                SectionCard(density: Self.density) {
                    if let live = liveStats {
                        StatsLine(label: "Messages", value: "\(live.messageCount)")
                        StatsLine(label: "Sessions", value: "\(live.sessionCount)")
                        StatsLine(label: "Tokens", value: live.formattedTokens, tooltip: live.tokenBreakdown)
                        if let cost {
                            StatsLine(label: "API cost", value: "≈ \(formatCost(cost.total))", tooltip: Self.costTooltip(cost))
                        }

                        if showProjectBreakdown {
                            ProjectBreakdownDisclosure(liveStats: live, costByProject: cost?.byProject)
                        }
                    } else if isBuildingCache {
                        cacheBuildHint
                    }
                }
            }
            .opacity(isLoading && liveStats != nil ? 0.5 : 1)
        }
    }

    /// The first scan after an install or update reads every transcript and can take a minute,
    /// with Stats and Active Sessions empty meanwhile. Says so instead of leaving a blank card.
    private var cacheBuildHint: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Reading your Claude Code history. The first run can take a minute.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Wraps `onSelectPeriod` rather than binding straight to a `period` property: `SegmentPicker`
    /// needs a `Binding`, but the caller's `onSelectPeriod` (`AppState.setStatsPeriod`) guards
    /// against a no-op write and triggers `refreshLiveStats()`. A raw property binding would skip
    /// that refresh and leave the numbers stale after every period switch.
    private var periodBinding: Binding<StatsPeriod> {
        Binding(get: { period }, set: { onSelectPeriod($0) })
    }

    private var header: some View {
        SectionHeader("Stats", icon: .reportAnalytics, density: Self.density) {
            SegmentPicker(selection: periodBinding, options: StatsPeriod.allCases)
        }
    }
}

private struct StatsLine: View {
    let label: String
    let value: String
    var tooltip: String?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.primary)
        }
        .tooltip(tooltip)
        .accessibilityHint(tooltip ?? "")
    }
}

// MARK: - Project Breakdown Disclosure

/// Top projects by token volume for the currently selected Stats period, nested inside the Stats
/// card rather than as its own section — the ranking already tracks whichever period is
/// selected above it, so visually it reads as one more Stats line rather than an unrelated block.
/// Collapsed by default: unlike the always-visible Messages/Sessions/Tokens lines, a project
/// breakdown is the kind of detail someone drills into occasionally, not on every glance.
private struct ProjectBreakdownDisclosure: View {
    let liveStats: LiveStats
    let costByProject: [String: Double]?
    @State private var isExpanded = false
    @State private var showAll = false

    /// Beyond this, the list keeps growing with the number of distinct projects in the period
    /// (up to dozens on `All`) — loading only this many by default keeps the common case cheap
    /// to render, with the rest a single tap away via "Show all".
    private static let collapsedLimit = 5
    /// Bounds the fully-expanded list's height once "Show all" is tapped, so a period with many
    /// projects scrolls internally instead of growing the popover without limit.
    private static let scrollCapHeight: CGFloat = 160
    private static let animation = Animation.easeInOut(duration: 0.2)

    private var ranked: [ProjectUsage] {
        liveStats.topProjects(limit: liveStats.projectTotals.count)
    }

    private var maxTokens: Int { ranked.first?.tokens ?? 1 }

    var body: some View {
        if !ranked.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    content
                        .padding(.top, 4)
                }
            }
            .padding(.top, 2)
        }
    }

    /// A `Button` rather than `.onTapGesture` — a tap gesture exposes no keyboard focus or
    /// activation on macOS, which would leave keyboard-only and VoiceOver users unable to expand
    /// this section at all. The full row is one tap target via `contentShape`, not just the label
    /// text, so clicking anywhere across its width works.
    ///
    /// No icon, no uppercase: this is a tappable row, not a section header, and needs to read as
    /// neither the Stats heading above it nor one of its plain content lines. The resting
    /// background is what signals "tappable" instead.
    ///
    /// The inner `+6`/outer `-6` horizontal padding pair cancels only for the size reported
    /// upward to the card's `VStack` — not for the background drawn around the padded label. So
    /// the label text still lands on the same left edge as the `StatsLine` rows above it (no
    /// layout shift), while the highlight itself bleeds ~6pt past that edge on each side, the way
    /// a resting selection highlight surrounds its label rather than displacing it. That bleed is
    /// horizontal only: the card's 10pt vertical clearance is untouched, so the 10pt corner curve
    /// is never entered.
    private var header: some View {
        Button {
            withAnimation(Self.animation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Text("Top Projects")
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                Spacer()
                TablerIconView(.chevronRight, size: 10)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .padding(.horizontal, -6)
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    @ViewBuilder
    private var content: some View {
        if showAll {
            ScrollView {
                projectList(ranked)
            }
            .frame(maxHeight: Self.scrollCapHeight)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                projectList(Array(ranked.prefix(Self.collapsedLimit)))

                if ranked.count > Self.collapsedLimit {
                    Button {
                        withAnimation(Self.animation) {
                            showAll = true
                        }
                    } label: {
                        Text("Show all \(ranked.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func projectList(_ projects: [ProjectUsage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(projects) { project in
                ProjectLine(project: project, maxTokens: maxTokens, cost: costByProject?[project.key])
            }
        }
    }
}

private struct ProjectLine: View {
    let project: ProjectUsage
    let maxTokens: Int
    let cost: Double?

    private var share: CGFloat {
        maxTokens > 0 ? CGFloat(project.tokens) / CGFloat(maxTokens) : 0
    }

    var body: some View {
        // Only a context menu, no left-click action: unlike Active Sessions, these rows have no
        // primary click behavior to begin with, so adding one is purely additive.
        if let cwd = project.cwd {
            content.contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
                }
                Button("Open in Terminal") {
                    openInTerminal(cwd)
                }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cwd, forType: .string)
                }
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(project.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let cost {
                    Text(formatCost(cost))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(formatTokenCount(project.tokens))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(claudeOrange)
                        .frame(width: geo.size.width * share)
                }
            }
            .frame(height: 3)
        }
    }
}

/// Launches Terminal.app at `path` via `/usr/bin/open`, rather than shelling out through `zsh -c`
/// (see `CLIVersionClient.readLocalVersion`) — arguments passed as an array need no shell
/// quoting, so a project path containing spaces can't break this. Fire-and-forget: nothing here
/// needs the launched process's exit status.
private func openInTerminal(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Terminal", path]
    try? process.run()
}
