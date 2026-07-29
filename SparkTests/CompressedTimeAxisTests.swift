import XCTest
@testable import Spark

final class CompressedTimeAxisTests: XCTestCase {

    /// Typed units: literal-only arithmetic such as `8 * hour` inside a `[TimeInterval]`
    /// literal is resolved as `Int` by older Swift type checkers and fails to compile.
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600

    private let width: CGFloat = 300
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var threshold: TimeInterval { 45 * minute }

    private func axis(_ offsets: [TimeInterval], width: CGFloat? = nil) -> CompressedTimeAxis {
        CompressedTimeAxis(
            timestamps: offsets.map { base.addingTimeInterval($0) },
            width: width ?? self.width,
            gapThreshold: threshold
        )
    }

    // MARK: - Continuous data

    func testContinuousDataMapsLinearly() {
        let offsets = stride(from: 0.0, through: 3600.0, by: 300.0).map { $0 }
        let sut = axis(offsets)

        XCTAssertEqual(sut.gaps.count, 0)
        XCTAssertEqual(sut.segments.count, 1)
        XCTAssertEqual(sut.x(for: base), 0, accuracy: 0.01)
        XCTAssertEqual(sut.x(for: base.addingTimeInterval(3600)), width, accuracy: 0.01)
        XCTAssertEqual(sut.x(for: base.addingTimeInterval(1800)), width / 2, accuracy: 0.01)
    }

    func testXPositionsIncreaseMonotonically() {
        let sut = axis([0, 300, 8 * hour, 8 * hour + 300, 20 * hour])
        var previous: CGFloat = -1
        for offset in stride(from: 0.0, through: 20 * hour, by: 600) {
            let x = sut.x(for: base.addingTimeInterval(offset))
            XCTAssertGreaterThanOrEqual(x, previous)
            previous = x
        }
    }

    // MARK: - Gap compression

    func testSingleGapCollapsesToBand() {
        let sut = axis([0, 300, 8 * hour, 8 * hour + 300])

        XCTAssertEqual(sut.segments.count, 2)
        XCTAssertEqual(sut.gaps.count, 1)

        let band = sut.gaps[0]
        XCTAssertEqual(band.xEnd - band.xStart, CompressedTimeAxis.maxGapWidth, accuracy: 0.01)
        XCTAssertEqual(band.duration, 8 * hour - 300, accuracy: 0.01)

        // Both spans are 300s long, so they split the remaining width evenly.
        XCTAssertEqual(sut.segments[0].xEnd, 146, accuracy: 0.01)
        XCTAssertEqual(band.xStart, 146, accuracy: 0.01)
        XCTAssertEqual(sut.segments[1].xStart, 154, accuracy: 0.01)
        XCTAssertEqual(sut.segments[1].xEnd, width, accuracy: 0.01)
    }

    func testLongSpanGetsMoreWidthThanShortSpan() {
        // 60min of continuous samples, then a gap, then 20min of samples.
        let firstSpan = stride(from: 0.0, through: 3600.0, by: 300.0).map { $0 }
        let secondSpan = stride(from: 12 * hour, through: 12 * hour + 1200, by: 300.0).map { $0 }
        let sut = axis(firstSpan + secondSpan)
        let activeWidth = width - CompressedTimeAxis.maxGapWidth

        XCTAssertEqual(sut.gaps.count, 1)

        XCTAssertEqual(sut.segments[0].xEnd - sut.segments[0].xStart, activeWidth * 0.75, accuracy: 0.01)
        XCTAssertEqual(sut.segments[1].xEnd - sut.segments[1].xStart, activeWidth * 0.25, accuracy: 0.01)
    }

    func testManyGapsStayWithinWidthBudget() {
        // 31 isolated pairs separated by long gaps -> 30 bands.
        var offsets: [TimeInterval] = []
        for index in 0..<31 {
            offsets.append(Double(index) * 24 * hour)
            offsets.append(Double(index) * 24 * hour + 300)
        }
        let sut = axis(offsets)

        XCTAssertEqual(sut.gaps.count, 30)
        let totalBandWidth = sut.gaps.reduce(0) { $0 + ($1.xEnd - $1.xStart) }
        XCTAssertLessThanOrEqual(totalBandWidth, CompressedTimeAxis.maxGapShare * width + 0.01)
        XCTAssertEqual(sut.segments.last?.xEnd ?? 0, width, accuracy: 0.01)
    }

