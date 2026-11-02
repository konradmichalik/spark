import SwiftUI

/// Level 2 of the report's Limits: per provider, Claude first, each day's session peak as grey
/// dot columns under the solid `accent` weekly line, all on one day axis with one legend
/// (docs/design/rules.md, "Windows", Limits).
struct ReportLimitsScreen: View {
    /// One per provider in the scope, Claude first.
    let limits: [ReportLimits]
    let period: ReportPeriod

    var body: some View {
        ReportCard {
            VStack(alignment: .leading, spacing: 16) {
                legend
                ForEach(limits, id: \.provider) { ReportLimitRow(limits: $0) }
                if let shared = limits.first(where: \.hasHistory) {
                    let dates = shared.days.map(\.day)
                    ReportDayAxisLabels(
                        labels: ReportDayAxis.labels(dates: dates, period: period, calendar: .current, locale: .current),
                        count: dates.count
                    )
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ReportLegendItem(colour: sessionPeakColour, text: "Session, daily peak")
            HStack(spacing: 5) {
                Capsule().fill(Theme.accent).frame(width: 12, height: 2)
                Text("Week")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityHidden(true)
    }
}

/// The grey of the session peak columns, the same for every provider, so it is not a provider's dot colour.
private let sessionPeakColour = Theme.ink.opacity(0.45)

/// One provider: logo, name and the long summary, then its graph or why there is none.
private struct ReportLimitRow: View {
    let limits: ReportLimits

    private var name: String { limits.provider.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PopoverHeader.logo(for: limits.provider.usageProvider)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if limits.hasHistory {
                    Text(limits.longSummary)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if limits.hasHistory {
                graph
            } else {
                DetailNote(text: limits.longSummary)
            }
        }
    }

    private var graph: some View {
        let rows = limits.days.map {
            ReportColumnLayout.percentRows($0.sessionUtilization, maxRows: ReportColumnLayout.maxRows(height: ReportColumnLayout.limitHeight))
        }
        return ReportColumnGrowth(rows: rows) { frame in
            Canvas { context, size in
                let bottom = size.height - ReportColumnLayout.dotSize / 2
                for index in rows.indices {
                    let x = ReportColumnLayout.centerX(index: index, count: rows.count, width: size.width)
                    for row in 0..<frame.shown(index) {
                        let dot = DotColumnDot.path(
                            x: x, row: row, bottom: bottom, pitch: ReportColumnLayout.rowPitch, size: ReportColumnLayout.dotSize
                        )
                        context.fill(dot, with: .color(sessionPeakColour))
                    }
                }
            }
        }
        .overlay { ReportWeekLineView(values: limits.days.map(\.weeklyUtilization)) }
        .frame(height: ReportColumnLayout.limitHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) limits")
        .accessibilityValue(limits.longSummary)
    }
}
