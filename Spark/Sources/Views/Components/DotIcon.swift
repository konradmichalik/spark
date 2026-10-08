import SwiftUI

/// Small icons drawn in the dot language: the overview rows on a 4 × 4 grid, the service status
/// on a 5 × 5 grid (docs/design/rules.md, "Dot language").
enum DotIcon: CaseIterable {
    case statistics, limits
    case statusOK, statusDegraded, statusOutage, statusUnknown

    struct Dot: Equatable {
        let column: Int
        let row: Int
        let isFilled: Bool
    }

    var grid: Int {
        switch self {
        case .statistics, .limits: 4
        default: 5
        }
    }

    var dots: [Dot] {
        switch self {
        case .statistics:
            // Three bars of 2, 4 and 3 dots, standing on the bottom row.
            return [(0, 2), (1, 4), (2, 3)].flatMap { column, height in
                (0..<height).map { Dot(column: column, row: 3 - $0, isFilled: true) }
            }
        case .limits:
            // An octagon of eight dots, filled clockwise from the top, like a partly used ring.
            let ring = [(1, 0), (2, 0), (3, 1), (3, 2), (2, 3), (1, 3), (0, 2), (0, 1)]
            return ring.enumerated().map { index, cell in Dot(column: cell.0, row: cell.1, isFilled: index < 5) }
        default:
            return statusDots
        }
    }

    /// Service status patterns, all dots filled.
    private var statusDots: [Dot] {
        let filled: [(Int, Int)]
        switch self {
        case .statusOK:
            // A closed ring.
            filled = [(1, 0), (2, 0), (3, 0), (4, 1), (4, 2), (4, 3), (3, 4), (2, 4), (1, 4), (0, 3), (0, 2), (0, 1)]
        case .statusDegraded:
            // A triangle with a dot inside.
            filled = [(2, 0), (1, 1), (3, 1), (1, 2), (2, 2), (3, 2), (0, 3), (4, 3), (0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]
        case .statusOutage:
            // A cross.
            filled = [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4), (4, 0), (3, 1), (1, 3), (0, 4)]
        case .statusUnknown:
            // A question mark.
            filled = [(0, 1), (1, 0), (2, 0), (3, 0), (4, 1), (3, 2), (2, 2), (2, 4)]
        case .statistics, .limits:
            filled = []
        }
        return filled.map { Dot(column: $0.0, row: $0.1, isFilled: true) }
    }
}

struct DotIconView: View {
    let icon: DotIcon
    var size: CGFloat = 13
    var color: Color = Theme.inkSecondary

    var body: some View {
        Canvas { context, canvas in
            let pitch = canvas.width / CGFloat(icon.grid)
            let dot = pitch * 0.62
            for item in icon.dots {
                let center = CGPoint(x: pitch * (CGFloat(item.column) + 0.5), y: pitch * (CGFloat(item.row) + 0.5))
                let rect = CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)
                context.fill(Path(ellipseIn: rect), with: .color(item.isFilled ? color : color.opacity(0.3)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One cycle of the live dot's halo, pure so it is unit tested. The halo grows from 40 % to
/// 95 % of the icon and fades over 2.4 s, then snaps back without animation, so every cycle
/// starts the same (docs/design/rules.md, "Motion").
enum LiveDotHalo: CaseIterable {
    case start, end

    static let period = 2.4
    /// Halo diameter at the start of a cycle, as a share of the icon.
    static let diameter = 0.4

    var scale: Double { self == .start ? 1 : 0.95 / Self.diameter }
    var opacity: Double { self == .start ? 0.35 : 0 }

    /// The animation into this phase: the growth runs the whole period, the reset snaps.
    var animation: Animation? { self == .end ? .easeOut(duration: Self.period) : nil }
}

/// A dot with a soft halo while something is live, such as an active session, on the overview
/// row and the Active Sessions screen alike. The halo is a fixed-size layer that only scales
/// and fades, driven by its own phase loop, so re-renders and animations around it cannot
/// re-target it. It stays still under Reduce Motion and when nothing is live.
struct PulsingDot: View {
    let isLive: Bool
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isLive {
                if reduceMotion {
                    halo(.start)
                } else {
                    PhaseAnimator(LiveDotHalo.allCases) { phase in
                        halo(phase)
                    } animation: { phase in
                        phase.animation
                    }
                }
            }
            Circle()
                .fill(isLive ? Theme.accent : Theme.inkSecondary.opacity(0.4))
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func halo(_ phase: LiveDotHalo) -> some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: size * LiveDotHalo.diameter, height: size * LiveDotHalo.diameter)
            .scaleEffect(phase.scale)
            .opacity(phase.opacity)
    }
}
