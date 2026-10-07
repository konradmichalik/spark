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

    static func count(width: CGFloat, pitch: CGFloat) -> Int {
        guard width.isFinite, width > 0, pitch > 0 else { return 0 }
        return Int((width / pitch).rounded(.down))
    }
}

/// A row of dots for a usage value, with optional projection (hollow dots) and time marker.
struct DotBar: View {
    var value: Double
    var projected: Double?
    var marker: Double?
    var tone: UsageTone = .normal
    var pitch: CGFloat = 6
    var dotSize: CGFloat = 3.8

    var body: some View {
        Canvas { context, size in
            let layout = DotBarLayout(
                count: DotBarLayout.count(width: size.width, pitch: pitch),
                value: value, projected: projected, marker: marker
            )
            let midY = size.height / 2
            for (position, dot) in layout.dots.enumerated() {
                let centerX = pitch * CGFloat(position) + pitch / 2
                let rect = CGRect(x: centerX - dotSize / 2, y: midY - dotSize / 2, width: dotSize, height: dotSize)
                switch dot {
                case .filled:
                    context.fill(Path(ellipseIn: rect), with: .color(tone.color))
                case .projected:
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.6, dy: 0.6)), with: .color(Theme.ink.opacity(0.55)), lineWidth: 1.2)
                case .track:
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.dotTrack))
                }
            }
            if let markerIndex = layout.markerIndex {
                let markerX = pitch * CGFloat(markerIndex) + pitch / 2 - 1
                context.fill(Path(roundedRect: CGRect(x: markerX, y: 0, width: 2, height: size.height), cornerRadius: 1), with: .color(Theme.ink))
            }
        }
        .accessibilityElement()
        .accessibilityValue(UsageFormat.percent(value))
    }
}
