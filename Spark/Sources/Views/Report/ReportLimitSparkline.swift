import SwiftUI

/// The weekly line of one provider on the report's overview: 24 pt high over a hairline
/// baseline, drawn in from the left like the Limits screen. Decorative, the row's summary
/// carries the numbers.
struct ReportLimitSparkline: View {
    /// One per day of the range, as `ReportLimits.days`.
    let days: [PaceDay]

    var body: some View {
        ReportWeekLineView(values: days.map(\.weeklyUtilization))
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .accessibilityHidden(true)
    }
}
