import SwiftUI

private let fiveHours: TimeInterval = 5 * 3600
private let sevenDays: TimeInterval = 7 * 24 * 3600

/// Session and week for one provider in the user's display style (bars or ring).
private struct UsageSection: View {
    let session: UsageBucket?
    let week: UsageBucket?
    let forecast: SessionForecast
    var fact: ForecastFact?
    var tokensPerMinute: Int?
    let warning: Double
    let critical: Double
    let style: String

    var body: some View {
        if let session {
            let elapsed = Pace.calculate(utilization: session.utilization, resetsAt: session.resetsAtDate, windowLength: fiveHours)?
                .elapsedFraction
            let reading = SessionReading(
                value: session.utilization, resetIn: session.timeUntilReset, resetDate: session.resetsAtDate,
                forecast: forecast, elapsed: elapsed, tone: UsageTone(value: session.utilization, warning: warning, critical: critical),
                fact: fact, tokensPerMinute: tokensPerMinute
            )
            if style == "bars" {
                VStack(alignment: .leading, spacing: 16) {
                    SessionBlock(reading: reading)
                    weekBlock
                }
            } else {
                RingsBlock(reading: reading, week: weekBlock)
            }
        } else {
            weekBlock
        }
    }

    private var weekBlock: WeekBlock? {
        week.map { week in
            WeekBlock(
                value: week.utilization, resetIn: week.timeUntilReset, resetDate: week.resetsAtDate,
                elapsed: Pace.calculate(utilization: week.utilization, resetsAt: week.resetsAtDate, windowLength: sevenDays)?
                    .elapsedFraction,
                tone: UsageTone(value: week.utilization, warning: warning, critical: critical)
            )
        }
    }
}

