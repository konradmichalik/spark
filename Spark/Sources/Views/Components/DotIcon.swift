import AppKit
import SwiftUI

/// Small icons drawn in the dot language: the overview rows on a 4 × 4 grid, the settings tabs
/// on a 5 × 5 grid (docs/design/rules.md, "Dot language").
enum DotIcon: CaseIterable {
    case statistics, limits
    case general, menuBar, display, connections, notifications, status, about

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
            return tabDots
        }
    }

    /// Settings tab patterns, filled dots first and dimmed ones as `false`.
    private var tabDots: [Dot] {
        let filled: [(Int, Int)]
        var dimmed: [(Int, Int)] = []
        switch self {
        case .general:
            // A gear: a ring of eight with four teeth.
            filled = [(1, 1), (2, 1), (3, 1), (1, 2), (3, 2), (1, 3), (2, 3), (3, 3), (2, 0), (4, 2), (2, 4), (0, 2)]
        case .menuBar:
            // A screen with a solid menu bar along the top.
            filled = (0..<5).map { ($0, 0) }
            dimmed = [(0, 1), (4, 1), (0, 2), (4, 2), (0, 3), (4, 3), (0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]
        case .display:
            // Four tiles.
            filled = [(0, 0), (1, 0), (0, 1), (1, 1), (3, 0), (4, 0), (3, 1), (4, 1), (0, 3), (1, 3), (0, 4), (1, 4), (3, 3), (4, 3), (3, 4), (4, 4)]
        case .connections:
            // Two linked ends on a diagonal.
            filled = [(0, 4), (1, 3), (2, 2), (3, 1), (4, 0), (0, 3), (4, 1)]
        case .notifications:
            // A bell.
            filled = [(2, 0), (1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (3, 2), (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (2, 4)]
        case .status:
            // A pulse line.
            filled = [(0, 2), (1, 2), (2, 0), (2, 1), (3, 3), (3, 4), (4, 2)]
        case .about:
            // An "i".
            filled = [(2, 0), (1, 2), (2, 2), (2, 3), (1, 4), (2, 4), (3, 4)]
        case .statistics, .limits:
            filled = []
        }
        return filled.map { Dot(column: $0.0, row: $0.1, isFilled: true) } + dimmed.map { Dot(column: $0.0, row: $0.1, isFilled: false) }
    }

    /// A template image for places that only take an `NSImage`, such as the Settings tab bar.
    func templateImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let pitch = rect.width / CGFloat(grid)
            let diameter = pitch * 0.62
            for dot in dots {
                let center = CGPoint(x: pitch * (CGFloat(dot.column) + 0.5), y: pitch * (CGFloat(dot.row) + 0.5))
                NSColor.black.withAlphaComponent(dot.isFilled ? 1 : 0.35).setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
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
