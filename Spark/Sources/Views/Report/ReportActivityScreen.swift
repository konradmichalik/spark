import SwiftUI

/// The two views of the Activity screen's graph.
enum ReportActivityMode: String, CaseIterable, SegmentLabeled {
    case byDay = "By day"
    case byWeekday = "By weekday"

    var segmentLabel: String { rawValue }
}

/// Level 2 of the report's Activity: the day columns with a tooltip per day, or the weekday
/// profile for a month, and three tiles under the card (docs/design/rules.md, "Windows").
struct ReportActivityScreen: View {
    let series: ReportDaySeries
    let scope: ReportScope
    let period: ReportPeriod
    /// `WeekdayProfile.make` for the range; the "By weekday" chip shows only for a month with one.
    let weekdayProfile: WeekdayProfile?

    @State private var mode: ReportActivityMode = .byDay

    private var calendar: Calendar { .current }

    var body: some View {
        let profile = period == .month ? weekdayProfile : nil
        let shownProfile = mode == .byWeekday ? profile : nil
        VStack(alignment: .leading, spacing: 12) {
            ReportCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        MicroLabel(text: shownProfile == nil ? "TOKENS PER DAY" : "AVERAGE BY WEEKDAY")
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        if profile != nil {
                            PaperSegments(selection: $mode, options: ReportActivityMode.allCases, style: .chips, label: "Activity view")
                        }
                    }
                    if let shownProfile {
                        WeekdaySection(profile: shownProfile, title: nil)
                    } else {
                        ReportDayColumns(
                            series: series, scope: scope, period: period, height: ReportColumnLayout.detailHeight, interactive: true
                        )
                        if scope == .all { ReportProviderLegend() }
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                activeDaysTile
                streakTile
                busiestTile
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeDaysTile: some View {
        tile(
            "ACTIVE DAYS", tooltip: "Days with fresh tokens, counted up to today.",
            spoken: "\(series.activeDays) \(ReportDayText.activeDaysUnit(series))"
        ) {
            numberLine(UsageFormat.count(series.activeDays), words: ReportDayText.activeDaysUnit(series))
        }
    }

    private var streakTile: some View {
        let unit = ActivityFigures.streakUnit(series.longestStreak)
        return tile("LONGEST STREAK", tooltip: "The longest run of days in a row with use.", spoken: "\(series.longestStreak) \(unit)") {
            numberLine(UsageFormat.count(series.longestStreak), words: unit)
        }
    }

    private var busiestTile: some View {
        let title = series.busiest.map { ReportDayText.title($0, calendar: calendar) }
        let spoken = series.busiest.map { "\(ReportDayText.title($0, calendar: calendar)), \(formatTokenCount($0.total)) tokens" }
        return tile("BUSIEST DAY", tooltip: "The day with the most fresh tokens, the latest on a tie.", spoken: spoken ?? "No use") {
            if let busiest = series.busiest, let title {
                VStack(alignment: .leading, spacing: 2) {
                    numberLine(UsageFormat.tokens(busiest.total), words: "tokens")
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else {
                Text("No use")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
    }

    private func tile<Content: View>(
        _ label: String, tooltip: String, spoken: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        // The tallest tile sets the row's height; the others stretch their card to it.
        ReportCard {
            ReportFigure(label: label, tooltip: tooltip, spoken: spoken, content: content)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// A Doto number with its unit and the words after it in SF Pro.
    private func numberLine(_ parts: NumberParts, words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            DotoValue(parts: parts, size: 32)
            Text(words)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
        }
    }
}
