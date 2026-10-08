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

/// A dot that pulses while something is live, such as an active session. It stays still under
/// Reduce Motion and when nothing is live (docs/design/rules.md, "Motion").
struct PulsingDot: View {
    let isLive: Bool
    var size: CGFloat = 13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            if isLive {
                Circle()
                    .fill(Theme.accent.opacity(isExpanded ? 0 : 0.35))
                    .frame(width: size * (isExpanded ? 0.95 : 0.4), height: size * (isExpanded ? 0.95 : 0.4))
            }
            Circle()
                .fill(isLive ? Theme.accent : Theme.inkSecondary.opacity(0.4))
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard isLive, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { isExpanded = true }
        }
        .accessibilityHidden(true)
    }
}
