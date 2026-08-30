import XCTest
@testable import Spark

final class SegmentLabelingTests: XCTestCase {

    func testStatsPeriodLabelsMatchRawValues() {
        for period in StatsPeriod.allCases {
            XCTAssertEqual(period.segmentLabel, period.rawValue)
        }
    }

    func testGraphTimeRangeLabelsMatchRawValues() {
        for range in GraphTimeRange.allCases {
            XCTAssertEqual(range.segmentLabel, range.rawValue)
        }
    }

    func testGraphModeUsesWordsNotSymbols() {
        XCTAssertEqual(GraphMode.limits.segmentLabel, "Limits")
        XCTAssertEqual(GraphMode.volume.segmentLabel, "Volume")
    }

    /// Doesn't exercise `SegmentPicker` or `SegmentLabeled` directly: it pins the option list
    /// Volume mode hands to the picker. Task 9 wires `availableTimeRanges` straight into
    /// `SegmentPicker`'s `options`, so a regression here would silently change what the picker
    /// offers in Volume mode.
    func testVolumeModeOffersOnlyDayGranularityRanges() {
        XCTAssertEqual(GraphTimeRange.dayGranularityCases, [.sevenDays, .thirtyDays])
    }
}
