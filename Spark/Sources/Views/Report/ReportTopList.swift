import SwiftUI

/// The content of the level 1 Models or Projects card: the top three rows with name, tokens and
/// the dot bar, no logos and no shares. The card and its chevron belong to the window.
struct ReportTopList: View {
    /// The Breakdown tab's rows; the card's label is built from the same rows.
    let rows: [ReportBreakdownRow]
    let emptyText: String

    var body: some View {
        let top = rows.prefix(ReportBreakdown.topCount)
        VStack(alignment: .leading, spacing: 2) {
            if top.isEmpty {
                DetailNote(text: emptyText)
            }
            ForEach(Array(top.enumerated()), id: \.element.id) { index, row in
                ReportBreakdownRowView(row: row, index: index, isCompact: true)
            }
        }
    }
}
