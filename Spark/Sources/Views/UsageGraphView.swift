import SwiftUI

private let graphHeight: CGFloat = 80
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

extension GraphTimeRange: SegmentLabeled {
    var segmentLabel: String { rawValue }
}

enum GraphMode: String, CaseIterable {
    case limits = "Limits"
    case volume = "Volume"
}

extension GraphMode: SegmentLabeled {
    var segmentLabel: String { rawValue }
}

struct UsageGraphView: View {
    let history: [UsageSnapshot]
    let rollups: [String: DailyRollup]
    @AppStorage("reduceTransparency") private var reduceTransparency: Bool = false
    @State private var graphMode: GraphMode = .limits
    @State private var timeRange: GraphTimeRange = .sixHours
    @State private var hoverTarget: GraphHoverTarget?
    @State private var canvasWidth: CGFloat = 0

    private static let density = SectionDensity.compact

    private var availableTimeRanges: [GraphTimeRange] { availableTimeRanges(for: graphMode) }

    /// Provides the time ranges supported by the specified graph mode.
    /// - Parameter mode: The graph mode whose supported ranges are requested.
    /// - Returns: Seven-day and thirty-day ranges for volume mode; all available ranges for limits mode.
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

        return VStack(alignment: .leading, spacing: Self.density.headerGap) {
            SectionHeader("History", icon: .history, density: Self.density) {
                SegmentPicker(selection: modeBinding, options: GraphMode.allCases)
            }

            SectionCard(density: Self.density) {
                HStack {
                    Spacer()
                    SegmentPicker(selection: $timeRange, options: availableTimeRanges)
                }

                if graphMode == .limits {
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

                    xAxisLabels(axis: axis)
                } else {
                    VolumeGraphView(rollups: rollups, timeRange: timeRange)
                }
            }
        }
        .onChange(of: timeRange) { hoverTarget = nil }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.width, initial: true) { _, width in
                    canvasWidth = width
                }
        }
    }

    // MARK: - Mode Binding

    /// The range correction lives here rather than an `.onChange(of: graphMode)` because
    /// `SegmentPicker` writes through a plain `Binding`: a follow-up `.onChange` leaves one render
    /// in between where the mode has switched but the time range hasn't, and Volume's rollup
    /// lookup treats an unadjusted sub-day range as "no data for today", flashing the empty state
    /// before the real chart appears. Correcting inside the same `set` keeps both changes atomic.
    private var modeBinding: Binding<GraphMode> {
        Binding(
            get: { graphMode },
            set: { newMode in
                withAnimation(.easeInOut(duration: 0.2)) {
                    graphMode = newMode
                    if !availableTimeRanges(for: newMode).contains(timeRange) {
                        timeRange = .sevenDays
                    }
                }
            }
        )
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

    /// Displays a tooltip for the hovered usage sample or inactivity gap.
    /// - Parameter samples: The usage snapshots available for point-based hover targets.
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
