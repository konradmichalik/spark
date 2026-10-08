import SwiftUI

/// Which dot of a dot bar or dot ring is filled, projected or track. Pure, so it is unit tested;
/// `DotBar` and `DotRing` only draw it (docs/design/rules.md, "Dot language").
struct DotBarLayout: Equatable {
    enum Dot: Equatable { case filled, projected, track }

    let dots: [Dot]
    let markerIndex: Int?

    init(count: Int, value: Double, projected: Double? = nil, marker: Double? = nil) {
        let total = max(count, 0)
        func index(_ percent: Double) -> Int {
            guard percent.isFinite else { return percent > 0 ? total : 0 }
            return Int((min(max(percent, 0), 100) / 100 * Double(total)).rounded())
        }
        let filled = value.isFinite ? index(value) : 0
        let projectedEnd = projected.map { max(index($0), filled) } ?? filled
        dots = (0..<total).map { position in
            position < filled ? .filled : position < projectedEnd ? .projected : .track
        }
        markerIndex = total == 0 ? nil : marker.flatMap { $0.isFinite ? min(index($0), total - 1) : nil }
    }

    var filledCount: Int {
        dots.filter { $0 == .filled }.count
    }

    /// Positions of the hollow dots: the only ones the breathing layer draws.
    var projectedPositions: [Int] {
        dots.indices.filter { dots[$0] == .projected }
    }

    /// The dots with the hollow ones taken out, for the layer that never breathes.
    static func baseDots(_ dots: [Dot]) -> [Dot] {
        dots.map { $0 == .projected ? .track : $0 }
    }

    static func count(width: CGFloat, pitch: CGFloat) -> Int {
        guard width.isFinite, width > 0, pitch > 0 else { return 0 }
        return Int((width / pitch).rounded(.down))
    }
}

/// A row of dots for a usage value, with optional projection (hollow dots) and time marker.
/// The hollow dots sit on their own layer, so a breath only changes that layer's opacity and
/// never redraws the filled dots.
struct DotBar: View {
    var value: Double
    var projected: Double?
    var marker: Double?
    var tone: UsageTone = .normal
    /// Colours the hollow dots and the marker: grey (ink) when normal, else the tone's colour.
    var projectionTone: UsageTone = .normal
    var pitch: CGFloat = 6
    var dotSize: CGFloat = 3.8
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
                DotBarProjectionLayer(
                    value: value, projected: projected, pitch: pitch, dotSize: dotSize, color: projectionTone.color.opacity(0.55)
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
            let layout = DotBarLayout(
                count: DotBarLayout.count(width: size.width, pitch: pitch),
                value: value, projected: projected, marker: marker
            )
            let midY = size.height / 2
            for (position, dot) in DotBarLayout.baseDots(frame.dots(of: layout)).enumerated() {
                let centerX = pitch * CGFloat(position) + pitch / 2
                let rect = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(dot == .filled ? tone.color : Theme.dotTrack))
            }
            if let markerIndex = layout.markerIndex {
                let markerX = pitch * CGFloat(markerIndex) + pitch / 2 - 1
                let markerRect = CGRect(x: markerX, y: 0, width: 2, height: size.height)
                context.fill(Path(roundedRect: markerRect, cornerRadius: 1), with: .color(projectionTone.color))
            }
        }
    }
}

/// The hollow dots of a bar. `Equatable` and applied with `.equatable()`, so SwiftUI skips
/// redrawing the canvas while only the opacity around it changes.
private struct DotBarProjectionLayer: View, Equatable {
    let value: Double
    let projected: Double?
    let pitch: CGFloat
    let dotSize: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let layout = DotBarLayout(
                count: DotBarLayout.count(width: size.width, pitch: pitch), value: value, projected: projected
            )
            let midY = size.height / 2
            for position in layout.projectedPositions {
                let centerX = pitch * CGFloat(position) + pitch / 2
                let rect = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(color), lineWidth: 1.2)
            }
        }
    }
}
