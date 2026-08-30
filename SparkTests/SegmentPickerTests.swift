import XCTest
@testable import Spark

final class SegmentPickerTests: XCTestCase {

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

    func testVolumeModeOffersOnlyDayGranularityRanges() {
        XCTAssertEqual(GraphTimeRange.dayGranularityCases, [.sevenDays, .thirtyDays])
    }
}
