import SwiftUI

/// Ten dots under the burn rate: the fill is the current rate, two faint strokes mark the
/// user's median and 90th percentile (docs/design/rules.md, "Burn rate gauge"). Only the high
/// tier takes the warning colour.
struct BurnRateGauge: View {
    let layout: BurnRateGaugeLayout
    let tier: BurnRate.Tier

    private let pitch: CGFloat = 6
    private let dotSize: CGFloat = 3.8

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let fill = tier == .high ? Theme.warning : Theme.ink
            for position in 0..<BurnRateGaugeLayout.dotCount {
                let centerX = pitch * CGFloat(position) + pitch / 2
                let rect = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(position < layout.filled ? fill : Theme.dotTrack))
            }
            for position in [layout.medianPosition, layout.p90Position] {
                let x = min(max(position * size.width - 1, 0), size.width - 2)
                let stroke = CGRect(x: x, y: 0, width: 2, height: size.height)
                context.fill(Path(roundedRect: stroke, cornerRadius: 1), with: .color(Theme.ink.opacity(0.45)))
            }
        }
        .frame(width: pitch * CGFloat(BurnRateGaugeLayout.dotCount), height: 10)
        .accessibilityHidden(true)
    }
}
