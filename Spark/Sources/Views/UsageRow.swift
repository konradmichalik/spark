import AppKit
import SwiftUI

// MARK: - Local-Only Usage Row

/// Shown instead of `UsageRow` when the API doesn't report a Sonnet/Opus-specific weekly quota
/// for this account's plan — a bare label plus the local token count, with no percentage or bar
/// implying a quota that doesn't exist.
struct LocalOnlyUsageRow: View {
    let label: String
    let localTokens: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            Text("· \(localTokens) local")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Usage Row

struct UsageRow: View {
    let label: String
    let utilization: Double
    let resetTime: String?
    let resetDate: Date?
    let warningThreshold: Double
    let criticalThreshold: Double
    var projection: ProjectionResult = .insufficientData
    /// Local token attribution for this bucket's model family, shown alongside the label — see
    /// `MenuBarView.formattedLocalTokens`. `nil` renders nothing, adding no vertical height.
    var localTokens: String?
    /// Pace for this bucket's window — see `Pace.calculate`. `nil` omits the marker entirely.
    var pace: Pace.Result?
    /// Local burn rate, shown alongside the label — see `BurnRate`. `nil` renders nothing.
    var burnRate: BurnRate?

    private static func burnRateDetail(_ burnRate: BurnRate) -> String {
        "\(formatTokenCount(burnRate.tokensPerMinute)) fresh tokens per minute across all sessions, "
            + "averaged over the last \(Int(BurnRate.window / 60)) minutes. Cache reads are not counted."
    }

    private var paceDescription: String? {
        guard let pace else { return nil }
        let percent = Int((pace.ratio * 100).rounded())
        let exhausts = pace.ratio > 1 ? "before" : "at or after"
        return "Pace: \(pace.tier.label) — \(percent)% of the on-track rate. At this rate, quota exhausts \(exhausts) reset."
    }

    private var color: Color {
        if utilization >= criticalThreshold { return .red }
        if utilization >= warningThreshold { return .orange }
        return .green
    }

    private var projectionTitle: String? {
        switch projection {
        case .limitReached(let seconds):
            return "Limit in ~\(formatDuration(seconds))"
        case .safe(let projected):
            return "~\(Int(projected))% at reset"
        case .insufficientData:
            return nil
        }
    }

    private var projectionDetail: String? {
        switch projection {
        case .limitReached(let seconds):
            let rate = ratePerHour
            return "At the current rate of ~\(Int(rate))%/h, the session limit will be reached in ~\(formatDuration(seconds))."
        case .safe(let projected):
            let rate = ratePerHour
            return "At the current rate of ~\(Int(rate))%/h, usage will be ~\(Int(projected))% when the session resets."
        case .insufficientData:
            return nil
        }
    }

    private var ratePerHour: Double {
        switch projection {
        case .limitReached(let seconds):
            guard seconds > 0 else { return 0 }
            return (100 - utilization) / (seconds / 3600)
        case .safe(let projected):
            guard resetTime != nil else { return 0 }
            // Rough estimate: parse hours from reset string isn't clean, use projected delta
            let delta = projected - utilization
            return delta > 0 ? delta : 0
        case .insufficientData:
            return 0
        }
    }

    private var projectionIconColor: Color {
        switch projection {
        case .limitReached: return .red
        case .safe: return .secondary
        case .insufficientData: return .clear
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        seconds.shortDuration
    }

    private var insightAccessibilityLabel: String {
        var parts: [String] = []
        if let burnRate {
            parts.append("Burn rate \(burnRate.tier.label), \(formatTokenCount(burnRate.tokensPerMinute)) tokens per minute")
        }
        if projectionTitle != nil { parts.append("Usage projection") }
        return parts.joined(separator: ", ")
    }

    private var insightTooltipTitle: String? {
        projectionTitle ?? burnRate.map { "Burn rate: \($0.tier.label)" }
    }

    private var insightTooltipText: String? {
        var paragraphs: [String] = []
        if let projectionDetail { paragraphs.append(projectionDetail) }
        if let burnRate {
            let detail = Self.burnRateDetail(burnRate)
            paragraphs.append(projectionTitle == nil ? detail : "Burn rate: \(burnRate.tier.label). \(detail)")
        }
        return paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n")
    }

    /// Burn rate and projection share one hover target and one tooltip.
    @ViewBuilder
    private var insight: some View {
        if projectionTitle != nil || burnRate != nil {
            HStack(spacing: 4) {
                // Neutral in the row: red there belongs to the projection, which says whether
                // the session limit is actually at risk. The tier is named in the tooltip.
                if let burnRate {
                    Text("· \(formatTokenCount(burnRate.tokensPerMinute))/min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if projectionTitle != nil {
                    TablerIconView(.chartLine, size: 10, color: projectionIconColor)
                }
            }
            .contentShape(Rectangle())
            .tooltip(insightTooltipText, title: insightTooltipTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(insightAccessibilityLabel)
            .accessibilityHint(insightTooltipText ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)

                if let localTokens {
                    Text("· \(localTokens) local")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                insight

                Spacer()
                if let resetTime {
                    HStack(spacing: 4) {
                        TablerIconView(.history, size: 10, color: .secondary)
                        Text("\(resetTime) left")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .tooltip(resetDate?.resetDescription, title: "Reset in \(resetTime)")
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(resetDate?.resetDescription ?? "")
                }
            }

            HStack(spacing: 8) {
                ProjectedProgressBar(
                    utilization: utilization,
                    color: color,
                    projection: projection,
                    pace: pace
                )
                .frame(height: 6)
                .tooltip(paceDescription)
                .accessibilityHint(paceDescription ?? "")

                Text("\(Int(utilization))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(utilization >= warningThreshold ? color : .primary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Projected Progress Bar

struct ProjectedProgressBar: View {
    let utilization: Double
    let color: Color
    let projection: ProjectionResult
    /// Pace for this bucket's window, drawn as a colored marker on the bar. Fill left of the
    /// marker reads as under budget, fill right of it as over; the marker's color reflects
    /// `Pace.Tier`, from comfortably under budget to badly overspending. `nil` when pace can't be
    /// computed (see `Pace.calculate`), which simply omits the marker rather than drawing a
    /// misleading one.
    var pace: Pace.Result?

    private var projectedWidth: Double {
        switch projection {
        case .limitReached:
            return 100
        case .safe(let projected):
            return min(projected, 100)
        case .insufficientData:
            return 0
        }
    }

    private var projectionColor: Color {
        switch projection {
        case .limitReached:
            return .red
        case .safe:
            return .primary
        case .insufficientData:
            return .clear
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Opaque backing to prevent vibrancy bleed-through
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)

                // Projection background
                if projectedWidth > utilization {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(projectionColor.opacity(0.15))
                        .frame(width: geometry.size.width * min(projectedWidth, 100) / 100)
                }

                // Current utilization
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * min(utilization, 100) / 100)

                // Pace marker: where "on budget" would sit right now, colored by Pace.Tier.
                if let pace {
                    Rectangle()
                        .fill(Theme.paceColor(for: pace.tier))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * min(max(pace.elapsedFraction, 0), 1))
                }
            }
        }
    }
}
