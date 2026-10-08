import SwiftUI

/// The usage report window (board 11): a week's or a calendar month's local token usage against
/// the period before it, navigable back one period at a time. Totals, trend and cache hit rate
/// come from the persisted `DailyRollup` data; the model split and top projects from a live scan
/// aligned to the same window; the pace from the polled usage history.
struct WeeklyReportView: View {
    static let windowID = "weeklyReport"

    @EnvironmentObject var state: AppState
    @EnvironmentObject private var codex: CodexState

    @State private var selectedScope = ReportScope.all
    @State private var cachedCodexData: CodexReportData?
    @State private var codexLoadedKey: String?

    var body: some View {
        // The header stays outside the scroll view: the period controls are what someone reaches
        // for after scrolling down.
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if ReportScoping.showsFilter(codexShown: codexShown) {
                PaperSegments(selection: $selectedScope, options: ReportScope.allCases, fillsWidth: true, label: "Provider")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Dims stale numbers while a reopen or period change re-scans.
            .opacity(state.isLoadingWeeklyReport || isLoadingCodexData ? 0.5 : 1)
        }
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 660)
        .background(Theme.paper)
        .task {
            // Always starts at the current week, so reopening never strands the user on a past
            // period they left the window on.
            state.loadWeeklyReport(period: .week, offset: 0)
        }
        .task(id: codexLoadKey) { await loadCodexData() }
    }

    /// Only the scan that belongs to the shown period; empty while a new one is running.
    private var codexData: CodexReportData? {
        ReportScoping.codexData(cachedCodexData, loadedFor: codexLoadedKey, wanted: codexLoadKey)
    }

    /// Codex counts once it is active, or when signed out but its local files still hold use.
    private var codexShown: Bool { codex.isActive || codexData?.hasUse == true }

    private var isLoadingCodexData: Bool { codex.isEnabled && codexLoadedKey != codexLoadKey }

    private var scope: ReportScope { ReportScoping.effective(selectedScope, codexShown: codexShown) }

    private var codexLoadKey: String {
        guard let report = state.weeklyReport else { return "none" }
        return "\(report.previousStart.timeIntervalSince1970)-\(report.rangeStart.timeIntervalSince1970)-\(codex.isEnabled)"
    }

    /// A switched-off Codex is not read at all.
    private func loadCodexData() async {
        let key = codexLoadKey
        guard let report = state.weeklyReport, codex.isEnabled else {
            cachedCodexData = nil
            codexLoadedKey = key
            return
        }
        let range = CodexReportRange(report: report)
        let data = await codex.reportData(previousStart: range.previousStart, start: range.start, until: range.until)
        guard !Task.isCancelled else { return }
        cachedCodexData = data
        codexLoadedKey = key
    }

    @ViewBuilder
    private var content: some View {
        if let report = state.weeklyReport, report.hasData || codexData?.hasUse == true {
            ReportBody(report: report, scope: scope, codex: codexData, showApiCost: state.showApiCost)
        } else if state.weeklyReport == nil {
            // Covers the gap before `.task` fires and the load itself.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            DetailNote(text: "No usage data yet.")
                .padding(.top, 40)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Usage report")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            PaperSegments(selection: periodBinding, options: ReportPeriod.allCases, label: "Period")
                .disabled(state.isLoadingWeeklyReport)
            periodNavigator
        }
    }

    private var periodBinding: Binding<ReportPeriod> {
        Binding(get: { state.reportPeriod }, set: { state.loadWeeklyReport(period: $0, offset: 0) })
    }

    private var periodNavigator: some View {
        let noun = state.reportPeriod == .month ? "month" : "week"
        return HStack(spacing: 2) {
            navigationButton(.chevronLeft, label: "Previous \(noun)", enabled: state.canGoToEarlierPeriod, action: state.goToEarlierPeriod)
            Text(periodTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .frame(minWidth: 110)
            navigationButton(.chevronRight, label: "Next \(noun)", enabled: state.canGoToLaterPeriod, action: state.goToLaterPeriod)
        }
    }

    private func navigationButton(_ icon: TablerIcon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TablerIconView(icon, size: 13, color: Theme.inkSecondary, isDecorative: false)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isLoadingWeeklyReport || !enabled)
        .opacity(enabled ? 1 : 0.35)
        .tooltip(label)
        .accessibilityLabel(label)
    }

    private var periodTitle: String {
        guard let report = state.weeklyReport else { return "" }
        return ReportText.periodTitle(report.period, start: report.rangeStart, end: report.rangeEnd)
    }
}
