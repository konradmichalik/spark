import SwiftUI

/// The report's Breakdown screen on level 2: Models, Projects and Top sessions of the scope, five
/// rows and then "Show N more" (docs/design/rules.md, "Windows" and "Detail screens").
struct ReportBreakdownScreen: View {
    /// A binding, so the window can open the screen on the tab of the card that was clicked.
    @Binding var tab: ReportBreakdownTab
    let scope: ReportScope
    let report: PeriodReport
    let codex: CodexReportData?

    @State private var isExpanded = false

    private static let visibleLimit = 5
    private static let scrollThreshold = 10
    private static let scrollHeight: CGFloat = 400

    var body: some View {
        let rows = ReportBreakdown.rows(tab, scope: scope, report: report, codex: codex)
        ReportCard {
            VStack(alignment: .leading, spacing: 12) {
                PaperSegments(selection: $tab, options: ReportBreakdownTab.allCases, fillsWidth: true, label: "Breakdown")
                if rows.isEmpty {
                    DetailNote(text: ReportBreakdown.emptyText(tab, isCurrentPeriod: report.periodOffset == 0))
                } else {
                    list(rows)
                }
            }
        }
        .onChange(of: tab) { isExpanded = false }
        .onChange(of: scope) { isExpanded = false }
        // A new period brings new rows under the same tab and scope.
        .onChange(of: rows.map(\.id)) { isExpanded = false }
    }

    private func list(_ rows: [ReportBreakdownRow]) -> some View {
        let more = ShowMore(total: rows.count, limit: Self.visibleLimit)
        let visible = Array(rows.prefix(more.visibleCount(expanded: isExpanded)))
        return VStack(spacing: 0) {
            if visible.count > Self.scrollThreshold {
                ScrollView { rowStack(visible) }
                    .frame(maxHeight: Self.scrollHeight)
            } else {
                rowStack(visible)
            }
            ShowMoreRow(more: more, isExpanded: $isExpanded)
        }
    }

    private func rowStack(_ rows: [ReportBreakdownRow]) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ReportBreakdownRowView(row: row, index: index)
            }
        }
    }
}
