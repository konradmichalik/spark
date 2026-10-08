import SwiftUI

/// Small icons drawn in the dot language for the overview rows, on a 4 × 4 grid
/// (docs/design/rules.md, "Dot language").
enum DotIcon: CaseIterable {
    case statistics, limits

    struct Dot: Equatable {
        let column: Int
        let row: Int
        let isFilled: Bool
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
        }
    }
}

struct DotIconView: View {
    let icon: DotIcon
    var size: CGFloat = 13
    var color: Color = Theme.inkSecondary

    var body: some View {
        Canvas { context, canvas in
            let pitch = canvas.width / 4
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
    var color: Color = Theme.accent
    var restingColor: Color = Theme.inkSecondary.opacity(0.4)

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
                .fill(isLive ? color : restingColor)
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func halo(_ phase: LiveDotHalo) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * LiveDotHalo.diameter, height: size * LiveDotHalo.diameter)
            .scaleEffect(phase.scale)
            .opacity(phase.opacity)
    }
}

/// The service status as one dot (docs/design/rules.md, "Dot language"). A healthy status is a
/// plain dot in `healthyColor`, an incident pulses in its tone, an unreadable status is a ring.
struct StatusDotView: View {
    let dot: StatusDot
    var size: CGFloat = 14
    var healthyColor: Color = Theme.ink

    var body: some View {
        if dot.isHollow {
            Circle()
                .strokeBorder(Theme.inkSecondary, lineWidth: 1.5)
                .frame(width: size * 0.42, height: size * 0.42)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            let color = dot.tone == .normal ? healthyColor : dot.tone.color
            PulsingDot(isLive: dot.pulses, size: size, color: color, restingColor: color)
        }
    }
}
