import SwiftUI

/// One frame of the report's column motion: how many dots each column shows right now.
struct ReportColumnFrame {
    let rows: [Int]
    let from: [Int]
    let progress: Double

    func shown(_ index: Int) -> Int {
        guard rows.indices.contains(index) else { return 0 }
        guard from.indices.contains(index) else { return rows[index] }
        return ReportColumnMotion.shown(from: from[index], to: rows[index], index: index, count: rows.count, progress: progress)
    }
}

/// Grows the report's columns from the bottom, left to right, on appear and when a value rises;
/// a falling value shows at once. Under Reduce Motion it draws the end state
/// (docs/design/rules.md, "Motion").
struct ReportColumnGrowth<Content: View>: View {
    let rows: [Int]
    @ViewBuilder let content: (ReportColumnFrame) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var fillFrom: [Int] = []
    @State private var fillTarget: Double = 0

    var body: some View {
        let target = fillTarget
        let rows = rows
        let isWaiting = !reduceMotion && !hasAppeared
        // Before the first fill starts the columns are empty, so they do not flash at full height.
        let from = isWaiting ? Array(repeating: 0, count: rows.count) : fillFrom
        AnimatedValue(value: fillTarget) { phase in
            let progress = isWaiting ? 0 : DotFillSequence.progress(phase: phase, target: target)
            content(ReportColumnFrame(rows: rows, from: from, progress: progress))
        }
        .onAppear {
            hasAppeared = true
            fill(from: Array(repeating: 0, count: rows.count))
        }
        .onChange(of: rows) { old, new in
            if let starts = ReportColumnMotion.starts(old: old, new: new) { fill(from: starts) }
        }
    }

    private func fill(from starts: [Int]) {
        guard !reduceMotion else { return }
        fillFrom = starts
        withAnimation(.linear(duration: DotFillSequence.duration)) { fillTarget += 1 }
    }
}

/// The day labels under the report's columns, each centred on its column.
struct ReportDayAxisLabels: View {
    let labels: [ReportDayAxis.Label]
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            ForEach(labels, id: \.index) { label in
                Text(label.text)
                    .fixedSize()
                    .position(
                        x: ReportColumnLayout.centerX(index: label.index, count: count, width: proxy.size.width),
                        y: proxy.size.height / 2
                    )
            }
        }
        .frame(height: 14)
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.inkTertiary)
        .accessibilityHidden(true)
    }
}

/// The weekly line over one column per day, broken where a day has no weekly value.
private struct ReportWeekLineShape: Shape {
    let segments: [[ReportLinePoint]]
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in segments {
            for (position, point) in segment.enumerated() {
                let location = CGPoint(
                    x: rect.minX + ReportColumnLayout.centerX(index: point.index, count: count, width: rect.width),
                    y: rect.minY + rect.height * (1 - point.value / 100)
                )
                if position == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
            // A week point alone between two gaps becomes a dot through the round cap.
            if segment.count == 1, let point = path.currentPoint {
                path.addLine(to: CGPoint(x: point.x + 0.01, y: point.y))
            }
        }
        return path
    }
}

/// The solid `accent` weekly line, drawn from left to right when it appears. Decorative: the
/// graph around it carries the numbers for VoiceOver.
struct ReportWeekLineView: View {
    /// One per day, percent, `nil` for a day without a weekly value.
    let values: [Double?]
    var lineWidth: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        ReportWeekLineShape(segments: ReportWeekLine.segments(values), count: values.count)
            .trim(from: 0, to: reduceMotion ? 1 : drawn)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: ReportColumnMotion.lineDuration).delay(ReportColumnMotion.lineDelay)) {
                    drawn = 1
                }
            }
            .accessibilityHidden(true)
    }
}
