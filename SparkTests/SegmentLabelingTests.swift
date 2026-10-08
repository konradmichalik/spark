import XCTest
@testable import Spark

final class SegmentLabelingTests: XCTestCase {

    /// Pins the ranges Volume mode offers, so a regression cannot silently change them.
    func testVolumeModeOffersOnlyDayGranularityRanges() {
        XCTAssertEqual(GraphTimeRange.dayGranularityCases, [.sevenDays, .thirtyDays])
    }
}
