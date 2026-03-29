import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var usageService: UsageService
    @EnvironmentObject var statusService: StatusService
    @AppStorage("showSonnetUsage") private var showSonnetUsage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                ClaudeLogoShape()
                    .fill(Color(nsColor: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))) // #D97757
                    .frame(width: 16, height: 16)
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                if usageService.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: {
                        Task { await usageService.fetchUsage() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
            }

            // Status - only show when there's a problem
            if !statusService.status.isHealthy {
                Divider()
                StatusRow(statusService: statusService)
            }

            Divider()

            // Session Usage
            if let session = usageService.usageData.session {
                UsageRow(
                    label: "Session (5h)",
                    utilization: session.utilization,
                    resetTime: session.timeUntilReset
                )
            }

            // Weekly Usage
            if let weekly = usageService.usageData.weekly {
                UsageRow(
                    label: "Weekly (7 days)",
                    utilization: weekly.utilization,
                    resetTime: weekly.timeUntilReset
                )
            }

            // Sonnet Usage
            if showSonnetUsage, let sonnet = usageService.usageData.weeklySonnet {
                UsageRow(
                    label: "Sonnet (Weekly)",
                    utilization: sonnet.utilization,
                    resetTime: sonnet.timeUntilReset
                )
            }

            if usageService.usageData.session == nil && usageService.error == nil && !usageService.isLoading {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Error
            if let error = usageService.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Mini Graph
            if !usageService.history.isEmpty {
                UsageGraphView(history: usageService.history)
                    .frame(height: 60)
                Divider()
            }

            // Footer: Last Updated + Actions
            HStack {
                Text("Updated: \(timeAgo(usageService.usageData.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Quit")
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

// MARK: - Usage Row

struct UsageRow: View {
    let label: String
    let utilization: Double
    let resetTime: String?

    private var color: Color {
        let warning = UserDefaults.standard.object(forKey: "warningThreshold") as? Double ?? 75
        let critical = UserDefaults.standard.object(forKey: "criticalThreshold") as? Double ?? 90
        if utilization >= critical { return .red }
        if utilization >= warning { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let resetTime {
                    Text("Reset: \(resetTime)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(color)

                Text("\(Int(utilization))%")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    @ObservedObject var statusService: StatusService

    var body: some View {
        HStack {
            Image(systemName: statusService.status.emoji)
                .foregroundColor(.orange)
            Text("Claude: \(statusService.status.displayName)")
                .font(.caption)

            Spacer()

            if !statusService.claudeCodeStatus.isHealthy {
                Text("Code: \(statusService.claudeCodeStatus.displayName)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
}
