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
    let showProjection: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ring.label.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.paper.opacity(0.65))
            Text(UsageFormat.percent(ring.utilization))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            if showProjection, let projectionText {
                Text(projectionText)
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .tooltipChrome()
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

// MARK: - Ring Legend Row

struct RingLegendRow: View {
    let ring: RingData
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(ring.label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            if let resetTime = ring.resetTime {
                HStack(spacing: 4) {
                    TablerIconView(.history, size: 11)
                        .frame(width: 18, height: 18)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                    Text(resetTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .tooltip(ring.resetDate?.resetDescription, title: "Reset in \(resetTime)")
                .accessibilityElement(children: .combine)
                .accessibilityHint(ring.resetDate?.resetDescription ?? "")
            }
        }
    }
}
