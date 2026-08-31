import SwiftUI

// MARK: - Model Row

/// One model family's token share for the shown period, ready to render as a donut segment or a
/// legend row.
struct ModelRow: Identifiable {
    let id: String
    let label: String
    let tokens: Int
    let family: ModelFamily

    /// Keyed on `family`, not the display `label` string — a relabel must never silently desync
    /// the donut/legend color from what it represents.
    var color: Color {
        switch family {
        case .sonnet: Theme.graphSonnet
        case .opus: Theme.graphOpus
        case .fable: Theme.graphFable
        case .other: .secondary
        }
    }

    static func rows(from modelTotals: [String: Int]) -> [ModelRow] {
        let families: [(ModelFamily, String)] = [(.sonnet, "Sonnet"), (.opus, "Opus"), (.fable, "Fable"), (.other, "Other")]
        var rows: [ModelRow] = []
        for (family, label) in families {
            var tokens = 0
            for (rawId, value) in modelTotals where ModelFamily.family(forRawModelId: rawId) == family {
                tokens += value
            }
            if tokens > 0 {
                rows.append(ModelRow(id: label, label: label, tokens: tokens, family: family))
            }
        }
        return rows
    }
}

// MARK: - Model Donut Chart

struct ModelDonutChart: View {
    let rows: [ModelRow]

    private static let ringWidth: CGFloat = 13
    private static let gapDegrees: Double = 3
    private static let size: CGFloat = 74

    private var total: Int { rows.reduce(0) { $0 + $1.tokens } }

    private var gapFraction: Double { rows.count > 1 ? Self.gapDegrees / 360 : 0 }

    private struct Segment: Identifiable {
        let row: ModelRow
        let start: Double
        let end: Double
        var id: String { row.id }
    }

    private var segments: [Segment] {
        guard total > 0 else { return [] }
        var cursor = 0.0
        return rows.map { row in
            let fraction = Double(row.tokens) / Double(total)
            let start = cursor
            cursor += fraction
            return Segment(row: row, start: start, end: cursor)
        }
    }

    var body: some View {
        ZStack {
            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: max(segment.start, segment.end - gapFraction))
                    .stroke(segment.row.color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        // Inset by half the stroke width so the stroke (centered on each circle's path) stays
        // fully inside the frame instead of bleeding past it on every side.
        .padding(Self.ringWidth / 2)
        .frame(width: Self.size, height: Self.size)
        // Decorative: this is a pure proportion chart with no content of its own — the adjacent
        // legend already states every label/color/token-count pair as text.
        .accessibilityHidden(true)
    }
}

// MARK: - Pace Graph

/// A compact two-line chart of one point per day's peak session/weekly utilization (see
/// `PaceDaySeries`), with day tick marks and a hover readout. Plotting raw polled snapshots
/// directly was too dense to read at a week/month zoom — session utilization alone resets every
/// 5h, so raw samples draw many sawtooth cycles a day; aggregating to one point per day is what
/// actually reads as an at-a-glance trend.
struct PaceGraph: View {
    let days: [PaceDay]

    @State private var hoverIndex: Int?

    private static let chartHeight: CGFloat = 44

    private func x(forIndex index: Int, width: CGFloat) -> CGFloat {
        guard days.count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(days.count - 1)
    }

    /// Every day gets a tick for a week's ~7 days; thinned to roughly 6 for a month's ~30, so
    /// labels don't overlap.
    private var dayTickIndices: [Int] {
        guard days.count > 8 else { return Array(days.indices) }
        let stride = Int((Double(days.count) / 6).rounded(.up))
        return days.indices.filter { $0 % stride == 0 }
    }

    private func nearestIndex(toX targetX: CGFloat, width: CGFloat) -> Int? {
        guard days.count > 1 else { return days.indices.first }
        let raw = Int((targetX / width * CGFloat(days.count - 1)).rounded())
        return min(max(raw, 0), days.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                Canvas { context, size in
                    drawIdleBands(context: context, size: size)
                    draw(context: context, size: size, color: Theme.graphWeekly) { $0.weeklyUtilization }
                    draw(context: context, size: size, color: Theme.graphSession) { $0.sessionUtilization }
                    if let hoverIndex, days.indices.contains(hoverIndex) {
                        let hx = x(forIndex: hoverIndex, width: size.width)
                        var line = Path()
                        line.move(to: CGPoint(x: hx, y: 0))
                        line.addLine(to: CGPoint(x: hx, y: size.height))
                        context.stroke(line, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverIndex = nearestIndex(toX: location.x, width: width)
                    case .ended:
                        hoverIndex = nil
                    }
                }
            }
            .frame(height: Self.chartHeight)

            dayAxis

            if let hoverIndex, days.indices.contains(hoverIndex) {
                hoverReadout(days[hoverIndex])
            } else {
                legend
            }
        }
        // Hover-only detail with no static text equivalent (unlike the donut, whose legend
        // already states every value) — give VoiceOver a range summary instead of nothing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        // A period switch swaps `days` (and can change `hoverIndex`'s meaning entirely) without
        // necessarily moving the pointer — clear any stale hover from the prior period.
        .onChange(of: days.count) { hoverIndex = nil }
    }

