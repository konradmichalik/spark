import XCTest
@testable import Spark

final class SegmentLabelingTests: XCTestCase {

    /// Doesn't exercise `SegmentPicker` or `SegmentLabeled` directly: it pins the option list
    /// Volume mode hands to the picker. Task 9 wires `availableTimeRanges` straight into
    /// `SegmentPicker`'s `options`, so a regression here would silently change what the picker
    /// offers in Volume mode.
    func testVolumeModeOffersOnlyDayGranularityRanges() {
        XCTAssertEqual(GraphTimeRange.dayGranularityCases, [.sevenDays, .thirtyDays])
    }
}
