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
/// and the forecast in a tooltip.
struct SessionBlock: View {
    let value: Double
    let resetIn: String?
    let resetDate: Date?
    let forecast: SessionForecast
    let elapsed: Double?
    let tone: UsageTone
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
                        .tooltip(resetDate?.resetDescription)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session \(UsageFormat.percent(value))")
            DotBar(
                value: value, projected: forecast.projected, marker: elapsed.map { $0 * 100 },
                tone: tone, projectionReachesLimit: forecast.reachesLimit
            )
            .frame(height: 10)
            .accessibilityLabel("Session usage")
            .tooltip(detail, title: "Forecast")
        }
    }
}

/// Week on the overview: label and value on one line, a thin dot bar below.
struct WeekBlock: View {
    let value: Double
    let resetIn: String?
    let resetDate: Date?
    let tone: UsageTone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "WEEK")
                Spacer()
                Text(UsageFormat.percent(value))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(toneColor(tone))
            }
            DotBar(value: value, tone: tone, pitch: 4, dotSize: 2.6)
                .frame(height: 6)
                .accessibilityLabel("Week usage")
        }
        .tooltip(resetDate?.resetDescription ?? resetIn.map { "Reset in \($0)" }, title: "Week")
    }
}

/// The "Rings" display style: session on the outer ring, week on the inner one, the session
/// value in the centre and the reset times beside it.
struct RingsBlock: View {
    let session: Double
    let week: Double
    let sessionResetIn: String?
    let weekResetIn: String?
    let forecast: SessionForecast
    let elapsed: Double?
    let sessionTone: UsageTone
    let weekTone: UsageTone
    let detail: String?

    var body: some View {
        HStack(spacing: 18) {
            rings
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel(text: "SESSION")
                    Text(sessionResetIn.map { "Reset in \($0)" } ?? " ")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel(text: "WEEK")
                    Text([UsageFormat.percent(week), weekResetIn.map { "Reset in \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(toneColor(weekTone))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var rings: some View {
        ZStack {
            DotRing(
                value: session, projected: forecast.projected, marker: elapsed.map { $0 * 100 },
                tone: sessionTone, projectionReachesLimit: forecast.reachesLimit, count: 44, dotSize: 6
            )
            DotRing(value: week, tone: weekTone, count: 32, dotSize: 4)
                .padding(30)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(Int(session.rounded())))
                    .font(.doto(size: 40))
                Text("%")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(toneColor(sessionTone))
            .accessibilityHidden(true)
        }
        .frame(width: 136, height: 136)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session \(UsageFormat.percent(session)), week \(UsageFormat.percent(week))")
        .tooltip(detail, title: "Forecast")
    }
}

#Preview("Session and week") {
    VStack(spacing: 16) {
        SessionBlock(
            value: 45, resetIn: "1h 49m", resetDate: nil, forecast: SessionForecast(.safe(79)),
            elapsed: 0.54, tone: .normal, detail: "~79% at reset"
        )
        WeekBlock(value: 48, resetIn: "3d 18h", resetDate: nil, tone: .normal)
        SessionBlock(
            value: 82, resetIn: "40m", resetDate: nil, forecast: SessionForecast(.limitReached(1200)),
            elapsed: 0.7, tone: .warning, detail: "Limit in ~20m"
        )
    }
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}

#Preview("Rings") {
    RingsBlock(
        session: 45, week: 48, sessionResetIn: "1h 49m", weekResetIn: "3d", forecast: SessionForecast(.safe(79)),
        elapsed: 0.54, sessionTone: .normal, weekTone: .normal, detail: nil
    )
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}
