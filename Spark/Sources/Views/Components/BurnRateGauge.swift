import SwiftUI

/// Three dots in a column beside the burn rate: one, two or three lit for the normal, moderate
/// and high tier. Only the high tier takes the warning colour. The scale with the user's median
/// and 90th percentile is in the tooltip (docs/design/rules.md, "Burn rate gauge").
struct BurnRateGauge: View {
    let layout: BurnRateGaugeLayout

    private let pitch: CGFloat = 4
    private let dotSize: CGFloat = 3.2
    private let steps = BurnRateGaugeLayout.tierStepCount

    var body: some View {
        Canvas { context, size in
            let fill = layout.tier == .high ? Theme.warning : Theme.ink
            for position in 0..<steps {
                let centerY = size.height - pitch * CGFloat(position) - pitch / 2
                let rect = CGRect(x: (size.width - dotSize) / 2, y: centerY - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(position < layout.tierSteps ? fill : Theme.dotTrack))
            }
        }
        .frame(width: pitch, height: pitch * CGFloat(steps))
        .accessibilityHidden(true)
    }
}

/// The tooltip scale: twenty dots filled to the current rate, two strokes at the user's median
/// and 90th percentile, each named below. The median label ends at its stroke, the P90 label
/// starts at its own, both kept inside the scale. When the median sits too close to the P90 for
/// both on one row, the P90 label drops to a second row.
struct BurnRateScale: View {
    let layout: BurnRateGaugeLayout

    static let width: CGFloat = 180
    private let pitch: CGFloat = 9
    private let dotSize: CGFloat = 4.4
    private let height: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                let midY = size.height / 2
                let fill = layout.tier == .high ? Theme.warning : Theme.paper
                for position in 0..<BurnRateGaugeLayout.dotCount {
                    let centerX = pitch * CGFloat(position) + pitch / 2
                    let rect = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(position < layout.filled ? fill : Theme.paper.opacity(0.22)))
                }
                for position in [layout.medianPosition, layout.p90Position] {
                    let x = min(max(position * size.width - 1, 0), size.width - 2)
                    context.fill(
                        Path(roundedRect: CGRect(x: x, y: 0, width: 2, height: size.height), cornerRadius: 1),
                        with: .color(Theme.paper.opacity(0.6))
                    )
                }
            }
            .frame(width: Self.width, height: height)
            labels
        }
        .accessibilityHidden(true)
    }

    private var labels: some View {
        let medianX = layout.medianPosition * Self.width
        let p90X = layout.p90Position * Self.width
        return ZStack(alignment: .topLeading) {
            label("Median \(formatTokenCount(layout.median))")
                .alignmentGuide(.leading) { -max(0, medianX - $0.width) }
            label("P90 \(formatTokenCount(layout.p90))")
                .alignmentGuide(.leading) { -min(p90X, Self.width - $0.width) }
                .offset(y: layout.stacksLabels ? 12 : 0)
        }
        .frame(width: Self.width, height: layout.stacksLabels ? 24 : 12, alignment: .topLeading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.paper.opacity(0.65))
            .fixedSize()
    }
}
