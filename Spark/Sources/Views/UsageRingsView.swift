import SwiftUI

// MARK: - Ring Data

struct RingData {
    let label: String
    let utilization: Double
    let resetTime: String?
    let resetDate: Date?
    let projection: ProjectionResult
    let ringIndex: Int
}

// MARK: - Single Ring Arc

struct RingArc: View {
    let utilization: Double
    let projection: ProjectionResult
    let color: Color
    let trackColor: Color
    let ringWidth: CGFloat
    let size: CGFloat

    private var fillFraction: Double {
        min(utilization, 100) / 100
    }

    private var projectedFraction: Double {
        switch projection {
        case .limitReached:
            return 1.0
        case .safe(let projected):
            return min(projected, 100) / 100
        case .insufficientData:
            return 0
        }
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: ringWidth)

            // Projection arc (behind fill) — gray like the bar projection
            if projectedFraction > fillFraction {
                Circle()
                    .trim(from: 0, to: projectedFraction)
                    .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            // Fill arc
            if fillFraction > 0 {
                Circle()
                    .trim(from: 0, to: fillFraction)
                    .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Ring Tooltip

struct RingTooltip: View {
    let ring: RingData

    var body: some View {
        VStack(spacing: 2) {
            Text(ring.label)
                .fontWeight(.medium)
            Text("\(Int(ring.utilization))%")
                .font(.system(.caption, design: .monospaced))
            if let resetTime = ring.resetTime {
                Text("Resets in \(resetTime)")
                    .foregroundColor(.secondary)
            }
            if let projectionText = projectionText {
                Text(projectionText)
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption2)
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var projectionText: String? {
        switch ring.projection {
        case .limitReached(let seconds):
            return "Limit in ~\(seconds.shortDuration)"
        case .safe(let projected):
            return "~\(Int(projected))% at reset"
        case .insufficientData:
            return nil
        }
    }
}

// MARK: - Concentric Rings

struct ConcentricRingsView: View {
    let rings: [RingData]
    let warningThreshold: Double
    let criticalThreshold: Double
    let showProjection: Bool

    private let outerSize: CGFloat = 100
    private let ringWidth: CGFloat = 8
    private let ringGap: CGFloat = 4

    @State private var hoveredIndex: Int?

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                let size = outerSize - CGFloat(index) * (ringWidth * 2 + ringGap)
                let color = Theme.ringColor(
                    utilization: ring.utilization,
                    warningThreshold: warningThreshold,
                    criticalThreshold: criticalThreshold,
                    ringIndex: ring.ringIndex
                )

                RingArc(
                    utilization: ring.utilization,
                    projection: showProjection ? ring.projection : .insufficientData,
                    color: color,
                    trackColor: color.opacity(0.15),
                    ringWidth: ringWidth,
                    size: size
                )
                .onHover { isHovered in
                    DispatchQueue.main.async {
                        hoveredIndex = isHovered ? index : nil
                    }
                }
                .opacity(hoveredIndex == nil || hoveredIndex == index ? 1.0 : 0.6)
                .accessibilityElement()
                .accessibilityLabel("\(ring.label) usage \(Int(ring.utilization)) percent")
                .accessibilityValue(ring.resetTime.map { "Resets in \($0)" } ?? "")
            }

            // Hover tooltip
            if let idx = hoveredIndex, idx < rings.count {
                RingTooltip(ring: rings[idx])
            }
        }
        .frame(width: outerSize, height: outerSize)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Side-by-Side Rings

struct SeparateRingsView: View {
    let rings: [RingData]
    let warningThreshold: Double
    let criticalThreshold: Double
    let showProjection: Bool

    private let ringSize: CGFloat = 60
    private let ringWidth: CGFloat = 6

    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                let color = Theme.ringColor(
                    utilization: ring.utilization,
                    warningThreshold: warningThreshold,
                    criticalThreshold: criticalThreshold,
                    ringIndex: ring.ringIndex
                )

                VStack(spacing: 4) {
                    ZStack {
                        RingArc(
                            utilization: ring.utilization,
                            projection: showProjection ? ring.projection : .insufficientData,
                            color: color,
                            trackColor: color.opacity(0.15),
                            ringWidth: ringWidth,
                            size: ringSize
                        )

                        // Center percentage
                        Text("\(Int(ring.utilization))%")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .popover(isPresented: Binding(
                        get: { hoveredIndex == index },
                        set: { if !$0 { hoveredIndex = nil } }
                    ), arrowEdge: .bottom) {
                        RingTooltip(ring: ring)
                            .padding(4)
                    }
                    .onHover { isHovered in
                        DispatchQueue.main.async {
                            hoveredIndex = isHovered ? index : nil
                        }
                    }

                    Text(ring.label)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(ring.label) usage \(Int(ring.utilization)) percent")
                .accessibilityValue(ring.resetTime.map { "Resets in \($0)" } ?? "")
            }
        }
    }
}

// MARK: - Main Usage Rings View

struct UsageRingsView: View {
    let session: UsageBucket?
    let weekly: UsageBucket?
    let sonnet: UsageBucket?
    let showSonnet: Bool
    let showProjection: Bool
    let warningThreshold: Double
    let criticalThreshold: Double
    let sessionProjection: ProjectionResult
    let displayStyle: String

    private var rings: [RingData] {
        var result: [RingData] = []
        var index = 0

        if let session {
            result.append(RingData(
                label: "Session (5h)",
                utilization: session.utilization,
                resetTime: session.timeUntilReset,
                resetDate: session.resetsAtDate,
                projection: sessionProjection,
                ringIndex: index
            ))
            index += 1
        }

        if let weekly {
            result.append(RingData(
                label: "Weekly (7 days)",
                utilization: weekly.utilization,
                resetTime: weekly.timeUntilReset,
                resetDate: weekly.resetsAtDate,
                projection: .insufficientData,
                ringIndex: index
            ))
            index += 1
        }

        if showSonnet, let sonnet {
            result.append(RingData(
                label: "Sonnet (Weekly)",
                utilization: sonnet.utilization,
                resetTime: sonnet.timeUntilReset,
                resetDate: sonnet.resetsAtDate,
                projection: .insufficientData,
                ringIndex: index
            ))
        }

        return result
    }

    var body: some View {
        if rings.isEmpty {
            Text("No data available")
                .foregroundColor(.secondary)
                .font(.caption)
        } else if displayStyle == "rings_separate" {
            SeparateRingsView(
                rings: rings,
                warningThreshold: warningThreshold,
                criticalThreshold: criticalThreshold,
                showProjection: showProjection
            )
            .frame(maxWidth: .infinity)
        } else {
            ConcentricRingsView(
                rings: rings,
                warningThreshold: warningThreshold,
                criticalThreshold: criticalThreshold,
                showProjection: showProjection
            )
            .frame(maxWidth: .infinity)
        }
    }
}