    func testEdgeGapsAreTrimmed() {
        let sut = axis([0, 300, 600])

        // Anything before the first or after the last sample clamps to the axis bounds.
        XCTAssertEqual(sut.x(for: base.addingTimeInterval(-24 * hour)), 0, accuracy: 0.01)
        XCTAssertEqual(sut.x(for: base.addingTimeInterval(24 * hour)), width, accuracy: 0.01)
        XCTAssertEqual(sut.date(atX: 0), base)
        XCTAssertEqual(sut.date(atX: width), base.addingTimeInterval(600))
    }

    // MARK: - Reverse mapping

    func testDateAtXRoundTripsWithinASecond() {
        let sut = axis([0, 1800, 3600, 12 * hour, 12 * hour + 1800])

        let offsets: [TimeInterval] = [0, 900, 1800, 3600, 12 * hour, 12 * hour + 900]
        for offset in offsets {
            let date = base.addingTimeInterval(offset)
            let mapped = sut.date(atX: sut.x(for: date))
            XCTAssertEqual(mapped?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testDateInsideBandReportsLastSampleBeforeGap() {
        let sut = axis([0, 300, 8 * hour, 8 * hour + 300])
        let band = sut.gaps[0]
        let middle = (band.xStart + band.xEnd) / 2

        XCTAssertEqual(sut.date(atX: middle), base.addingTimeInterval(300))
    }

    func testGapLookupOnlyHitsInsideBand() {
        let sut = axis([0, 300, 8 * hour, 8 * hour + 300])

        XCTAssertNotNil(sut.gap(atX: 150))
        XCTAssertNil(sut.gap(atX: 100))
        XCTAssertNil(sut.gap(atX: 200))
    }

    // MARK: - Degenerate input

    func testEmptyInput() {
        let sut = axis([])

        XCTAssertTrue(sut.segments.isEmpty)
        XCTAssertTrue(sut.gaps.isEmpty)
        XCTAssertNil(sut.date(atX: 10))
        XCTAssertEqual(sut.x(for: base), 0)
    }

    func testZeroWidth() {
        let sut = axis([0, 300], width: 0)

        XCTAssertTrue(sut.segments.isEmpty)
        XCTAssertTrue(sut.gaps.isEmpty)
    }

    func testSingleSampleYieldsNoSegments() {
        // A lone sample draws nothing, so it gets no axis either.
        let sut = axis([0])

        XCTAssertTrue(sut.segments.isEmpty)
        XCTAssertNil(sut.date(atX: 10))
    }

    // MARK: - Sample ranges

    func testSampleRangesCoverAllSamplesInOrder() {
        let sut = axis([0, 300, 600, 8 * hour, 8 * hour + 300, 20 * hour])

        XCTAssertEqual(sut.segments.map(\.sampleRange), [0..<3, 3..<5, 5..<6])
    }

    func testSampleRangeBoundsMatchSegmentDates() {
        let offsets: [TimeInterval] = [0, 300, 8 * hour, 8 * hour + 300]
        let sut = axis(offsets)

        for segment in sut.segments {
            XCTAssertEqual(segment.start, base.addingTimeInterval(offsets[segment.sampleRange.lowerBound]))
            XCTAssertEqual(segment.end, base.addingTimeInterval(offsets[segment.sampleRange.upperBound - 1]))
        }
    }

    func testIsolatedSamplesShareWidthEvenly() {
        // Three lone samples, each separated by a gap -> no active duration at all.
        let sut = axis([0, 8 * hour, 16 * hour])
        let activeWidth = width - 2 * CompressedTimeAxis.maxGapWidth

        XCTAssertEqual(sut.segments.count, 3)
        XCTAssertEqual(sut.gaps.count, 2)
        for segment in sut.segments {
            XCTAssertEqual(segment.xEnd - segment.xStart, activeWidth / 3, accuracy: 0.01)
        }
        XCTAssertEqual(sut.segments.last?.xEnd ?? 0, width, accuracy: 0.01)
    }
}
