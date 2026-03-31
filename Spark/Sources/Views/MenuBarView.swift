// swiftlint:disable file_length
import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                SparkLogoView(size: 20)
                Text("Spark")
                    .font(.headline)

                Text(state.accountTier.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(claudeOrange.opacity(0.15))
                    .foregroundColor(claudeOrange)
                    .clipShape(Capsule())

                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
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
                    projection: sessionProjection
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
                    criticalThreshold: state.criticalThreshold
                )
            }

            // Sonnet Usage
            if state.showSonnetUsage, let sonnet = state.usageData.weeklySonnet {
                UsageRow(
                    label: "Sonnet (Weekly)",
                    utilization: sonnet.utilization,
                    resetTime: sonnet.timeUntilReset,
                    resetDate: sonnet.resetsAtDate,
                    warningThreshold: state.warningThreshold,
                    criticalThreshold: state.criticalThreshold
                )
            }

            if state.usageData.session == nil && state.lastError == nil && !state.isLoading {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Error
            if let error = state.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Today's Stats
            if state.showStats {
                TodayStatsRow(liveStats: state.liveStats)
            }

            // Mini Graph
            if state.showGraph, !state.history.isEmpty {
                UsageGraphView(history: state.history)
                Divider()
            }

            // Footer
            HStack {
                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await state.fetchUsage() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }

                Text("Updated: \(timeAgo(state.usageData.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

// MARK: - Today Stats Row

struct TodayStatsRow: View {
    let liveStats: LiveDayStats?

    var body: some View {
        if let live = liveStats {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "number.square")
                        .font(.caption2)
                        .foregroundColor(claudeOrange)
                    Text("Stats (today)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                StatsLine(label: "Messages", value: "\(live.messageCount)")
                StatsLine(label: "Sessions", value: "\(live.sessionCount)")
                StatsLine(label: "Tokens", value: live.formattedTokens)
            }

            Divider()
        }
    }
}

private struct StatsLine: View {
    let label: String
    let value: String

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

    private var iconName: String {
        if label.hasPrefix("Session") { return "bolt.fill" }
        if label.hasPrefix("Weekly") { return "calendar" }
        if label.hasPrefix("Sonnet") { return "wand.and.stars" }
        return "chart.bar.fill"
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
                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundColor(claudeOrange)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if projectionTitle != nil {
                    Button(action: { showProjectionPopover.toggle() }, label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 9))
                            .foregroundColor(projectionIconColor)
                            .frame(width: 18, height: 18)
                            .background(projectionIconColor.opacity(0.12))
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .popover(isPresented: $showProjectionPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = projectionTitle {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .foregroundColor(projectionIconColor)
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
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
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
                    projection: projection
                )
                .frame(height: 6)

                Text("\(Int(utilization))%")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(color)
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
            }
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack {
            Image(systemName: state.status.emoji)
                .foregroundColor(Theme.sparkOrange)
            Text("Claude: \(state.status.displayName)")
                .font(.caption)

            Spacer()

            if !state.claudeCodeStatus.isHealthy {
                // swiftlint:disable:next force_unwrapping
                Link(destination: URL(string: "https://status.claude.com")!) {
                    HStack(spacing: 2) {
                        Text("Code: \(state.claudeCodeStatus.displayName)")
                            .font(.caption2)
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.sparkOrange)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
