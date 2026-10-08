import SwiftUI

/// The uppercase micro label above a value (docs/design/rules.md, "Typography").
private struct MicroLabel: View {
    let text: String
    var size: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: size, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.inkSecondary)
    }
}

private func toneColor(_ tone: UsageTone) -> Color {
    tone == .normal ? Theme.ink : tone.color
}

/// Everything the session block and the ring show, gathered once by the overview.
struct SessionReading {
    let value: Double
    let resetIn: String?
    let resetDate: Date?
    let forecast: SessionForecast
    let elapsed: Double?
    let tone: UsageTone
    var fact: ForecastFact?
    var tokensPerMinute: Int?

    var accessibilityValue: String {
        let facts = [fact?.text, tokensPerMinute.map { "\(BurnRateFact.text($0)) tokens" }].compactMap { $0 }
        return HeadlineLimit.accessibilityValue(value, detail: facts.isEmpty ? nil : facts.joined(separator: ". "))
    }

    func barTooltip(reset: String?) -> String {
        BarTooltip.text(window: "5-hour", showsForecast: forecast.projected != nil, elapsed: elapsed, reset: reset)
    }
}

/// Session on the overview: the one Doto number with forecast and burn rate beside it, and the
/// dot bar with projection and time marker below. Each part explains itself in a tooltip.
struct SessionBlock: View {
    let reading: SessionReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: "SESSION")
                Spacer()
                if let resetIn = reading.resetIn {
                    Text("Reset in \(resetIn)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(Int(reading.value.rounded())))
                        .font(.doto(size: 60))
                    Text("%")
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(toneColor(reading.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    if let fact = reading.fact {
                        SessionFact(label: "FORECAST", value: fact.text, tone: fact.tone, explanation: fact.explanation)
                    }
                    if let tokensPerMinute = reading.tokensPerMinute {
                        SessionFact(
                            label: "BURN RATE", value: BurnRateFact.text(tokensPerMinute), tone: .normal,
                            explanation: BurnRateFact.explanation
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            DotBar(
                value: reading.value, projected: reading.forecast.projected, marker: reading.elapsed.map { $0 * 100 },
                tone: reading.tone, projectionTone: reading.forecast.tone
            )
            .frame(height: 10)
            // A taller hover target than the dots themselves.
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .tooltip(reading.barTooltip(reset: reading.resetDate?.resetDescription), title: "Session", delay: .quick)
            .padding(.vertical, -6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session")
        .accessibilityValue(reading.accessibilityValue)
        .accessibilityHint(reading.resetIn.map { "Reset in \($0)" } ?? "")
    }
}

/// A micro label over a short value, with the sentence that explains it in a tooltip. Grey
/// while normal, otherwise in its tone.
private struct SessionFact: View {
    var alignment: HorizontalAlignment = .trailing
    let label: String
    let value: String
    let tone: UsageTone
    let explanation: String

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            MicroLabel(text: label, size: 9)
            Text(value)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(tone == .normal ? Theme.ink : tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .contentShape(Rectangle())
        .tooltip(explanation, title: label.capitalized, delay: .quick)
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
            BarTooltip.text(window: window, showsForecast: false, elapsed: elapsed, reset: resetDescription),
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
/// forecast beside it, and the week as the same block the bars style uses. The burn rate sits in
/// the ring's tooltip, there is no room for a third fact.
struct RingsBlock: View {
    let reading: SessionReading
    let week: WeekBlock?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    MicroLabel(text: "SESSION")
                    if let resetIn = reading.resetIn {
                        Text("Reset in \(resetIn)")
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if let fact = reading.fact {
                    SessionFact(alignment: .leading, label: "FORECAST", value: fact.text, tone: fact.tone, explanation: fact.explanation)
                }
                week
            }
        }
    }

    private var ring: some View {
        ZStack {
            DotRing(
                value: reading.value, projected: reading.forecast.projected, marker: reading.elapsed.map { $0 * 100 },
                tone: reading.tone, projectionTone: reading.forecast.tone
            )
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(String(Int(reading.value.rounded())))
                    .font(.doto(size: 38))
                Text("%")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(toneColor(reading.tone))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(24)
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session")
        .accessibilityValue(reading.accessibilityValue)
        .tooltip(ringTooltip, title: "Session", delay: .quick)
    }

    private var ringTooltip: String {
        let tooltip = reading.barTooltip(reset: reading.resetIn.map { "in \($0)" })
        guard let tokensPerMinute = reading.tokensPerMinute else { return tooltip }
        return tooltip + "\nBurn rate: \(BurnRateFact.text(tokensPerMinute))"
    }
}

private let previewReading = SessionReading(
    value: 16, resetIn: "4h 15m", resetDate: nil, forecast: SessionForecast(.limitReached(11_460)), elapsed: 0.15,
    tone: .normal,
    fact: ForecastFact(text: "Limit 1h 4m early", tone: .critical, explanation: "At ~26%/h the limit is reached in ~3h 11m."),
    tokensPerMinute: 25_500
)

#Preview("Session and week") {
    VStack(spacing: 16) {
        SessionBlock(reading: previewReading)
        WeekBlock(value: 70, resetIn: "3d 18h", resetDate: nil, elapsed: 0.5, tone: .warning)
    }
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}

#Preview("Ring") {
    RingsBlock(
        reading: previewReading,
        week: WeekBlock(value: 65, resetIn: "3d 12h", resetDate: nil, elapsed: 0.5, tone: .normal)
    )
    .padding(14)
    .frame(width: 320)
    .background(Theme.paper)
}