private func noDataText(_ text: String = "No data available") -> some View {
    Text(text)
        .font(.system(size: 12))
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// The Claude overview: status and connection notices, session and week, the history card, and
/// the rows to the detail screens.
struct ClaudeOverview: View {
    @EnvironmentObject var state: AppState
    let open: (PopoverScreen) -> Void

    var body: some View {
        if state.status.isIncident {
            StatusRow(state: state)
        }
        if state.needsReconnect {
            ReconnectPrompt(onReconnect: state.reconnect)
        }
        if let error = state.lastError {
            WarningBanner(message: error)
        }
        if state.usageData.session == nil {
            if state.lastError == nil, !state.isLoading { noDataText() }
        } else {
            UsageSection(
                session: state.usageData.session, week: state.usageData.weekly, forecast: SessionForecast(projection),
                fact: forecastFact, tokensPerMinute: state.showProjection ? state.burnRate?.tokensPerMinute : nil,
                warning: state.warningThreshold, critical: state.criticalThreshold, style: state.usageDisplayStyle
            )
        }
        if state.showGraph, !state.history.isEmpty {
            HistoryCard(columns: HistoryColumns.make(state.history, now: Date())) { open(.history) }
        }
        OverviewRows(rows: rows, onOpen: open)
    }

    private var projection: ProjectionResult {
        guard state.showProjection, let session = state.usageData.session else { return .insufficientData }
        return SessionProjection.calculate(history: state.history, currentUtilization: session.utilization, resetsAt: session.resetsAtDate)
    }

    private var forecastFact: ForecastFact? {
        guard state.showProjection, let session = state.usageData.session else { return nil }
        let secondsToReset = session.resetsAtDate.map { $0.timeIntervalSinceNow }
        return ForecastFact.make(
            projection: projection, utilization: session.utilization,
            secondsToReset: secondsToReset, elapsedInWindow: secondsToReset.map { fiveHours - $0 }
        )
    }

    private var rows: [OverviewRow] {
        var rows: [OverviewRow] = []
        if state.showActiveSessions {
            rows.append(OverviewRow(
                screen: .sessions, icon: .terminal2, label: "Active sessions", value: "\(state.activeSessions.count)"
            ))
        }
        if state.showStats {
            let label = state.statsPeriod == .today ? "Statistics today" : "Statistics"
            let value = OverviewSummary.statisticsValue(
                tokens: state.liveStats?.realTokens, cost: state.showApiCost ? state.liveCost?.total : nil,
                messages: state.liveStats?.messageCount
            )
            rows.append(OverviewRow(screen: .statistics, icon: .chartBar, label: label, value: value))
        }
        rows.append(OverviewRow(
            screen: .limits, icon: .layoutGrid, label: "All limits",
            value: OverviewSummary.limitsValue(extraLimits: extraLimitCount, plan: state.accountTier.displayName)
        ))
        return rows
    }

    private var extraLimitCount: Int {
        let data = state.usageData
        let models = [
            state.showSonnetUsage && data.weeklySonnet != nil,
            state.showOpusUsage && data.weeklyOpus != nil,
            state.showFableUsage && data.weeklyFable != nil,
            data.extraUsage?.hasSpend == true
        ]
        return models.filter { $0 }.count
    }
}

/// The Codex overview: sign-in and error notices, session and week, and the rows. Codex has no
/// usage history, so there is no history card.
struct CodexOverview: View {
    @ObservedObject var codex: CodexState
    let warning: Double
    let critical: Double
    let style: String
    let showStats: Bool
    let open: (PopoverScreen) -> Void

    var body: some View {
        if codex.needsSignIn {
            CodexSignInPrompt()
        }
        if let error = codex.lastError {
            WarningBanner(message: error)
        }
        if let usage = codex.usage, usage.usageData.session != nil {
            UsageSection(
                session: usage.usageData.session, week: usage.usageData.weekly, forecast: SessionForecast(.insufficientData),
                warning: warning, critical: critical, style: style
            )
        } else if let usage = codex.usage,
                  let headline = HeadlineLimit.withoutSession(weekly: usage.usageData.weekly, others: usage.additionalLimits) {
            WeekBlock(
                label: headline.label, window: headline.label == "WEEK" ? "weekly" : headline.label.lowercased(),
                value: headline.bucket.utilization, resetIn: headline.bucket.timeUntilReset,
                resetDate: headline.bucket.resetsAtDate,
                elapsed: Pace.calculate(
                    utilization: headline.bucket.utilization, resetsAt: headline.bucket.resetsAtDate, windowLength: headline.window
                )?.elapsedFraction,
                tone: UsageTone(value: headline.bucket.utilization, warning: warning, critical: critical)
            )
        } else if let usage = codex.usage {
            noDataText(HeadlineLimit.emptyText(limitReached: usage.limitReached))
        } else if !codex.isLoading, !codex.needsSignIn, codex.lastError == nil {
            noDataText()
        }
        OverviewRows(rows: rows, onOpen: open)
    }

    private var rows: [OverviewRow] {
        var rows: [OverviewRow] = []
        if showStats, let stats = codex.stats, stats.fileCount > 0 {
            rows.append(OverviewRow(
                screen: .statistics, icon: .chartBar, label: "Statistics",
                value: OverviewSummary.statisticsValue(tokens: stats.totalTokens, cost: nil, messages: stats.messageCount)
            ))
        }
        let extra = (codex.usage?.additionalLimits.count ?? 0) + (codex.usage?.creditsBalance == nil ? 0 : 1)
        rows.append(OverviewRow(
            screen: .limits, icon: .layoutGrid, label: "All limits",
            value: OverviewSummary.limitsValue(extraLimits: extra, plan: codex.usage?.planDisplayName)
        ))
        return rows
    }
}

/// The Claude session expired notice with its reconnect action, unchanged from the former popover.
struct ReconnectPrompt: View {
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TablerIconView(.refreshAlert, size: 12, color: .orange)
            Text("Session expired")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Reconnect", action: onReconnect)
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundColor(Theme.sparkOrange)
        }
    }
}
