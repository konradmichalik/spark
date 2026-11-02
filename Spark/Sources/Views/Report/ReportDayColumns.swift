import SwiftUI

/// The report's days as dot columns, one per day, scaled to the busiest day of the range, with
/// the day labels under them (docs/design/rules.md, "Dot language", Day columns). In All,
/// Claude's dots are ink and Codex's ink at 45 % on top; an idle day is one `dotTrack` dot and a
/// day still to come is not drawn.
struct ReportDayColumns: View {
    let series: ReportDaySeries
    let scope: ReportScope
    let period: ReportPeriod
    /// `ReportColumnLayout.overviewHeight` on level 1, `detailHeight` on level 2.
    var height: CGFloat = ReportColumnLayout.overviewHeight
    /// Level 2: each day explains itself in a tooltip.
    var interactive = false

    private var calendar: Calendar { .current }

    var body: some View {
        let days = series.days
        let stacks = Self.stacks(days, height: height)
        VStack(spacing: 6) {
            ReportColumnGrowth(rows: stacks.map(\.total)) { frame in
                Canvas { context, size in
                    draw(days, stacks: stacks, frame: frame, in: &context, size: size)
                }
            }
            .frame(height: height)
            .overlay { if interactive { hoverTargets(days) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tokens per day")
            .accessibilityValue(ReportDayText.summary(series, calendar: calendar))
            ReportDayAxisLabels(
                labels: ReportDayAxis.labels(dates: days.map(\.date), period: period, calendar: calendar, locale: .current),
                count: days.count
            )
        }
    }

    private static func stacks(_ days: [ReportDay], height: CGFloat) -> [ReportColumnStack] {
        let peak = days.map(\.total).max() ?? 0
        let maxRows = ReportColumnLayout.maxRows(height: height)
        return days.map { ReportColumnLayout.stack(claude: $0.claude, codex: $0.codex, peak: peak, maxRows: maxRows) }
    }

    private func draw(
        _ days: [ReportDay], stacks: [ReportColumnStack], frame: ReportColumnFrame, in context: inout GraphicsContext, size: CGSize
    ) {
        let bottom = size.height - ReportColumnLayout.dotSize / 2
        let codexColour = scope == .all ? Theme.ink.opacity(0.45) : Theme.ink
        for (index, day) in days.enumerated() where !day.isFuture {
            let x = ReportColumnLayout.centerX(index: index, count: days.count, width: size.width)
            let stack = stacks[index]
            guard stack.total > 0 else {
                context.fill(dot(x: x, row: 0, bottom: bottom), with: .color(Theme.dotTrack))
                continue
            }
            for row in 0..<frame.shown(index) {
                context.fill(dot(x: x, row: row, bottom: bottom), with: .color(row < stack.claude ? Theme.ink : codexColour))
            }
        }
    }

    private func dot(x: CGFloat, row: Int, bottom: CGFloat) -> Path {
        DotColumnDot.path(x: x, row: row, bottom: bottom, pitch: ReportColumnLayout.rowPitch, size: ReportColumnLayout.dotSize)
    }

    /// One hover target per day, so every day shows the shared tooltip.
    private func hoverTargets(_ days: [ReportDay]) -> some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .tooltip(
                        day.isFuture ? nil : ReportDayText.body(day, scope: scope),
                        title: ReportDayText.title(day, calendar: calendar), delay: .quick
                    )
            }
        }
    }
}

/// Which dots stand for which provider, under the columns in All.
struct ReportProviderLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            item(Theme.ink, "Claude")
            item(Theme.ink.opacity(0.45), "Codex")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityHidden(true)
    }

    private func item(_ colour: Color, _ name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 6, height: 6)
            Text(name)
        }
    }
}
