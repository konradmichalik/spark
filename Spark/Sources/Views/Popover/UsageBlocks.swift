import SwiftUI

/// The uppercase micro label above a value (docs/design/rules.md, "Typography").
private struct MicroLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.inkSecondary)
    }
}

private func toneColor(_ tone: UsageTone) -> Color {
    tone == .normal ? Theme.ink : tone.color
}

/// Session on the overview: the one Doto number, the dot bar with projection and time marker,
/// and the forecast line below it; the rest of the forecast sits in the tooltip.
struct SessionBlock: View {
    let value: Double
    let resetIn: String?
    let resetDate: Date?
    let forecast: SessionForecast
    let elapsed: Double?
    let tone: UsageTone
    var forecastLine: ForecastLine?
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "SESSION")
                Spacer()
                if let resetIn {
                    Text("Reset in \(resetIn)")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(Int(value.rounded())))
                    .font(.doto(size: 60))
                Text("%")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(toneColor(tone))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            DotBar(value: value, projected: forecast.projected, marker: elapsed.map { $0 * 100 }, tone: tone)
                .frame(height: 10)
            if let forecastLine {
                ForecastLineText(line: forecastLine)
            }
        }
        .contentShape(Rectangle())
        .tooltip(
            BarTooltip.text(window: "5-hour", forecast: detail, elapsed: elapsed, reset: resetDate?.resetDescription),
            title: "Session", delay: .quick
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session")
        .accessibilityValue(HeadlineLimit.accessibilityValue(value, detail: detail))
        .accessibilityHint(resetIn.map { "Reset in \($0)" } ?? "")
    }
}

/// Grey when the session lands below the limit, red with semibold weight when it does not.
private struct ForecastLineText: View {
    let line: ForecastLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 11.5, weight: line.isWarning ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(line.isWarning ? Theme.accent : Theme.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Week on the overview: label and value on one line, a thin dot bar with the time marker below.
struct WeekBlock: View {
    var label = "WEEK"
    var window = "weekly"
    let value: Double
    let resetIn: String?
    let resetDate: Date?
    var elapsed: Double?
    let tone: UsageTone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: label)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(Int(value.rounded())))
                        .font(.doto(size: 24))
                    Text("%")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(toneColor(tone))
            }
            DotBar(value: value, marker: elapsed.map { $0 * 100 }, tone: tone, pitch: 4, dotSize: 2.6)
                .frame(height: 8)
        }
        .contentShape(Rectangle())
        .tooltip(
            BarTooltip.text(window: window, forecast: nil, elapsed: elapsed, reset: resetDescription),
            title: label.capitalized, delay: .quick
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(UsageFormat.percent(value))
        .accessibilityHint(resetDescription ?? "")
    }

    private var resetDescription: String? {
        resetDate?.resetDescription ?? resetIn.map { "in \($0)" }
    }
}

/// The "Ring" display style: the session as one dot ring with the number inside, the reset and
/// forecast line beside it, and the week as the same block the bars style uses.
struct RingsBlock: View {
    let value: Double
    let resetIn: String?
    let forecast: SessionForecast
    let elapsed: Double?
    let tone: UsageTone
    var forecastLine: ForecastLine?
    let detail: String?
    let week: WeekBlock?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel(text: "SESSION")
                    if let forecastLine {
                        ForecastLineText(line: forecastLine)
                    }
                    if let resetIn {
                        Text("Reset in \(resetIn)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                week
            }
        }
    }

    private var ring: some View {
        ZStack {
            DotRing(value: value, projected: forecast.projected, marker: elapsed.map { $0 * 100 }, tone: tone)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(Int(value.rounded())))
                    .font(.doto(size: 38))
                Text("%")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(toneColor(tone))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(24)
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session")
        .accessibilityValue(HeadlineLimit.accessibilityValue(value, detail: detail))
        .tooltip(
            BarTooltip.text(window: "5-hour", forecast: detail, elapsed: elapsed, reset: resetIn.map { "in \($0)" }),
            title: "Session", delay: .quick
        )
    }
}

#Preview("Session and week") {
    VStack(spacing: 16) {
        SessionBlock(
            value: 45, resetIn: "1h 49m", resetDate: nil, forecast: SessionForecast(.safe(79)),
            elapsed: 0.54, tone: .normal, detail: "~79% at reset"
        )
        WeekBlock(value: 48, resetIn: "3d 18h", resetDate: nil, elapsed: 0.5, tone: .normal)
        SessionBlock(
            value: 92, resetIn: "1h 5m", resetDate: nil, forecast: SessionForecast(.limitReached(1200)),
            elapsed: 0.78, tone: .critical, forecastLine: ForecastLine(text: "Limit in ~20m \u{00B7} 45m before reset", isWarning: true),
            detail: "Limit in ~20m"
        )
    }
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}

#Preview("Ring") {
    RingsBlock(
        value: 92, resetIn: "1h 5m", forecast: SessionForecast(.limitReached(1200)), elapsed: 0.78,
        tone: .critical, forecastLine: ForecastLine(text: "Limit in ~20m", isWarning: true), detail: nil,
        week: WeekBlock(value: 65, resetIn: "3d 12h", resetDate: nil, elapsed: 0.5, tone: .normal)
    )
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}
