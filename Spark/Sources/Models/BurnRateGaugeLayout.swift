import Foundation

/// Where the gauge under the burn rate fills and where its two strokes sit. Pure, so it is unit
/// tested; `BurnRateGauge` only draws it (docs/design/rules.md, "Burn rate gauge").
struct BurnRateGaugeLayout: Equatable {
    static let dotCount = 10
    /// The scale ends a third past the 90th percentile, so a high rate still has room to grow.
    private static let scaleOverP90 = 4.0 / 3.0

    let filled: Int
    /// Stroke positions as a share of the gauge width, `0...1`.
    let medianPosition: Double
    let p90Position: Double

    init(tokensPerMinute: Int, baseline: BurnRateBaseline) {
        let scale = max(Double(baseline.p90) * Self.scaleOverP90, 1)
        let count = Double(Self.dotCount)
        filled = min(max(Int((Double(tokensPerMinute) / scale * count).rounded()), 1), Self.dotCount)
        medianPosition = min(Double(baseline.median) / scale, 1)
        p90Position = min(Double(baseline.p90) / scale, 1)
    }
}