    private var accessibilitySummary: String {
        guard let first = days.first?.day, let last = days.last?.day else {
            return "Session and weekly pace, no data"
        }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "Session and weekly pace from \(first.formatted(style)) to \(last.formatted(style))"
    }

    /// A faint full-height band over each run of consecutive idle days, mirroring
    /// `VolumeGraphView`'s `idleLane` treatment and `UsageGraphCanvas`'s gap bands. Each band's
    /// edges sit exactly on the nearest surrounding data point (not the midpoint to it), so the
    /// shaded region touches the line instead of leaving a sliver of blank space between them.
    private func drawIdleBands(context: GraphicsContext, size: CGSize) {
        guard days.count > 1 else { return }
        var index = 0
        while index < days.count {
            guard !days[index].hasData else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd + 1 < days.count, !days[runEnd + 1].hasData {
                runEnd += 1
            }

            let leftEdge = index > 0 ? x(forIndex: index - 1, width: size.width) : 0
            let rightEdge = runEnd < days.count - 1 ? x(forIndex: runEnd + 1, width: size.width) : size.width
            context.fill(
                Path(CGRect(x: leftEdge, y: 0, width: rightEdge - leftEdge, height: size.height)),
                with: .color(.gray.opacity(0.09))
            )

            index = runEnd + 1
        }
    }

    /// `value` returns `nil` for an idle day (no snapshot at all) — the line breaks there instead
    /// of connecting across it, the same "skip rather than interpolate" rule `UsageGraphCanvas`
    /// uses for Sonnet/Opus samples that predate those fields.
    private func draw(context: GraphicsContext, size: CGSize, color: Color, value: (PaceDay) -> Double?) {
        var path = Path()
        var isDrawing = false
        for (index, day) in days.enumerated() {
            guard let utilization = value(day) else {
                isDrawing = false
                continue
            }
            let point = CGPoint(
                x: x(forIndex: index, width: size.width),
                y: size.height * (1 - CGFloat(min(max(utilization, 0), 100) / 100))
            )
            if isDrawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                isDrawing = true
            }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private var dayAxis: some View {
        GeometryReader { proxy in
            // `Text` is centered on its `.position`, so a tick exactly at the leading/trailing
            // edge would have half its label clipped by the container's bounds (a "18" rendering
            // as "8") — inset every tick by half a label's width so the full text stays visible.
            let halfLabelWidth: CGFloat = 8
            ForEach(dayTickIndices, id: \.self) { index in
                let rawX = x(forIndex: index, width: proxy.size.width)
                Text(days[index].day.formatted(Date.FormatStyle().day()))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                    .position(
                        x: min(max(rawX, halfLabelWidth), proxy.size.width - halfLabelWidth),
                        y: proxy.size.height / 2
                    )
            }
        }
        .frame(height: 10)
    }

    private func hoverReadout(_ day: PaceDay) -> some View {
        HStack(spacing: 8) {
            Text(day.day.formatted(Date.FormatStyle().month(.abbreviated).day()))
                .foregroundColor(.secondary)
            if let session = day.sessionUtilization {
                dot(color: Theme.graphSession, text: "\(Int(session))%")
            }
            if let weekly = day.weeklyUtilization {
                dot(color: Theme.graphWeekly, text: "\(Int(weekly))%")
            }
            if !day.hasData {
                Text("No data")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption2)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            dot(color: Theme.graphSession, text: "Session")
            dot(color: Theme.graphWeekly, text: "Weekly")
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }

    private func dot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }
}

// MARK: - Trend Badge

struct TrendBadge: View {
    let percent: Double
    /// "week" / "month" — names what the comparison is against, e.g. "Up 12% from the ___ before".
    let comparisonNoun: String

    private enum Direction { case up, down, flat }

    /// Direction is decided from the rounded, displayed value, not the raw percent — otherwise
    /// e.g. -0.3% rounds to "0%" in the label while still rendering a down arrow.
    private var roundedPercent: Int { Int(percent.rounded()) }

    private var direction: Direction {
        if roundedPercent > 0 { return .up }
        if roundedPercent < 0 { return .down }
        return .flat
    }

    private var icon: TablerIcon {
        switch direction {
        case .up: .arrowUp
        case .down: .arrowDown
        case .flat: .arrowRight
        }
    }

    private var accessibilityText: String {
        switch direction {
        case .up: "Up \(roundedPercent)% from the \(comparisonNoun) before"
        case .down: "Down \(abs(roundedPercent))% from the \(comparisonNoun) before"
        case .flat: "Unchanged from the \(comparisonNoun) before"
        }
    }

    /// Color is a reinforcement, never the only signal — the arrow direction and the percent
    /// text already say the same thing regardless of color.
    private var tintColor: Color {
        switch direction {
        case .up: Theme.sparkOrangeIcon
        case .down: Theme.trendDown
        case .flat: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            TablerIconView(icon, size: 11, color: tintColor)
            Text("\(abs(roundedPercent))%")
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundColor(tintColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}
