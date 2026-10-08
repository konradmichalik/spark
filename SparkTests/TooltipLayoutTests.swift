import XCTest
@testable import Spark

final class TooltipLayoutTests: XCTestCase {
    private let container = CGSize(width: 300, height: 400)
    private let size = CGSize(width: 100, height: 30)

    func testCentersBelowTheAnchorByDefault() {
        let anchor = CGRect(x: 100, y: 50, width: 40, height: 20)

        let origin = TooltipLayout.origin(anchor: anchor, size: size, container: container)

        XCTAssertEqual(origin.x, 70, accuracy: 0.001)
        XCTAssertEqual(origin.y, anchor.maxY + TooltipLayout.gap, accuracy: 0.001)
    }

    func testClampsToTheLeftEdge() {
        let anchor = CGRect(x: 0, y: 50, width: 20, height: 20)

        let origin = TooltipLayout.origin(anchor: anchor, size: size, container: container)

        XCTAssertEqual(origin.x, TooltipLayout.inset, accuracy: 0.001)
    }

    func testClampsToTheRightEdge() {
        let anchor = CGRect(x: 280, y: 50, width: 20, height: 20)

        let origin = TooltipLayout.origin(anchor: anchor, size: size, container: container)

        XCTAssertEqual(origin.x, container.width - size.width - TooltipLayout.inset, accuracy: 0.001)
    }

    func testFlipsAboveWhenThereIsNoRoomBelow() {
        let anchor = CGRect(x: 100, y: 370, width: 40, height: 20)

        let origin = TooltipLayout.origin(anchor: anchor, size: size, container: container)

        XCTAssertEqual(origin.y, anchor.minY - TooltipLayout.gap - size.height, accuracy: 0.001)
    }

    func testStaysInsideWhenThereIsNoRoomAboveEither() {
        let tallAnchor = CGRect(x: 100, y: 5, width: 40, height: 390)
        let container = CGSize(width: 300, height: 60)

        let origin = TooltipLayout.origin(anchor: tallAnchor, size: size, container: container)

        XCTAssertGreaterThanOrEqual(origin.y, TooltipLayout.inset)
        XCTAssertLessThanOrEqual(origin.y + size.height, container.height - TooltipLayout.inset + 0.001)
    }

    func testTooltipWiderThanTheContainerPinsToTheLeftInset() {
        let anchor = CGRect(x: 100, y: 50, width: 40, height: 20)
        let wide = CGSize(width: 400, height: 30)

        let origin = TooltipLayout.origin(anchor: anchor, size: wide, container: container)

        XCTAssertEqual(origin.x, TooltipLayout.inset, accuracy: 0.001)
    }

    func testShortTextKeepsItsOwnWidth() {
        XCTAssertEqual(TooltipLayout.textWidth(ideal: 64.2), 65, accuracy: 0.001)
    }

    func testLongTextWrapsAtTheMaximumWidth() {
        XCTAssertEqual(TooltipLayout.textWidth(ideal: 480), TooltipLayout.maxWidth, accuracy: 0.001)
    }

    func testUnmeasuredTextHasNoWidth() {
        XCTAssertEqual(TooltipLayout.textWidth(ideal: -3), 0, accuracy: 0.001)
        XCTAssertEqual(TooltipLayout.textWidth(ideal: .infinity), TooltipLayout.maxWidth, accuracy: 0.001)
    }
}
