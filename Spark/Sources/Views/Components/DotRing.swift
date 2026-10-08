import SwiftUI

enum DotRingLayout {
    /// Radius of the dot circle in a square of `size`, leaving room for the dots and the time tick.
    static func radius(size: CGSize, dotSize: CGFloat) -> CGFloat {
        min(size.width, size.height) / 2 - dotSize - 4
    }

    /// Dot centres on a circle, starting at twelve o'clock and running clockwise in view
    /// coordinates (y grows downwards). `gap` leaves that many slots free, split around twelve
    /// o'clock, so start and end stay visible even on a full ring.
    static func points(count: Int, radius: CGFloat, center: CGPoint, gap: Int = 0) -> [CGPoint] {
        guard count > 0 else { return [] }
        let gap = max(gap, 0)
        let slots = Double(count + gap)
        // Half a step more than half the gap puts the first and last dot at the same distance
        // from twelve o'clock.
        let offset = gap > 0 ? Double(gap + 1) / 2 : 0
        return (0..<count).map { position in
            let angle = (Double(position) + offset) / slots * 2 * .pi - .pi / 2
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

/// A ring of dots for the session, with a gap at twelve o'clock. Hollow dots show the
/// projection, a short tick outside the ring the elapsed share of the window.
struct DotRing: View {
    var value: Double
    var projected: Double?
    var marker: Double?
    var tone: UsageTone = .normal
    /// Colours the hollow dots and the marker: grey (ink) when normal, else the tone's colour.
    var projectionTone: UsageTone = .normal
    var count = 40
    var gap = 2
    var dotSize: CGFloat = 6
    /// Fills the dots in sequence on appear and when the value rises (docs/design/rules.md, "Motion").
    var animatesFill = false
    /// Lets the hollow dots breathe, for a forecast that reaches the limit before the reset.
    var breathes = false

    var body: some View {
        ZStack {
            DotMotion(value: value, animates: animatesFill) { frame in
                baseCanvas(frame)
            }
            if projected != nil {
                DotRingProjectionLayer(
                    value: value, projected: projected, count: count, gap: gap, dotSize: dotSize,
                    color: projectionTone.color.opacity(0.55)
                )
                .equatable()
                .breathing(isActive: breathes && animatesFill)
            }
        }
        .accessibilityElement()
        .accessibilityValue(UsageFormat.percent(value))
    }

    private func baseCanvas(_ frame: DotMotionFrame) -> some View {
        Canvas { context, size in
            let layout = DotBarLayout(count: count, value: value, projected: projected, marker: marker)
            let radius = DotRingLayout.radius(size: size, dotSize: dotSize)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let points = DotRingLayout.points(count: count, radius: radius, center: center, gap: gap)
            for (position, dot) in DotBarLayout.baseDots(frame.dots(of: layout)).enumerated() {
                guard let dot else { continue }
                let rect = CGRect(x: points[position].x - dotSize / 2, y: points[position].y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(dot == .filled ? tone.color : Theme.dotTrack))
            }
            if let index = layout.markerIndex {
                let inner = DotRingLayout.points(count: count, radius: radius + dotSize / 2 + 1, center: center, gap: gap)[index]
                let outer = DotRingLayout.points(count: count, radius: radius + dotSize / 2 + 6, center: center, gap: gap)[index]
                var tick = Path()
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(tick, with: .color(projectionTone.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

/// The hollow dots of a ring, on their own `Equatable` layer like the bar's.
private struct DotRingProjectionLayer: View, Equatable {
    let value: Double
    let projected: Double?
    let count: Int
    let gap: Int
    let dotSize: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let layout = DotBarLayout(count: count, value: value, projected: projected)
            let radius = DotRingLayout.radius(size: size, dotSize: dotSize)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let points = DotRingLayout.points(count: count, radius: radius, center: center, gap: gap)
            for position in layout.projectedPositions {
                let rect = CGRect(x: points[position].x - dotSize / 2, y: points[position].y - dotSize / 2, width: dotSize, height: dotSize)
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(color), lineWidth: 1.2)
            }
        }
    }
}
