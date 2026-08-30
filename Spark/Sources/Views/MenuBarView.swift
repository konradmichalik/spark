// swiftlint:disable file_length
import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let sevenDays: TimeInterval = 7 * 24 * 3600

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                SparkLogoView(size: 20, isLoading: state.isLoading)
                Text("Spark")
                    .font(.custom("InstrumentSerif-Regular", size: 15))

                Text(state.accountTier.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(claudeOrange.opacity(0.15))
                    .foregroundColor(claudeOrange)
                    .clipShape(Capsule())

                Spacer()
                Button {
                    openWindow(id: WeeklyReportView.windowID)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    TablerIconView(.calendarMonth, size: 13, color: .secondary)
                }
                .buttonStyle(.borderless)
                .help("Usage Report")
                .accessibilityLabel("Usage Report")

                SettingsLink {
                    TablerIconView(.settings, size: 13, color: .secondary)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            // Status - only show when there's a problem
            if !state.status.isHealthy {
                Divider()
                StatusRow(state: state)
            }

            Divider()

            if state.usageDisplayStyle == "bars" {
                // Session Usage
                if let session = state.usageData.session {
                    let sessionProjection = state.showProjection
                        ? SessionProjection.calculate(
                            history: state.history,
                            currentUtilization: session.utilization,
                            resetsAt: session.resetsAtDate
                        )
                        : .insufficientData

                    UsageRow(
                        label: "Session (5h)",
                        utilization: session.utilization,
                        resetTime: session.timeUntilReset,
                        resetDate: session.resetsAtDate,
                        warningThreshold: state.warningThreshold,
                        criticalThreshold: state.criticalThreshold,
                        projection: sessionProjection,
                        pace: Pace.calculate(
                            utilization: session.utilization,
                            resetsAt: session.resetsAtDate,
                            windowLength: Self.fiveHours
                        )
                    )
                }

                // Weekly Usage
                if let weekly = state.usageData.weekly {
                    UsageRow(
                        label: "Weekly (7 days)",
                        utilization: weekly.utilization,
                        resetTime: weekly.timeUntilReset,
                        resetDate: weekly.resetsAtDate,
                        warningThreshold: state.warningThreshold,
                        criticalThreshold: state.criticalThreshold,
                        pace: Pace.calculate(
                            utilization: weekly.utilization,
                            resetsAt: weekly.resetsAtDate,
                            windowLength: Self.sevenDays
                        )
                    )
                }

                // Sonnet Usage
                if state.showSonnetUsage {
                    // `weeklySonnet` is nil when the account's plan doesn't report a
                    // Sonnet-specific weekly quota — falling back to a zeroed bucket there would
                    // draw an empty 0% bar that reads as "no usage" when it actually means "no
                    // such quota to measure against." Local token attribution, unlike the quota,
                    // always exists independently, so it's shown as a plain line instead.
                    if let sonnet = state.usageData.weeklySonnet {
                        UsageRow(
                            label: "Sonnet (Weekly)",
                            utilization: sonnet.utilization,
                            resetTime: sonnet.timeUntilReset,
                            resetDate: sonnet.resetsAtDate,
                            warningThreshold: state.warningThreshold,
                            criticalThreshold: state.criticalThreshold,
                            localTokens: formattedLocalTokens(state.liveStats, family: .sonnet),
                            pace: Pace.calculate(
                                utilization: sonnet.utilization,
                                resetsAt: sonnet.resetsAtDate,
                                windowLength: Self.sevenDays
                            )
                        )
                    } else if let localTokens = formattedLocalTokens(state.liveStats, family: .sonnet) {
                        LocalOnlyUsageRow(label: "Sonnet", localTokens: localTokens)
                    }
                }

                // Opus Usage
                if state.showOpusUsage {
                    if let opus = state.usageData.weeklyOpus {
                        UsageRow(
                            label: "Opus (Weekly)",
                            utilization: opus.utilization,
                            resetTime: opus.timeUntilReset,
                            resetDate: opus.resetsAtDate,
                            warningThreshold: state.warningThreshold,
                            criticalThreshold: state.criticalThreshold,
                            localTokens: formattedLocalTokens(state.liveStats, family: .opus),
                            pace: Pace.calculate(
                                utilization: opus.utilization,
                                resetsAt: opus.resetsAtDate,
                                windowLength: Self.sevenDays
                            )
                        )
                    } else if let localTokens = formattedLocalTokens(state.liveStats, family: .opus) {
                        LocalOnlyUsageRow(label: "Opus", localTokens: localTokens)
                    }
                }

                // Fable Usage
                if state.showFableUsage {
                    if let fable = state.usageData.weeklyFable {
                        UsageRow(
                            label: "Fable (Weekly)",
                            utilization: fable.utilization,
                            resetTime: fable.timeUntilReset,
                            resetDate: fable.resetsAtDate,
                            warningThreshold: state.warningThreshold,
                            criticalThreshold: state.criticalThreshold,
                            localTokens: formattedLocalTokens(state.liveStats, family: .fable),
                            pace: Pace.calculate(
                                utilization: fable.utilization,
                                resetsAt: fable.resetsAtDate,
                                windowLength: Self.sevenDays
                            )
                        )
                    } else if let localTokens = formattedLocalTokens(state.liveStats, family: .fable) {
                        LocalOnlyUsageRow(label: "Fable", localTokens: localTokens)
                    }
                }

                if state.usageData.session == nil && state.lastError == nil && !state.isLoading {
                    Text("No data available")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } else {
                let sessionProjection = state.showProjection
                    ? SessionProjection.calculate(
                        history: state.history,
                        currentUtilization: state.usageData.session?.utilization ?? 0,
                        resetsAt: state.usageData.session?.resetsAtDate
                    )
                    : .insufficientData

                UsageRingsView(
                    session: state.usageData.session,
                    weekly: state.usageData.weekly,
                    sonnet: state.usageData.weeklySonnet,
                    opus: state.usageData.weeklyOpus,
                    fable: state.usageData.weeklyFable,
                    showSonnet: state.showSonnetUsage,
                    showOpus: state.showOpusUsage,
                    showFable: state.showFableUsage,
                    showProjection: state.showProjection,
                    warningThreshold: state.warningThreshold,
                    criticalThreshold: state.criticalThreshold,
                    sessionProjection: sessionProjection,
                    displayStyle: state.usageDisplayStyle
                )
            }

            // Extra usage (pay-as-you-go) — subtle line, only when credits spent
            if let extra = state.usageData.extraUsage, extra.hasSpend,
               let spend = extra.formattedSpendWithLimit {
                HStack(spacing: 6) {
                    TablerIconView(.circlePlus, size: 11)
                    Text("Extra usage")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(spend)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Extra usage \(extra.spendAccessibilityValue ?? spend)")
            }

            // Reconnect prompt (token expired, ACL wiped by Claude Code)
            if state.needsReconnect {
                HStack(spacing: 6) {
                    TablerIconView(.refreshAlert, size: 12, color: .orange)
                    Text("Session expired")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Reconnect") {
                        state.reconnect()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundColor(Theme.sparkOrange)
                }
            }

            // Error
            if let error = state.lastError {
                HStack {
                    TablerIconView(.alertTriangle, size: 13, color: .orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Active Sessions
            if state.showActiveSessions {
                ActiveSessionsView(sessions: state.activeSessions)
            }

            // Stats
            if state.showStats {
                StatsRow(
                    liveStats: state.liveStats,
                    period: state.statsPeriod,
                    isLoading: state.isLoadingStats,
                    showProjectBreakdown: state.showProjectBreakdown,
                    onSelectPeriod: state.setStatsPeriod
                )
            }

            // Mini Graph
            if state.showGraph, !state.history.isEmpty {
                UsageGraphView(history: state.history, rollups: state.rollups)
                Divider()
            }

            // Footer
            HStack {
                RefreshButton(isLoading: state.isLoading) {
                    Task { await state.fetchUsage() }
                }

                Text("Updated: \(timeAgo(state.usageData.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    TablerIconView(.power, size: 12, color: .secondary)
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if state.reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .background(WindowResizer())
        .onAppear { state.startActiveSessionTicker() }
        .onDisappear { state.stopActiveSessionTicker() }
    }

    /// Local token attribution for a model family, or `nil` when there's nothing to show —
    /// omitted rather than rendered as "0" to avoid noise on every row that hasn't seen that
    /// model in the currently selected Stats period.
    private func formattedLocalTokens(_ liveStats: LiveStats?, family: ModelFamily) -> String? {
        guard let tokens = liveStats?.tokens(for: family), tokens > 0 else { return nil }
        return formatTokenCount(tokens)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

// MARK: - Stats Row

struct StatsRow: View {
    let liveStats: LiveStats?
    let period: StatsPeriod
    let isLoading: Bool
    let showProjectBreakdown: Bool
    let onSelectPeriod: (StatsPeriod) -> Void

    var body: some View {
        if liveStats != nil || isLoading {
            VStack(alignment: .leading, spacing: 4) {
                header

                if let live = liveStats {
                    StatsLine(label: "Messages", value: "\(live.messageCount)")
                    StatsLine(label: "Sessions", value: "\(live.sessionCount)")
                    StatsLine(label: "Tokens", value: live.formattedTokens, tooltip: live.tokenBreakdown)

                    if showProjectBreakdown {
                        ProjectBreakdownDisclosure(liveStats: live)
                    }
                }
            }
            .opacity(isLoading ? 0.5 : 1)

            Divider()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                TablerIconView(.reportAnalytics, size: 11, color: claudeOrange)
                Text("Stats")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(StatsPeriod.allCases, id: \.self) { candidate in
                    Button {
                        onSelectPeriod(candidate)
                    } label: {
                        Text(candidate.rawValue)
                            .font(.system(size: 10, weight: period == candidate ? .semibold : .regular))
                            .foregroundColor(period == candidate ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                period == candidate
                                    ? Color.primary.opacity(0.1)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
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
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
        }
        .help(tooltip ?? "")
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
    /// this section at all. The full row — icon, label, and trailing chevron — is one tap target
    /// via `contentShape`, not just the label text, so clicking anywhere across its width works.
    private var header: some View {
        Button {
            withAnimation(Self.animation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                TablerIconView(.folders, size: 11, color: claudeOrange)
                Text("Top Projects")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                TablerIconView(.chevronRight, size: 9)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
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
                ProjectLine(project: project, maxTokens: maxTokens)
            }
        }
    }
}

private struct ProjectLine: View {
    let project: ProjectUsage
    let maxTokens: Int

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

// MARK: - Local-Only Usage Row

/// Shown instead of `UsageRow` when the API doesn't report a Sonnet/Opus-specific weekly quota
/// for this account's plan — a bare label plus the local token count, with no percentage or bar
/// implying a quota that doesn't exist.
struct LocalOnlyUsageRow: View {
    let label: String
    let localTokens: String

    private var icon: TablerIcon {
        label == "Sonnet" ? .sparkles : .chartBar
    }

    var body: some View {
        HStack(spacing: 4) {
            TablerIconView(icon, size: 11, color: claudeOrange)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("· \(localTokens) local")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Usage Row

private let claudeOrange = Theme.sparkOrange

struct UsageRow: View {
    let label: String
    let utilization: Double
    let resetTime: String?
    let resetDate: Date?
    let warningThreshold: Double
    let criticalThreshold: Double
    var projection: ProjectionResult = .insufficientData
    /// Local token attribution for this bucket's model family, shown alongside the label — see
    /// `MenuBarView.formattedLocalTokens`. `nil` renders nothing, adding no vertical height.
    var localTokens: String?
    /// Pace for this bucket's window — see `Pace.calculate`. `nil` omits the marker entirely.
    var pace: Pace.Result?

    private var paceDescription: String? {
        guard let pace else { return nil }
        let percent = Int((pace.ratio * 100).rounded())
        let exhausts = pace.ratio > 1 ? "before" : "at or after"
        return "Pace: \(pace.tier.label) — \(percent)% of the on-track rate. At this rate, quota exhausts \(exhausts) reset."
    }

    private var icon: TablerIcon {
        if label.hasPrefix("Session") { return .activity }
        if label.hasPrefix("Weekly") { return .calendarMonth }
        if label.hasPrefix("Sonnet") { return .sparkles }
        return .chartBar
    }

    private var color: Color {
        if utilization >= criticalThreshold { return .red }
        if utilization >= warningThreshold { return .orange }
        return .green
    }

    @State private var showProjectionPopover = false
    @State private var showResetPopover = false

    private var projectionTitle: String? {
        switch projection {
        case .limitReached(let seconds):
            return "Limit in ~\(formatDuration(seconds))"
        case .safe(let projected):
            return "~\(Int(projected))% at reset"
        case .insufficientData:
            return nil
        }
    }

    private var projectionDetail: String? {
        switch projection {
        case .limitReached(let seconds):
            let rate = ratePerHour
            return "At the current rate of ~\(Int(rate))%/h, the session limit will be reached in ~\(formatDuration(seconds))."
        case .safe(let projected):
            let rate = ratePerHour
            return "At the current rate of ~\(Int(rate))%/h, usage will be ~\(Int(projected))% when the session resets."
        case .insufficientData:
            return nil
        }
    }

    private var ratePerHour: Double {
        switch projection {
        case .limitReached(let seconds):
            guard seconds > 0 else { return 0 }
            return (100 - utilization) / (seconds / 3600)
        case .safe(let projected):
            guard resetTime != nil else { return 0 }
            // Rough estimate: parse hours from reset string isn't clean, use projected delta
            let delta = projected - utilization
            return delta > 0 ? delta : 0
        case .insufficientData:
            return 0
        }
    }

    private var projectionIconColor: Color {
        switch projection {
        case .limitReached: return .red
        case .safe: return .secondary
        case .insufficientData: return .clear
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        seconds.shortDuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TablerIconView(icon, size: 11, color: claudeOrange)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let localTokens {
                    Text("· \(localTokens) local")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if projectionTitle != nil {
                    Button(action: { showProjectionPopover.toggle() }, label: {
                        TablerIconView(.chartLine, size: 9, color: projectionIconColor)
                            .frame(width: 18, height: 18)
                            .background(projectionIconColor.opacity(0.12))
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .popover(isPresented: $showProjectionPopover, arrowEdge: .bottom) {
                        VStack(spacing: 6) {
                            if let title = projectionTitle {
                                HStack(spacing: 4) {
                                    TablerIconView(.chartLine, size: 9, color: projectionIconColor)
                                    Text(title)
                                        .fontWeight(.medium)
                                }
                                .font(.caption)
                            }
                            if let detail = projectionDetail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(width: 220)
                    }
                }

                Spacer()
                if let resetTime {
                    Button(action: { showResetPopover.toggle() }, label: {
                        HStack(spacing: 4) {
                            TablerIconView(.history, size: 11)
                                .frame(width: 18, height: 18)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Circle())
                            Text(resetTime)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    })
                    .buttonStyle(.plain)
                    .popover(isPresented: $showResetPopover, arrowEdge: .bottom) {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                TablerIconView(.history, size: 11)
                                Text("Reset in \(resetTime)")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)

                            if let resetDate {
                                Text(resetDate, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(width: 220)
                    }
                }
            }

            HStack(spacing: 8) {
                ProjectedProgressBar(
                    utilization: utilization,
                    color: color,
                    projection: projection,
                    pace: pace
                )
                .frame(height: 6)
                .help(paceDescription ?? "")

                Text("\(Int(utilization))%")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(utilization >= warningThreshold ? color : .primary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Projected Progress Bar

struct ProjectedProgressBar: View {
    let utilization: Double
    let color: Color
    let projection: ProjectionResult
    /// Pace for this bucket's window, drawn as a colored marker on the bar. Fill left of the
    /// marker reads as under budget, fill right of it as over; the marker's color reflects
    /// `Pace.Tier`, from comfortably under budget to badly overspending. `nil` when pace can't be
    /// computed (see `Pace.calculate`), which simply omits the marker rather than drawing a
    /// misleading one.
    var pace: Pace.Result?

    private var projectedWidth: Double {
        switch projection {
        case .limitReached:
            return 100
        case .safe(let projected):
            return min(projected, 100)
        case .insufficientData:
            return 0
        }
    }

    private var projectionColor: Color {
        switch projection {
        case .limitReached:
            return .red
        case .safe:
            return .primary
        case .insufficientData:
            return .clear
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Opaque backing to prevent vibrancy bleed-through
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)

                // Projection background
                if projectedWidth > utilization {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(projectionColor.opacity(0.15))
                        .frame(width: geometry.size.width * min(projectedWidth, 100) / 100)
                }

                // Current utilization
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * min(utilization, 100) / 100)

                // Pace marker: where "on budget" would sit right now, colored by Pace.Tier.
                if let pace {
                    Rectangle()
                        .fill(Theme.paceColor(for: pace.tier))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * min(max(pace.elapsedFraction, 0), 1))
                }
            }
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            TablerIconView(state.status.icon, size: 13, color: Theme.sparkOrange)
            Text("Claude: \(state.status.displayName)")
                .font(.caption)

            Spacer()

            if !state.claudeCodeStatus.isHealthy {
                Link(destination: URL(string: "https://status.claude.com")!) {
                    HStack(spacing: 2) {
                        Text("Code: \(state.claudeCodeStatus.displayName)")
                            .font(.caption2)
                        TablerIconView(.externalLink, size: 9, color: Theme.sparkOrange)
                    }
                    .foregroundColor(Theme.sparkOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Window Resizer

/// Measures the SwiftUI content size via GeometryReader and forces the
/// hosting NSPanel to match, working around the MenuBarExtra resize bug.
struct WindowResizer: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size) { _, newSize in
                    resizeHostingWindow(to: newSize)
                }
                .onAppear {
                    resizeHostingWindow(to: proxy.size)
                }
        }
    }

    private func resizeHostingWindow(to size: CGSize) {
        DispatchQueue.main.async {
            guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) else { return }
            let contentRect = panel.contentRect(forFrameRect: panel.frame)
            let deltaHeight = size.height - contentRect.size.height
            var frame = panel.frame
            frame.origin.y -= deltaHeight
            frame.size.height += deltaHeight
            panel.setFrame(frame, display: true)
        }
    }
}

// MARK: - Refresh Button

struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            TablerIconView(.refresh, size: 12, color: .secondary)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
        .help(isLoading ? "Refreshing\u{2026}" : "Refresh")
        .task(id: isLoading) {
            guard isLoading else { return }
            while !Task.isCancelled {
                withAnimation(.linear(duration: 0.8)) {
                    rotation += 360
                }
                do {
                    try await Task.sleep(for: .seconds(0.8))
                } catch {
                    return
                }
            }
        }
    }
}
