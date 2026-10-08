import SwiftUI

/// Which days each provider was used, as one dotted calendar per provider: weeks in rows, weekdays
/// in columns, the dot's weight the day's fresh tokens against the busiest day of the period.
struct ActivitySection: View {
    let report: PeriodReport

    @EnvironmentObject private var codex: CodexState
    @State private var codexDays: [String: Int] = [:]

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "ACTIVITY \u{00B7} DAYS WITH USE")
                .accessibilityAddTraits(.isHeader)
            ActivityCalendarView(provider: .claude, rows: rows(report.dayTokens), calendar: calendar)
            if codex.isActive || hasCodexUse {
                ActivityCalendarView(provider: .codex, rows: rows(codexDays), calendar: calendar)
            }
            ActivityLegend()
        }
        .task(id: "\(report.calendarStart.timeIntervalSince1970)-\(codex.isEnabled)") {
            await loadCodexDays()
        }
    }

    private var hasCodexUse: Bool {
        codexDays.values.contains { $0 > 0 }
    }

    private func rows(_ dayTokens: [String: Int]) -> [[ActivityCell]] {
        ActivityCalendar.rows(
            start: report.calendarStart, end: report.calendarEnd, today: Date(), dayTokens: dayTokens, calendar: calendar
        )
    }

    /// Codex switched off in Settings is not read at all, a signed-out one still shows what its
    /// rollout files hold.
    private func loadCodexDays() async {
        guard codex.isEnabled else {
            codexDays = [:]
            return
        }
        let days = await codex.dayTokens(since: report.calendarStart)
        guard !Task.isCancelled else { return }
        codexDays = days
    }
}

private struct ActivityCalendarView: View {
    let provider: UsageProvider
    let rows: [[ActivityCell]]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PopoverHeader.logo(for: provider)
                Text(provider.segmentLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
            }
            grid
        }
    }

    private var grid: some View {
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
        .accessibilityLabel("\(provider.segmentLabel) activity")
        .accessibilityValue(ActivityCalendar.summary(rows.flatMap { $0 }, calendar: calendar))
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
