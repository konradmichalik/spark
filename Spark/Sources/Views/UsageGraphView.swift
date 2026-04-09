import SwiftUI

private let claudeOrange = Theme.sparkOrange
private let weeklyGray = Color(nsColor: NSColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1))
private let graphHeight: CGFloat = 80
private let yAxisWidth: CGFloat = 32
private let xAxisHeight: CGFloat = 14

enum GraphTimeRange: String, CaseIterable {
    case oneHour = "1h"
    case sixHours = "6h"
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"

    var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 3600 * 6
        case .oneDay: 3600 * 24
        case .sevenDays: 3600 * 24 * 7
        case .thirtyDays: 3600 * 24 * 30
        }
    }
}

struct UsageGraphView: View {
    let history: [UsageSnapshot]
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @State private var timeRange: GraphTimeRange = .sixHours
    @State private var hoverIndex: Int?

    private var windowEnd: Date { Date() }
    private var windowStart: Date { windowEnd.addingTimeInterval(-timeRange.seconds) }

    /// Maximum gap (seconds) before we assume the app was inactive and insert 0% anchors.
    private static let gapThreshold: TimeInterval = 45 * 60

    private var filteredHistory: [UsageSnapshot] {
        let raw = history.filter { $0.timestamp > windowStart }

        var result: [UsageSnapshot] = []
        for (index, snap) in raw.enumerated() {
            let previous = index == 0 ? windowStart : raw[index - 1].timestamp
            let gap = snap.timestamp.timeIntervalSince(previous)

            if gap > Self.gapThreshold {
                // Drop to 0% right after the previous point
                result.append(UsageSnapshot(
                    timestamp: previous.addingTimeInterval(1),
                    sessionUtilization: 0,
                    weeklyUtilization: 0
                ))
                // Stay at 0% right before this point
                result.append(UsageSnapshot(
                    timestamp: snap.timestamp.addingTimeInterval(-1),
                    sessionUtilization: 0,
                    weeklyUtilization: 0
                ))
            }
            result.append(snap)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundColor(claudeOrange)
                    Text("History")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(GraphTimeRange.allCases, id: \.self) { range in
                        Button {
                            timeRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 10, weight: timeRange == range ? .semibold : .regular))
                                .foregroundColor(timeRange == range ? .primary : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    timeRange == range
                                        ? Color.primary.opacity(0.1)
                                        : Color.clear
                                )
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Graph area with Y-axis
            HStack(alignment: .top, spacing: 0) {
                graphCanvas
                    .frame(height: graphHeight)
                    .overlay(alignment: .topLeading) {
                        hoverTooltip
                    }
                    .overlay(alignment: .bottomLeading) {
                        hoverLegend
                    }

                // Y-axis labels (right)
                VStack(alignment: .trailing) {
                    Text("100%").frame(height: 1)
                    Spacer()
                    Text("75%")
                    Spacer()
                    Text("50%")
                    Spacer()
                    Text("25%")
                    Spacer()
                    Text("0%").frame(height: 1)
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: yAxisWidth, height: graphHeight)
            }

            // X-axis time labels
            xAxisLabels
        }
        .onChange(of: timeRange) { hoverIndex = nil }
    }

    // MARK: - Hover Tooltip

