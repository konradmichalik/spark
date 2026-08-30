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

    /// Rollups have no resolution below a day, and a single day is a single bar — neither is
    /// meaningful as a Volume chart, so Volume mode only offers ranges that plot more than one.
    static let dayGranularityCases: [GraphTimeRange] = [.sevenDays, .thirtyDays]
}

enum GraphMode: String, CaseIterable {
    case limits = "Limits"
    case volume = "Volume"

    /// Icon-only segmented control labels — the full words don't fit on one line alongside the
    /// "History" label and the time-range buttons at the popover's 300pt width.
    var icon: TablerIcon {
        switch self {
        case .limits: .chartLine
        case .volume: .chartBar
        }
    }
}

struct UsageGraphView: View {
    let history: [UsageSnapshot]
    let rollups: [String: DailyRollup]
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @State private var graphMode: GraphMode = .limits
    @State private var timeRange: GraphTimeRange = .sixHours
    @State private var hoverTarget: GraphHoverTarget?
    @State private var canvasWidth: CGFloat = 0

    private var availableTimeRanges: [GraphTimeRange] { availableTimeRanges(for: graphMode) }

    private func availableTimeRanges(for mode: GraphMode) -> [GraphTimeRange] {
        mode == .volume ? GraphTimeRange.dayGranularityCases : GraphTimeRange.allCases
    }

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

            if graphMode == .limits {
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
                        hoverLegend(samples: samples)
                    }

                    yAxisLabels
                }

                xAxisLabels(axis: axis)
            } else {
                VolumeGraphView(rollups: rollups, timeRange: timeRange)
            }
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

    /// The mode toggle is icon-only (see `GraphMode.icon`) rather than spelling out
    /// "Limits"/"Volume" — that's what keeps the label, the toggle, and all five time-range
    /// buttons (`1h`…`30d`) fitting on one row within the popover's 300pt width. With the full
    /// words, this row would overflow, and since none of these views have a fixed size, SwiftUI
    /// would resolve the overflow by wrapping each button's text mid-word.
    private var header: some View {
        HStack {
            HStack(spacing: 4) {
                TablerIconView(.history, size: 11, color: Theme.graphSession)
                Text("History")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 2) {
                ForEach(GraphMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            graphMode = mode
                            // Corrected in the same update as the mode switch, not via a
                            // follow-up `.onChange` — that leaves one render in between where
                            // the mode has switched but the time range hasn't, and Volume's
                            // rollup lookup treats an unadjusted sub-day range as "no data for
                            // today," flashing the empty state before the real chart appears.
                            if !availableTimeRanges(for: mode).contains(timeRange) {
                                timeRange = .sevenDays
                            }
                        }
                    } label: {
                        // Selection was previously also cued by `.semibold` vs `.regular` weight;
                        // TablerIconView has no weight parameter, so for now selection is carried
                        // by colour and the background highlight below. Task 9 replaces this
                        // icon-only toggle with a text `SegmentPicker` whose labels restore the
                        // weight cue.
                        TablerIconView(mode.icon, size: 10, color: graphMode == mode ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                graphMode == mode
                                    ? Color.primary.opacity(0.1)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.rawValue)
                    .help(mode.rawValue)
                }
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach(availableTimeRanges, id: \.self) { range in
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

    /// Renders nothing for `nil` — Sonnet/Opus are absent on snapshots recorded before those
    /// fields existed, and on a Session/Weekly-only bucket the tooltip should just omit them.
    @ViewBuilder
    private func tooltipValue(_ value: Double?, color: Color) -> some View {
        if let value {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text("\(Int(value))%")
                    .foregroundColor(color)
            }
        }
    }

    @ViewBuilder
    private func hoverTooltip(samples: [UsageSnapshot]) -> some View {
        switch hoverTarget {
        case .point(let index) where index < samples.count:
            let snapshot = samples[index]
            HStack(spacing: 6) {
                Text(formatTimestamp(snapshot.timestamp))
                    .foregroundColor(.secondary)
                Spacer()
                tooltipValue(snapshot.sessionUtilization, color: Theme.graphSession)
                tooltipValue(snapshot.weeklyUtilization, color: Theme.graphWeekly)
                tooltipValue(snapshot.sonnetUtilization, color: Theme.graphSonnet)
                tooltipValue(snapshot.opusUtilization, color: Theme.graphOpus)
                tooltipValue(snapshot.fableUtilization, color: Theme.graphFable)
            }
            .modifier(TooltipStyle(reduceTransparency: reduceTransparency))
        case .gap(let band):
            HStack(spacing: 4) {
                TablerIconView(.moon, size: 12)
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
    private func hoverLegend(samples: [UsageSnapshot]) -> some View {
        if case .point = hoverTarget {
            HStack(spacing: 8) {
                legendItem("Session", color: Theme.graphSession)
                legendItem("Weekly", color: Theme.graphWeekly)
                // Omitted until real data exists, rather than always showing an entry for a
                // series that's empty for every launch before this feature shipped.
                if samples.contains(where: { $0.sonnetUtilization != nil }) {
                    legendItem("Sonnet", color: Theme.graphSonnet)
                }
                if samples.contains(where: { $0.opusUtilization != nil }) {
                    legendItem("Opus", color: Theme.graphOpus)
                }
                if samples.contains(where: { $0.fableUtilization != nil }) {
                    legendItem("Fable", color: Theme.graphFable)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .adaptiveBackground(reduceTransparency: reduceTransparency)
        }
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
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
