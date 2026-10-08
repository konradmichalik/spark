import AppKit
import SwiftUI

/// All Codex limits for the "All limits" screen: the session and weekly windows, every
/// additional limit and the credit balance. `CodexUsage` maps onto `UsageData`, so the rows are
/// the same `UsageRow`s the Claude limits use.
struct CodexLimitsList: View {
    @ObservedObject var codex: CodexState
    let warningThreshold: Double
    let criticalThreshold: Double

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let sevenDays: TimeInterval = 7 * 24 * 3600

    var body: some View {
        SectionCard(density: .compact) {
            if let usage = codex.usage {
                windows(usage)
            } else if !codex.isLoading, !codex.needsSignIn {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            creditsRow
        }
    }

    @ViewBuilder
    private func windows(_ usage: CodexUsage) -> some View {
        let data = usage.usageData
        if let session = data.session {
            row("Session (5h)", session, windowLength: Self.fiveHours)
        }
        if let weekly = data.weekly {
            row("Weekly (7 days)", weekly, windowLength: Self.sevenDays)
        }
        ForEach(usage.additionalLimits) { limit in
            row(limit.label, limit.bucket, windowLength: TimeInterval(limit.windowSeconds))
        }
        if data.session == nil, data.weekly == nil, usage.additionalLimits.isEmpty {
            Text(usage.limitReached ? "Usage limit reached" : "No limits reported for this plan")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private func row(_ label: String, _ bucket: UsageBucket, windowLength: TimeInterval) -> some View {
        UsageRow(
            label: label,
            utilization: bucket.utilization,
            resetTime: bucket.timeUntilReset,
            resetDate: bucket.resetsAtDate,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            pace: Pace.calculate(utilization: bucket.utilization, resetsAt: bucket.resetsAtDate, windowLength: windowLength)
        )
    }

    @ViewBuilder
    private var creditsRow: some View {
        if let balance = codex.usage?.creditsBalance {
            HStack(spacing: 6) {
                TablerIconView(.circlePlus, size: 11)
                Text("Credits")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(balance)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Spark never refreshes the Codex token itself (that would sign the CLI out), so an expired
/// sign-in can only be fixed in the CLI.
struct CodexSignInPrompt: View {
    var body: some View {
        HStack(spacing: 6) {
            TablerIconView(.refreshAlert, size: 12, color: .orange)
            Text("Codex sign-in expired. Run codex login.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("codex login", forType: .string)
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundColor(Theme.sparkOrange)
            .accessibilityLabel("Copy codex login command")
        }
    }
}
