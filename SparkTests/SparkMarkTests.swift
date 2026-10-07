import XCTest
@testable import Spark

final class SparkMarkTests: XCTestCase {
    func testRestingMarkHasNineFullAndThreeFaintDots() {
        let opacities = SparkMarkLayout.opacities(step: 0)
        XCTAssertEqual(opacities.count, 12)
        XCTAssertEqual(opacities.filter { $0 == 1 }.count, 9)
        XCTAssertEqual(Array(opacities.suffix(3)), Array(repeating: SparkMarkLayout.faintOpacity, count: 3))
    }

    func testLoadingStepMovesTheGapClockwise() {
        let opacities = SparkMarkLayout.opacities(step: 1)
        XCTAssertEqual(opacities[9], 1)
        XCTAssertEqual(opacities[0], SparkMarkLayout.faintOpacity)
        XCTAssertEqual(opacities.filter { $0 == 1 }.count, 9)
    }

    func testStepWrapsAround() {
        XCTAssertEqual(SparkMarkLayout.opacities(step: 12), SparkMarkLayout.opacities(step: 0))
        XCTAssertEqual(SparkMarkLayout.opacities(step: -1), SparkMarkLayout.opacities(step: 11))
    }
}