    @ViewBuilder
    private var hoverTooltip: some View {
        if let idx = hoverIndex, idx < filteredHistory.count {
            let snap = filteredHistory[idx]
            HStack(spacing: 6) {
                Text(formatTimestamp(snap.timestamp))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(claudeOrange).frame(width: 5, height: 5)
                    Text("\(Int(snap.sessionUtilization))%")
                        .foregroundColor(claudeOrange)
                }
                HStack(spacing: 3) {
                    Circle().fill(weeklyGray).frame(width: 5, height: 5)
                    Text("\(Int(snap.weeklyUtilization))%")
                        .foregroundColor(weeklyGray)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .adaptiveBackground(reduceTransparency: reduceTransparency)
        }
    }

    // MARK: - Hover Legend

    @ViewBuilder
    private var hoverLegend: some View {
        if hoverIndex != nil {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle().fill(claudeOrange).frame(width: 5, height: 5)
                    Text("Session")
                }
                HStack(spacing: 3) {
                    Circle().fill(weeklyGray).frame(width: 5, height: 5)
                    Text("Weekly")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .adaptiveBackground(reduceTransparency: reduceTransparency)
        }
    }

    // MARK: - Graph Canvas

    private var graphCanvas: some View {
        GeometryReader { geometry in
            let data = filteredHistory
            let size = geometry.size
            let start = windowStart
            let end = windowEnd
            let duration = end.timeIntervalSince(start)

            Canvas { context, canvasSize in
                // Grid lines at 25%, 50%, 75%, 100%
                for threshold in [25.0, 50.0, 75.0, 100.0] {
                    let y = canvasSize.height * (1 - threshold / 100)
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    let opacity = threshold == 100.0 ? 0.3 : 0.15
                    context.stroke(gridPath, with: .color(.gray.opacity(opacity)), lineWidth: 0.5)
                }

                guard data.count >= 2, duration > 0 else {
                    context.draw(
                        Text("Not enough data")
                            .font(.caption2)
                            .foregroundColor(.secondary),
                        at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    )
                    return
                }

                // Time-proportional X position for a snapshot
                func xPos(_ timestamp: Date) -> CGFloat {
                    let t = timestamp.timeIntervalSince(start) / duration
                    return canvasSize.width * CGFloat(t)
                }

                // Draw time-proportional lines
                drawTimeLine(
                    context: context, data: data, size: canvasSize,
                    color: weeklyGray, start: start, duration: duration,
                    keyPath: \.weeklyUtilization
                )
                drawTimeLine(
                    context: context, data: data, size: canvasSize,
                    color: claudeOrange, start: start, duration: duration,
                    keyPath: \.sessionUtilization
                )

                // Hover indicator
                if let idx = hoverIndex, idx < data.count {
                    let x = xPos(data[idx].timestamp)

                    // Vertical line
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: x, y: 0))
                    vLine.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(vLine, with: .color(.gray.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))

                    // Dots
                    let sessionY = canvasSize.height * (1 - min(data[idx].sessionUtilization, 100) / 100)
                    let weeklyY = canvasSize.height * (1 - min(data[idx].weeklyUtilization, 100) / 100)
                    let dotSize: CGFloat = 5

                    context.fill(
                        Path(ellipseIn: CGRect(x: x - dotSize / 2, y: sessionY - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(claudeOrange)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - dotSize / 2, y: weeklyY - dotSize / 2, width: dotSize, height: dotSize)),
                        with: .color(weeklyGray)
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard data.count >= 2, duration > 0 else {
                        hoverIndex = nil
                        return
                    }
                    // Find nearest data point to mouse X
                    let hoverTime = start.addingTimeInterval(duration * Double(location.x / size.width))
                    var bestIdx = 0
                    var bestDist = Double.infinity
                    for (i, snap) in data.enumerated() {
                        let dist = abs(snap.timestamp.timeIntervalSince(hoverTime))
                        if dist < bestDist {
                            bestDist = dist
                            bestIdx = i
                        }
                    }
                    hoverIndex = bestIdx
                case .ended:
                    hoverIndex = nil
                }
            }
        }
    }

    // MARK: - X-Axis

    private var xAxisLabels: some View {
        let tickCount = 3
        let start = windowStart
        let end = windowEnd

        return HStack {
            ForEach(0..<tickCount, id: \.self) { i in
                if i > 0 { Spacer() }
                let fraction = Double(i) / Double(tickCount - 1)
                let date = Date(
                    timeIntervalSince1970: start.timeIntervalSince1970
                        + fraction * end.timeIntervalSince(start)
                )
                Text(formatAxisTime(date))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer().frame(width: yAxisWidth)
        }
        .frame(height: xAxisHeight)
    }

    // MARK: - Drawing

    // swiftlint:disable:next function_parameter_count
    private func drawTimeLine(
        context: GraphicsContext,
        data: [UsageSnapshot],
        size: CGSize,
        color: Color,
        start: Date,
        duration: TimeInterval,
        keyPath: KeyPath<UsageSnapshot, Double>
    ) {
        guard data.count >= 2, duration > 0 else { return }

        var path = Path()
        for (index, snap) in data.enumerated() {
            let t = snap.timestamp.timeIntervalSince(start) / duration
            let x = size.width * CGFloat(t)
            let y = size.height * (1 - min(snap[keyPath: keyPath], 100) / 100)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - Formatting

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        if timeRange == .sevenDays || timeRange == .thirtyDays {
            formatter.dateFormat = "dd.MM HH:mm"
        } else {
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }

    private func formatAxisTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if timeRange == .sevenDays || timeRange == .thirtyDays {
            formatter.dateFormat = "dd.MM"
        } else {
            formatter.dateFormat = "HH:mm"
        }
        return formatter.string(from: date)
    }
}
