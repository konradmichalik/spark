import SwiftUI

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
    @State private var hoverTarget: GraphHoverTarget?
    @State private var canvasWidth: CGFloat = 0

    /// Maximum gap (seconds) before we assume the app was inactive — anything longer
    /// is collapsed into a narrow band instead of stretching the axis.
    private static let gapThreshold: TimeInterval = 45 * 60

    private func windowedHistory(now: Date) -> [UsageSnapshot] {
        let windowStart = now.addingTimeInterval(-timeRange.seconds)
        return history.filter { $0.timestamp > windowStart }
    }

    var body: some View {
        // Samples and axis are derived once per pass from a single `now`, so every
        // consumer sees the same window and the axis' sample ranges always match.
        let samples = windowedHistory(now: Date())
        let axis = CompressedTimeAxis(
            timestamps: samples.map(\.timestamp),
            width: canvasWidth,
            gapThreshold: Self.gapThreshold
        )

        return VStack(alignment: .leading, spacing: 4) {
            header

            HStack(alignment: .top, spacing: 0) {
                UsageGraphCanvas(
                    data: samples,
                    axis: axis,
                    hoverTarget: $hoverTarget
                )
                .frame(height: graphHeight)
                .background(widthReader)
                .overlay(alignment: .topLeading) {
                    hoverTooltip(samples: samples)
                }
                .overlay(alignment: .bottomLeading) {
                    hoverLegend
                }

                yAxisLabels
            }

            xAxisLabels(axis: axis)
        }
        .onChange(of: timeRange) { hoverTarget = nil }
    }

    private var yAxisLabels: some View {
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

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width, initial: true) { _, width in
                    canvasWidth = width
                }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundColor(Theme.graphSession)
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
    }

    // MARK: - Hover Tooltip

    @ViewBuilder
    private func hoverTooltip(samples: [UsageSnapshot]) -> some View {
        switch hoverTarget {
        case .point(let index) where index < samples.count:
            let snapshot = samples[index]
            HStack(spacing: 6) {
                Text(formatTimestamp(snapshot.timestamp))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(Theme.graphSession).frame(width: 5, height: 5)
                    Text("\(Int(snapshot.sessionUtilization))%")
                        .foregroundColor(Theme.graphSession)
                }
                HStack(spacing: 3) {
                    Circle().fill(Theme.graphWeekly).frame(width: 5, height: 5)
                    Text("\(Int(snapshot.weeklyUtilization))%")
                        .foregroundColor(Theme.graphWeekly)
                }
            }
            .modifier(TooltipStyle(reduceTransparency: reduceTransparency))
        case .gap(let band):
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                Text("\(band.duration.shortDuration) · no data")
            }
            .foregroundColor(.secondary)
            .modifier(TooltipStyle(reduceTransparency: reduceTransparency))
        default:
            EmptyView()
        }
    }

    // MARK: - Hover Legend

    @ViewBuilder
    private var hoverLegend: some View {
        if case .point = hoverTarget {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle().fill(Theme.graphSession).frame(width: 5, height: 5)
                    Text("Session")
                }
                HStack(spacing: 3) {
                    Circle().fill(Theme.graphWeekly).frame(width: 5, height: 5)
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

    // MARK: - X-Axis

    /// Labels sit at fixed positions but report the time actually shown there —
    /// on a compressed axis that is no longer a linear function of the window.
    private func xAxisLabels(axis: CompressedTimeAxis) -> some View {
        let tickCount = 3

        return HStack {
            ForEach(0..<tickCount, id: \.self) { index in
                if index > 0 { Spacer() }
                let fraction = CGFloat(index) / CGFloat(tickCount - 1)
                Text(axis.date(atX: canvasWidth * fraction).map(formatAxisTime) ?? "")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer().frame(width: yAxisWidth)
        }
        .frame(height: xAxisHeight)
    }

    // MARK: - Formatting

    private var usesDateInLabels: Bool {
        timeRange == .sevenDays || timeRange == .thirtyDays
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = usesDateInLabels ? "dd.MM HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    private func formatAxisTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = usesDateInLabels ? "dd.MM" : "HH:mm"
        return formatter.string(from: date)
    }
}

private struct TooltipStyle: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(.caption2, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .adaptiveBackground(reduceTransparency: reduceTransparency)
    }
}
