import SwiftUI

/// The content of the level 1 Models or Projects card: the top three rows with name, tokens and
/// the dot bar, no logos and no shares. The card and its chevron belong to the window.
struct ReportTopList: View {
    /// `.models` or `.projects`, the Breakdown tab the card opens.
    let tab: ReportBreakdownTab
    let scope: ReportScope
    let report: PeriodReport
    let codex: CodexReportData?

    var body: some View {
        let rows = ReportBreakdown.rows(tab, scope: scope, report: report, codex: codex).prefix(ReportBreakdown.topCount)
        VStack(alignment: .leading, spacing: 2) {
            if rows.isEmpty {
                DetailNote(text: ReportBreakdown.emptyText(tab, isCurrentPeriod: report.periodOffset == 0))
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ReportBreakdownRowView(row: row, index: index, isCompact: true)
            }
        }
    }
}
