import SwiftUI

/// What the pointer currently sits on: a sample, or a collapsed gap band.
enum GraphHoverTarget: Equatable {
    case point(Int)
    case gap(CompressedTimeAxis.GapBand)
}

/// Draws the usage lines on a `CompressedTimeAxis`, breaking each line where the
/// app had no data (Mac asleep, app quit) instead of dropping it to 0%.
struct UsageGraphCanvas: View {
    let data: [UsageSnapshot]
    let axis: CompressedTimeAxis
    @Binding var hoverTarget: GraphHoverTarget?

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            drawGapBands(context: context, size: size)

            guard data.count >= 2, !axis.segments.isEmpty else {
                context.draw(
                    Text("Not enough data")
                        .font(.caption2)
                        .foregroundColor(.secondary),
                    at: CGPoint(x: size.width / 2, y: size.height / 2)
                )
                return
            }

            drawLine(context: context, size: size, color: Theme.graphWeekly) { $0.weeklyUtilization }
            drawLine(context: context, size: size, color: Theme.graphSession) { $0.sessionUtilization }
            drawLine(context: context, size: size, color: Theme.graphSonnet) { $0.sonnetUtilization }
            drawLine(context: context, size: size, color: Theme.graphOpus) { $0.opusUtilization }
            drawHoverIndicator(context: context, size: size)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverTarget = target(atX: location.x)
            case .ended:
                hoverTarget = nil
            }
        }
    }

    // MARK: - Hit testing

    private func target(atX x: CGFloat) -> GraphHoverTarget? {
        guard data.count >= 2, !axis.segments.isEmpty else { return nil }
        if let band = axis.gap(atX: x) { return .gap(band) }
        guard let index = nearestIndex(toX: x) else { return nil }
        return .point(index)
    }

    /// Nearest sample in pixel space — that keeps the pick from jumping across a gap.
    private func nearestIndex(toX x: CGFloat) -> Int? {
        data.indices.min {
            abs(axis.x(for: data[$0].timestamp) - x) < abs(axis.x(for: data[$1].timestamp) - x)
        }
    }

    // MARK: - Drawing

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        for threshold in [25.0, 50.0, 75.0, 100.0] {
            let y = size.height * (1 - threshold / 100)
            var gridPath = Path()
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            let opacity = threshold == 100.0 ? 0.3 : 0.15
            context.stroke(gridPath, with: .color(.gray.opacity(opacity)), lineWidth: 0.5)
        }
    }

    private func drawGapBands(context: GraphicsContext, size: CGSize) {
        for band in axis.gaps {
            let rect = CGRect(x: band.xStart, y: 0, width: band.xEnd - band.xStart, height: size.height)
            context.fill(Path(rect), with: .color(.gray.opacity(0.1)))

            for edge in [band.xStart, band.xEnd] {
                var line = Path()
                line.move(to: CGPoint(x: edge, y: 0))
                line.addLine(to: CGPoint(x: edge, y: size.height))
                context.stroke(
                    line,
                    with: .color(.gray.opacity(0.3)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
                )
            }
        }
    }

    /// `value` returns `nil` to skip a sample entirely — used for Sonnet/Opus, which are absent
    /// on snapshots recorded before those fields existed. A segment with no present values draws
    /// nothing; this is how an all-nil series (no Sonnet/Opus data yet) costs nothing to draw.
    private func drawLine(
        context: GraphicsContext,
        size: CGSize,
        color: Color,
        value: (UsageSnapshot) -> Double?
    ) {
        for segment in axis.segments {
            let points = data[segment.sampleRange].compactMap { sample -> CGPoint? in
                guard let utilization = value(sample) else { return nil }
                return CGPoint(x: axis.x(for: sample.timestamp), y: yPosition(utilization, in: size))
            }
            guard let first = points.first else { continue }

            // A lone sample between two gaps has no line to draw — show it as a dot.
            guard points.count > 1 else {
                let dot = CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                continue
            }

            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }

    private func drawHoverIndicator(context: GraphicsContext, size: CGSize) {
        guard case .point(let index) = hoverTarget, index < data.count else { return }
        let snapshot = data[index]
        let x = axis.x(for: snapshot.timestamp)

        var vLine = Path()
        vLine.move(to: CGPoint(x: x, y: 0))
        vLine.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(vLine, with: .color(.gray.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))

        let dotSize: CGFloat = 5
        let points: [(value: Double?, color: Color)] = [
            (snapshot.sessionUtilization, Theme.graphSession),
            (snapshot.weeklyUtilization, Theme.graphWeekly),
            (snapshot.sonnetUtilization, Theme.graphSonnet),
            (snapshot.opusUtilization, Theme.graphOpus)
        ]
        for (value, color) in points {
            guard let value else { continue }
            let y = yPosition(value, in: size)
            let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }

    private func yPosition(_ value: Double, in size: CGSize) -> CGFloat {
        size.height * (1 - min(value, 100) / 100)
    }
}
