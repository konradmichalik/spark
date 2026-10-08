import SwiftUI

/// History as dot columns: the session (or a day's volume) as grey columns, the week as a solid
/// red line on the same scale. Runs without data collapse into one narrow band and the line
/// breaks there (docs/design/rules.md, "Dot language"). Hovering marks the item under the
/// pointer and reads it out at once, beside the item on the side with more room.
struct DotColumnsChart: View {
    let columns: [HistoryColumn]
    /// The detail graph draws quarter grid lines and an ink crosshair; the overview card only a
    /// hairline guide.
    var isDetailed = false
    let readout: (HistoryItem) -> (title: String, body: String)?

    @State private var hovered: Int?

    private static let rowPitch: CGFloat = 6

    var body: some View {
        let items = HistoryLayout.items(columns)
        GeometryReader { proxy in
            Canvas { context, size in
                if isDetailed { drawGrid(in: &context, size: size) }
                draw(items, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = HistoryLayout.index(x: location.x, width: proxy.size.width, count: items.count)
                case .ended:
                    hovered = nil
                }
            }
            .overlay(alignment: .topLeading) { readoutView(items, width: proxy.size.width) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .onChange(of: columns.count) { hovered = nil }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for quarter in 1...4 {
            let y = (size.height * (1 - CGFloat(quarter) / 4)).rounded() + 0.5
            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Theme.hairline))
        }
    }

    private func draw(_ items: [HistoryItem], in context: inout GraphicsContext, size: CGSize) {
        guard !items.isEmpty else { return }
        let pitch = size.width / CGFloat(items.count)
        let highlighted = hovered ?? items.lastIndex { if case .column(let index) = $0 { columns[index].session != nil } else { false } }
        if let hovered {
            let guideX = pitch * (CGFloat(hovered) + 0.5)
            let guide = CGRect(x: guideX - 0.5, y: 0, width: 1, height: size.height)
            context.fill(Path(guide), with: .color(isDetailed ? Theme.ink : Theme.hairline))
        }
        var line = Path()
        var lineIsOpen = false
        for (position, item) in items.enumerated() {
            let centerX = pitch * (CGFloat(position) + 0.5)
            guard case .column(let index) = item else {
                let bandWidth = min(max(pitch - 2, 2), 6)
                let band = CGRect(x: centerX - bandWidth / 2, y: 0, width: bandWidth, height: size.height)
                context.fill(Path(roundedRect: band, cornerRadius: 2), with: .color(Theme.dotTrack.opacity(0.7)))
                lineIsOpen = false
                continue
            }
            let column = columns[index]
            if let session = column.session {
                drawColumn(session, x: centerX, pitch: pitch, isHighlighted: position == highlighted, in: &context, size: size)
            }
            guard let weekly = column.weekly else { continue }
            let point = CGPoint(x: centerX, y: size.height * (1 - min(max(weekly, 0), 100) / 100))
            if lineIsOpen {
                line.addLine(to: point)
            } else {
                // A segment can be a single point between two gaps; the dot keeps it visible.
                line.move(to: point)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(Theme.accent))
            }
            lineIsOpen = true
        }
        context.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
    }

    // swiftlint:disable:next function_parameter_count
    private func drawColumn(
        _ value: Double, x: CGFloat, pitch: CGFloat, isHighlighted: Bool, in context: inout GraphicsContext, size: CGSize
    ) {
        let dot = min(4, pitch - 1.5)
        let rows = Int((min(max(value, 0), 100) / 100 * Double(size.height / Self.rowPitch)).rounded())
        let colour = isHighlighted ? Theme.ink : Theme.ink.opacity(0.3)
        for row in 0..<max(rows, 1) {
            let centerY = size.height - 3 - CGFloat(row) * Self.rowPitch
            context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: centerY - dot / 2, width: dot, height: dot)), with: .color(colour))
        }
    }

    @ViewBuilder
    private func readoutView(_ items: [HistoryItem], width: CGFloat) -> some View {
        if let hovered, items.indices.contains(hovered), let text = readout(items[hovered]) {
            let itemX = width / CGFloat(items.count) * (CGFloat(hovered) + 0.5)
            let onLeft = itemX > width / 2
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.paper.opacity(0.65))
                Text(text.body)
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .tooltipChrome()
            .padding(onLeft ? .trailing : .leading, onLeft ? width - itemX + 8 : itemX + 8)
            .frame(width: width, alignment: onLeft ? .trailing : .leading)
        }
    }
}
