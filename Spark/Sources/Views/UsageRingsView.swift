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
    @State private var isHovered = false
    @State private var hoverInProjectionZone = false

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
            .overlay(alignment: .top) {
                if isHovered {
                    RingTooltip(ring: ring, showProjection: hoverInProjectionZone)
                        .fixedSize()
                        .offset(y: -8)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let onRing = hitTestRing(location)
                    isHovered = onRing.hit
                    hoverInProjectionZone = onRing.inProjectionZone
                case .ended:
                    isHovered = false
                    hoverInProjectionZone = false
                }
            }

            HStack(spacing: 4) {
                Text(ring.label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                if ring.resetTime != nil {
                    Button {
                        showResetPopover.toggle()
                    } label: {
                        TablerIconView(.history, size: 9)
                            .frame(width: 14, height: 14)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showResetPopover, arrowEdge: .bottom) {
                        VStack(spacing: 6) {
                            HStack(spacing: 4) {
                                TablerIconView(.history, size: 11)
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

    private struct RingHit {
        let hit: Bool
        let inProjectionZone: Bool
    }

    private func hitTestRing(_ point: CGPoint) -> RingHit {
        let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        let radius = ringSize / 2
        let innerEdge = radius - ringWidth / 2
        let outerEdge = radius + ringWidth / 2

        guard distance >= innerEdge && distance <= outerEdge else {
            return RingHit(hit: false, inProjectionZone: false)
        }

        let fillFraction = min(ring.utilization, 100) / 100
        let projectedFraction: Double = {
            switch ring.projection {
            case .limitReached: return 1.0
            case .safe(let projected): return min(projected, 100) / 100
            case .insufficientData: return 0
            }
        }()

        let angle = atan2(dx, -dy)
        let normalizedAngle = angle < 0 ? angle + 2 * .pi : angle
        let fraction = normalizedAngle / (2 * .pi)

        let inProjection = showProjection
            && projectedFraction > fillFraction
            && fraction > fillFraction
            && fraction <= projectedFraction

        return RingHit(hit: true, inProjectionZone: inProjection)
    }
}

// MARK: - Main Usage Rings View

struct UsageRingsView: View {
    let session: UsageBucket?
    let weekly: UsageBucket?
    let sonnet: UsageBucket?
    let opus: UsageBucket?
    let fable: UsageBucket?
    let showSonnet: Bool
    let showOpus: Bool
    let showFable: Bool
    let showProjection: Bool
    let warningThreshold: Double
    let criticalThreshold: Double
    let sessionProjection: ProjectionResult
    let displayStyle: String

    private var rings: [RingData] {
        var result: [RingData] = []
        var index = 0

        func append(label: String, bucket: UsageBucket?, projection: ProjectionResult = .insufficientData) {
            guard let bucket else { return }
            result.append(RingData(
                label: label,
                utilization: bucket.utilization,
                resetTime: bucket.timeUntilReset,
                resetDate: bucket.resetsAtDate,
                projection: projection,
                ringIndex: index
            ))
            index += 1
        }

        append(label: "Session (5h)", bucket: session, projection: sessionProjection)
        append(label: "Weekly (7 days)", bucket: weekly)

        // Unlike `session`/`weekly` above, `sonnet`/`opus`/`fable` are only appended when their
        // toggle is on — falling back to a zeroed bucket here would draw a ring that always reads
        // as 0% for any account whose plan doesn't report that model's weekly quota at all, which
        // looks like real usage data rather than the absence of a quota to measure against.
        if showSonnet { append(label: "Sonnet (Weekly)", bucket: sonnet) }
        if showOpus { append(label: "Opus (Weekly)", bucket: opus) }
        if showFable { append(label: "Fable (Weekly)", bucket: fable) }

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
