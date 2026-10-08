import Foundation

/// The forecast beside the session number: a short value, its tone, and the sentence its
/// tooltip explains it with.
struct ForecastFact: Equatable {
    let text: String
    let tone: UsageTone
    let explanation: String

    static func make(
        projection: ProjectionResult,
        utilization: Double,
        secondsToReset: TimeInterval?,
        elapsedInWindow: TimeInterval?,
        locale: Locale = .current
    ) -> ForecastFact? {
        switch projection {
        case .safe(let projected):
            let landing = "~\(UsageFormat.percent(projected.rounded(), locale: locale))"
            let rate = secondsToReset.flatMap { $0 > 0 ? (projected - utilization) / ($0 / 3600) : nil }
            return ForecastFact(
                text: "\(landing) at reset",
                tone: SessionForecast(projection).tone,
                explanation: "\(ratePrefix(rate, locale: locale)) the session ends at \(landing) when it resets."
            )
        case .limitReached(let seconds):
            let rate = seconds > 0 ? (100 - utilization) / (seconds / 3600) : nil
            let reach = "\(ratePrefix(rate, locale: locale)) the limit is reached in ~\(seconds.shortDuration)"
            if let secondsToReset, secondsToReset - seconds >= 60 {
                let early = (secondsToReset - seconds).shortDuration
                return ForecastFact(text: "Limit \(early) early", tone: .critical, explanation: "\(reach), \(early) before the reset.")
            }
            return ForecastFact(text: "Limit in ~\(seconds.shortDuration)", tone: .critical, explanation: "\(reach), around the reset.")
        case .insufficientData:
            guard let elapsedInWindow, elapsedInWindow < SessionProjection.minimumSpan else { return nil }
            let minutes = Int(SessionProjection.minimumSpan / 60)
            return ForecastFact(
                text: "After \(minutes) min", tone: .normal,
                explanation: "The forecast needs \(minutes) minutes of this session's data."
            )
        }
    }

    private static func ratePrefix(_ rate: Double?, locale: Locale) -> String {
        guard let rate, rate > 0.5 else { return "At the current rate" }
        return "At ~\(UsageFormat.percent(rate.rounded(), locale: locale))/h"
    }
}

/// The burn rate beside the session number.
enum BurnRateFact {
    static let explanation = "Fresh tokens per minute across all sessions, averaged over the last "
        + "\(Int(BurnRate.window / 60)) minutes. Cache reads are not counted."

    static func text(_ tokensPerMinute: Int) -> String {
        "\(formatTokenCount(tokensPerMinute))/min"
    }
}

/// The explaining tooltip of a dot bar: what the fill means, then the hollow dots, the marker
/// and the reset, each only when the bar shows it.
enum BarTooltip {
    static func text(window: String, showsForecast: Bool, elapsed: Double?, reset: String?) -> String {
        var lines = ["Share of the \(window) limit used"]
        if showsForecast { lines.append("Hollow dots: where the session heads at the current rate") }
        if let elapsed {
            lines.append("Marker: \(Int((elapsed * 100).rounded()))% of the window has passed. Fill ahead of it means faster than an even pace")
        }
        if let reset { lines.append("Resets \(reset)") }
        return lines.joined(separator: "\n")
    }
}
