import SwiftUI

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
    @State private var hoverInProjectionZone = false

    var body: some View {
        VStack(spacing: 10) {
            // Rings
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                    let size = outerSize - CGFloat(index) * (ringWidth * 2 + ringGap)
                    let color = ringColorFor(ring)

                    RingArc(
                        utilization: ring.utilization,
                        projection: showProjection ? ring.projection : .insufficientData,
                        color: color,
                        trackColor: color.opacity(0.15),
                        ringWidth: ringWidth,
                        size: size
                    )
                    .allowsHitTesting(false)
                    .opacity(hoveredIndex == nil || hoveredIndex == index ? 1.0 : 0.6)
                    .accessibilityElement()
                    .accessibilityLabel("\(ring.label) usage \(Int(ring.utilization)) percent")
                    .accessibilityValue(ring.resetTime.map { "Resets in \($0)" } ?? "")
                }

                // Hover tooltip
                if let idx = hoveredIndex, idx < rings.count {
                    RingTooltip(ring: rings[idx], showProjection: hoverInProjectionZone)
                }
            }
            .frame(width: outerSize, height: outerSize)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let result = hitTest(location)
                    hoveredIndex = result.ringIndex
                    hoverInProjectionZone = result.inProjectionZone
                case .ended:
                    hoveredIndex = nil
                    hoverInProjectionZone = false
                }
            }

            // Legend
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                    RingLegendRow(
                        ring: ring,
                        color: ringColorFor(ring)
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ringColorFor(_ ring: RingData) -> Color {
        Theme.ringColor(
            utilization: ring.utilization,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            ringIndex: ring.ringIndex
        )
    }

    // MARK: - Hit Testing

    private struct HitResult {
        let ringIndex: Int?
        let inProjectionZone: Bool
    }

    private func hitTest(_ point: CGPoint) -> HitResult {
        let center = CGPoint(x: outerSize / 2, y: outerSize / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        // Check each ring from outermost to innermost
        for (index, ring) in rings.enumerated() {
            let ringRadius = (outerSize - CGFloat(index) * (ringWidth * 2 + ringGap)) / 2
            let innerEdge = ringRadius - ringWidth / 2
            let outerEdge = ringRadius + ringWidth / 2

            guard distance >= innerEdge && distance <= outerEdge else { continue }

            // Determine angle (0 = 12 o'clock, clockwise)
            let angle = atan2(dx, -dy)
            let normalizedAngle = angle < 0 ? angle + 2 * .pi : angle
            let fraction = normalizedAngle / (2 * .pi)

            let fillFraction = min(ring.utilization, 100) / 100
            let projectedFraction = projectedFractionFor(ring)

            // In projection zone: between fill end and projection end
            let inProjection = showProjection
                && projectedFraction > fillFraction
                && fraction > fillFraction
                && fraction <= projectedFraction

            return HitResult(ringIndex: index, inProjectionZone: inProjection)
        }

        return HitResult(ringIndex: nil, inProjectionZone: false)
    }

    private func projectedFractionFor(_ ring: RingData) -> Double {
        switch ring.projection {
        case .limitReached: return 1.0
        case .safe(let projected): return min(projected, 100) / 100
        case .insufficientData: return 0
        }
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

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                SeparateRingItem(
                    ring: ring,
                    color: ringColorFor(ring),
                    showProjection: showProjection,
                    ringWidth: ringWidth,
                    ringSize: ringSize
                )
            }
        }
    }

    private func ringColorFor(_ ring: RingData) -> Color {
        Theme.ringColor(
            utilization: ring.utilization,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold,
            ringIndex: ring.ringIndex
        )
    }
}

private struct SeparateRingItem: View {
    let ring: RingData
    let color: Color
    let showProjection: Bool
    let ringWidth: CGFloat
    let ringSize: CGFloat
    @State private var showResetPopover = false

    var body: some View {
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

                Text("\(Int(ring.utilization))%")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.medium)
            }

            HStack(spacing: 4) {
                Text(ring.label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                if ring.resetTime != nil {
                    Button {
                        showResetPopover.toggle()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showResetPopover, arrowEdge: .bottom) {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text("Reset in \(ring.resetTime ?? "")")
                                    .fontWeight(.medium)
                            }
                            .font(.caption)

                            if let resetDate = ring.resetDate {
                                Text(
                                    resetDate,
                                    format: .dateTime.weekday(.wide).day().month(.wide).hour().minute()
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(width: 220)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ring.label) usage \(Int(ring.utilization)) percent")
        .accessibilityValue(ring.resetTime.map { "Resets in \($0)" } ?? "")
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
