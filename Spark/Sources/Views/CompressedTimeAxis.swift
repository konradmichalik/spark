import CoreGraphics
import Foundation

/// Maps timestamps to x positions on a non-linear axis: stretches of time without
/// samples (Mac asleep, app quit) collapse into narrow fixed-width bands instead of
/// eating up the graph width.
///
/// Gaps at the window edges are trimmed rather than banded, so the axis always spans
/// exactly the first to the last available sample.
///
/// `timestamps` must be in ascending order (history is appended chronologically).
struct CompressedTimeAxis {
    struct Segment {
        let start: Date
        let end: Date
        let xStart: CGFloat
        let xEnd: CGFloat
        /// Indices of the samples this segment was built from — the single source of
        /// truth for where a line has to break.
        let sampleRange: Range<Int>
    }

    struct GapBand: Equatable {
        let duration: TimeInterval
        let xStart: CGFloat
        let xEnd: CGFloat
    }

    /// Width a single gap band gets when there is room for it.
    static let maxGapWidth: CGFloat = 8
    /// Upper bound for the share of the axis all gap bands together may occupy.
    static let maxGapShare: CGFloat = 0.15

    let segments: [Segment]
    let gaps: [GapBand]

    init(timestamps: [Date], width: CGFloat, gapThreshold: TimeInterval) {
        guard width > 0, timestamps.count >= 2 else {
            self.segments = []
            self.gaps = []
            return
        }

        let (ranges, gapDurations) = Self.split(timestamps, gapThreshold: gapThreshold)
        let spans = ranges.map {
            (range: $0, start: timestamps[$0.lowerBound], end: timestamps[$0.upperBound - 1])
        }
        let gapWidth = Self.gapWidth(gapCount: gapDurations.count, width: width)
        let activeWidth = width - gapWidth * CGFloat(gapDurations.count)
        let totalActive = spans.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        var segments: [Segment] = []
        var gaps: [GapBand] = []
        var x: CGFloat = 0

        for (index, span) in spans.enumerated() {
            let share = totalActive > 0
                ? span.end.timeIntervalSince(span.start) / totalActive
                : 1 / Double(spans.count)
            let segmentWidth = activeWidth * CGFloat(share)
            segments.append(
                Segment(start: span.start, end: span.end, xStart: x, xEnd: x + segmentWidth, sampleRange: span.range)
            )
            x += segmentWidth

            if index < gapDurations.count {
                gaps.append(GapBand(duration: gapDurations[index], xStart: x, xEnd: x + gapWidth))
                x += gapWidth
            }
        }

        self.segments = segments
        self.gaps = gaps
    }

    // MARK: - Mapping

    /// X position for a timestamp. Dates inside a gap snap to the band's trailing edge.
    func x(for date: Date) -> CGFloat {
        guard let first = segments.first, let last = segments.last else { return 0 }
        if date <= first.start { return first.xStart }
        if date >= last.end { return last.xEnd }

        for segment in segments where date <= segment.end {
            if date <= segment.start { return segment.xStart }
            let duration = segment.end.timeIntervalSince(segment.start)
            guard duration > 0 else { return segment.xStart }
            let fraction = date.timeIntervalSince(segment.start) / duration
            return segment.xStart + (segment.xEnd - segment.xStart) * CGFloat(fraction)
        }
        return last.xEnd
    }

    /// Timestamp shown at an x position. Positions inside a gap band report the last
    /// sample before the gap.
    func date(atX x: CGFloat) -> Date? {
        guard let first = segments.first, let last = segments.last else { return nil }
        if x <= first.xStart { return first.start }
        if x >= last.xEnd { return last.end }

        for (index, segment) in segments.enumerated() {
            if x <= segment.xEnd {
                let segmentWidth = segment.xEnd - segment.xStart
                guard segmentWidth > 0 else { return segment.start }
                let fraction = Double((x - segment.xStart) / segmentWidth)
                return segment.start.addingTimeInterval(segment.end.timeIntervalSince(segment.start) * fraction)
            }
            if index < gaps.count, x < gaps[index].xEnd { return segment.end }
        }
        return last.end
    }

    func gap(atX x: CGFloat) -> GapBand? {
        gaps.first { x >= $0.xStart && x <= $0.xEnd }
    }

    // MARK: - Layout

    private static func split(
        _ timestamps: [Date],
        gapThreshold: TimeInterval
    ) -> (ranges: [Range<Int>], gapDurations: [TimeInterval]) {
        var ranges: [Range<Int>] = []
        var gapDurations: [TimeInterval] = []
        var spanStart = 0

        for index in 1..<timestamps.count {
            let delta = timestamps[index].timeIntervalSince(timestamps[index - 1])
            if delta > gapThreshold {
                ranges.append(spanStart..<index)
                gapDurations.append(delta)
                spanStart = index
            }
        }
        ranges.append(spanStart..<timestamps.count)
        return (ranges, gapDurations)
    }

    private static func gapWidth(gapCount: Int, width: CGFloat) -> CGFloat {
        guard gapCount > 0 else { return 0 }
        return min(maxGapWidth, maxGapShare * width / CGFloat(gapCount))
    }
}
