import Foundation

/// What the burn rate gauges draw. The popover shows only the tier as a short dot column, the
/// tooltip the rate on a scale with the user's median and 90th percentile marked. Pure, so it is
/// unit tested; `BurnRateGauge` and `BurnRateScale` only draw it (docs/design/rules.md, "Burn
/// rate gauge").
struct BurnRateGaugeLayout: Equatable {
    static let dotCount = 20
    static let tierStepCount = 3
    /// The scale ends a third past the 90th percentile, so a high rate still has room to grow.
    private static let scaleOverP90 = 4.0 / 3.0

    let tier: BurnRate.Tier
    /// Dots lit on the tooltip scale, at least one.
    let filled: Int
    let median: Int
    let p90: Int
    /// Stroke positions as a share of the scale width, `0...1`.
    let medianPosition: Double
    let p90Position: Double

    init(tokensPerMinute: Int, baseline: BurnRateBaseline) {
        let scale = max(Double(baseline.p90) * Self.scaleOverP90, 1)
        let count = Double(Self.dotCount)
        tier = BurnRate(tokensPerMinute: tokensPerMinute).tier(in: baseline)
        filled = min(max(Int((Double(tokensPerMinute) / scale * count).rounded()), 1), Self.dotCount)
        median = baseline.median
        p90 = baseline.p90
        medianPosition = min(Double(baseline.median) / scale, 1)
        p90Position = min(Double(baseline.p90) / scale, 1)
    }

    /// Past this share of the scale a median label no longer fits beside the P90 label, which
    /// always sits near three quarters of the scale, so the two go on separate rows.
    private static let stackedLabelsFrom = 0.6

    var stacksLabels: Bool { medianPosition > Self.stackedLabelsFrom }

    var tierSteps: Int {
        switch tier {
        case .normal: 1
        case .moderate: 2
        case .high: 3
        }
    }
}
