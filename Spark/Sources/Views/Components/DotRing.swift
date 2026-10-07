import SwiftUI

enum DotRingLayout {
    /// Dot centres on a circle, starting at twelve o'clock and running clockwise in view
    /// coordinates (y grows downwards).
    static func points(count: Int, radius: CGFloat, center: CGPoint) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { position in
            let angle = Double(position) / Double(count) * 2 * .pi - .pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
        }
    }

    /// Opacity per dot for a template glyph: full dots at 1, the last partial dot proportional,
    /// the rest at `track`. Lets twelve dots show 45% instead of rounding to 42 or 50.
    static func partialOpacities(count: Int, value: Double, track: Double = 0.28) -> [Double] {
        guard count > 0 else { return [] }
        let clamped = value.isFinite ? min(max(value, 0), 100) : 0
        let filled = clamped / 100 * Double(count)
        return (0..<count).map { position in
            let share = filled - Double(position)
            if share >= 1 { return 1 }
            if share > 0 { return track + (1 - track) * share }
            return track
        }
    }
}

/// A ring of dots for a usage value. Session uses the outer ring (44 dots), week the inner one
/// (32 dots). The time marker is an enlarged hollow dot.
struct DotRing: View {
    var value: Double
    var projected: Double?
    var marker: Double?
    var tone: UsageTone = .normal
    var projectionReachesLimit = false
    var count = 44
    var dotSize: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let layout = DotBarLayout(count: count, value: value, projected: projected, marker: marker)
            let radius = min(size.width, size.height) / 2 - dotSize
            let points = DotRingLayout.points(count: count, radius: radius, center: CGPoint(x: size.width / 2, y: size.height / 2))
            for (position, point) in points.enumerated() {
                let isMarker = position == layout.markerIndex
                let diameter = isMarker ? dotSize + 3 : dotSize
                let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                if isMarker {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(Theme.ink), lineWidth: 1.5)
                    continue
                }
                switch layout.dots[position] {
                case .filled:
                    context.fill(Path(ellipseIn: rect), with: .color(tone.color))
                case .projected:
                    let stroke = projectionReachesLimit ? Theme.accent : Theme.ink.opacity(0.55)
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(stroke), lineWidth: 1.2)
                case .track:
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.dotTrack))
                }
            }
        }
        .accessibilityElement()
        .accessibilityValue(UsageFormat.percent(value))
    }
}
