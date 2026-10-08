import SwiftUI

/// The days the shown scope was used, as one dotted calendar: weeks in rows, weekdays in columns,
/// the dot's weight the day's fresh tokens against the busiest day of the period.
struct ActivitySection: View {
    let report: PeriodReport
    let dayTokens: [String: Int]

    private var calendar: Calendar { .current }

    var body: some View {
        let rows = ActivityCalendar.rows(
            start: report.calendarStart, end: report.calendarEnd, today: Date(), dayTokens: dayTokens, calendar: calendar
        )
        let figures = ActivityFigures(cells: rows.flatMap { $0 })
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "ACTIVITY \u{00B7} DAYS WITH USE")
                .accessibilityAddTraits(.isHeader)
            // Side by side while the window is wide enough, the figures under the calendar otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    calendarBlock(rows, figures)
                    ActivityFiguresView(figures: figures, calendar: calendar)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    calendarBlock(rows, figures)
                    ActivityFiguresView(figures: figures, calendar: calendar)
                }
            }
        }
    }

    private func calendarBlock(_ rows: [[ActivityCell]], _ figures: ActivityFigures) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            grid(rows, figures)
            ActivityLegend()
        }
    }

    private func grid(_ rows: [[ActivityCell]], _ figures: ActivityFigures) -> some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(ActivityCalendar.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(width: ActivityDayCell.width, height: 16)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        ActivityDayCell(cell: cell, calendar: calendar)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity")
        .accessibilityValue(ActivityCalendar.summary(figures, calendar: calendar))
    }
}

/// One day: a dot in the weight of its level, a ring around it for today, nothing for days that
/// have not happened. The whole cell is the tooltip's hit target.
private struct ActivityDayCell: View {
    static let width: CGFloat = 28

    let cell: ActivityCell
    let calendar: Calendar

    var body: some View {
        ZStack {
            if cell.isDrawn {
                ActivityDot(level: cell.level)
                if cell.isToday {
                    Circle().strokeBorder(Theme.ink, lineWidth: 1).frame(width: 14, height: 14)
                }
            }
        }
        .frame(width: Self.width, height: 24)
        .contentShape(Rectangle())
        .tooltip(
            cell.isDrawn ? ActivityCalendar.tooltipBody(cell) : nil,
            title: ActivityCalendar.tooltipTitle(cell, calendar: calendar), delay: .quick
        )
    }
}

private struct ActivityDot: View {
    let level: Int

    private static let opacity: [Double] = [1, 0.35, 0.6, 1]

    var body: some View {
        Circle()
            .fill(level == 0 ? Theme.dotTrack : Theme.ink.opacity(Self.opacity[min(max(level, 0), 3)]))
            .frame(width: level == 0 ? 4 : 8, height: level == 0 ? 4 : 8)
    }
}

private struct ActivityLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
            ForEach(0..<ActivityCalendar.levelCount, id: \.self) { level in
                ActivityDot(level: level).frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkSecondary)
        .accessibilityHidden(true)
    }
}

/// Active days, the longest streak and the busiest day, each one element for VoiceOver.
private struct ActivityFiguresView: View {
    let figures: ActivityFigures
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportFigure(
                label: "ACTIVE DAYS", tooltip: "Days with fresh tokens in this period.",
                spoken: "\(figures.activeDays) of \(figures.totalDays) days"
            ) {
                numberLine(figures.activeDays, text: "of \(figures.totalDays) days")
            }
            ReportFigure(
                label: "LONGEST STREAK", tooltip: "The longest run of days in a row with use.",
                spoken: "\(figures.longestStreak) \(ActivityFigures.streakUnit(figures.longestStreak))"
            ) {
                numberLine(figures.longestStreak, text: ActivityFigures.streakUnit(figures.longestStreak))
            }
            ReportFigure(label: "BUSIEST DAY", tooltip: "The day with the most fresh tokens.", spoken: busiestSpoken) { busiest }
        }
    }

    private var busiestSpoken: String {
        guard let day = figures.busiest else { return "No use" }
        return "\(ActivityCalendar.tooltipTitle(day, calendar: calendar)), \(ActivityCalendar.tooltipBody(day))"
    }

    @ViewBuilder
    private var busiest: some View {
        if let day = figures.busiest {
            VStack(alignment: .leading, spacing: 2) {
                Text(ActivityCalendar.tooltipTitle(day, calendar: calendar))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(ActivityCalendar.tooltipBody(day))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkSecondary)
            }
        } else {
            Text("No use")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    private func numberLine(_ value: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            DotoValue(parts: NumberParts(number: String(value), unit: ""), size: 32)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
