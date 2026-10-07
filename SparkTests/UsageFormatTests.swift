import XCTest
@testable import Spark

final class UsageFormatTests: XCTestCase {
    func testCostBelowHundredKeepsCents() {
        XCTAssertEqual(UsageFormat.cost(84.2), NumberParts(number: "84.20", unit: "$"))
        XCTAssertEqual(UsageFormat.cost(0), NumberParts(number: "0.00", unit: "$"))
    }

    func testCostFromHundredIsWholeDollars() {
        XCTAssertEqual(UsageFormat.cost(116.65), NumberParts(number: "117", unit: "$"))
        XCTAssertEqual(UsageFormat.cost(7015.2), NumberParts(number: "7,015", unit: "$"))
    }

    func testCostFromTenThousandIsCompact() {
        XCTAssertEqual(UsageFormat.cost(48_210), NumberParts(number: "48.2", unit: "K$"))
        XCTAssertEqual(UsageFormat.cost(2_400_000), NumberParts(number: "2.4", unit: "M$"))
    }

    func testCostRoundingAcrossATierBoundaryMovesToTheNextTier() {
        XCTAssertEqual(UsageFormat.cost(99.996), NumberParts(number: "100", unit: "$"))
        XCTAssertEqual(UsageFormat.cost(9_999.6), NumberParts(number: "10.0", unit: "K$"))
    }

    func testCostNeverExceedsFiveCharacters() {
        for dollars in [0.004, 9.99, 99.994, 99.995, 999.5, 9_999.4, 9_999.5, 99_949, 99_950, 999_949, 1e9] {
            XCTAssertLessThanOrEqual(UsageFormat.cost(dollars).number.count, 5, "\(dollars)")
        }
    }

    func testCostOfInvalidInputIsZero() {
        XCTAssertEqual(UsageFormat.cost(-3), NumberParts(number: "0.00", unit: "$"))
        XCTAssertEqual(UsageFormat.cost(.nan), NumberParts(number: "0.00", unit: "$"))
    }

    func testTokensAreCompact() {
        XCTAssertEqual(UsageFormat.tokens(812), NumberParts(number: "812", unit: ""))
        XCTAssertEqual(UsageFormat.tokens(536_900), NumberParts(number: "536.9", unit: "K"))
        XCTAssertEqual(UsageFormat.tokens(6_800_000), NumberParts(number: "6.8", unit: "M"))
        XCTAssertEqual(UsageFormat.tokens(2_700_000_000), NumberParts(number: "2.7", unit: "B"))
    }

    func testTokensRoundingUpPromoteToTheNextUnit() {
        XCTAssertEqual(UsageFormat.tokens(999_950), NumberParts(number: "1.0", unit: "M"))
        XCTAssertEqual(UsageFormat.tokens(999), NumberParts(number: "999", unit: ""))
        XCTAssertEqual(UsageFormat.tokens(-5), NumberParts(number: "0", unit: ""))
    }

    func testPercentFollowsTheLocale() {
        XCTAssertEqual(UsageFormat.percent(45, locale: Locale(identifier: "en_US")), "45%")
        let german = UsageFormat.percent(45, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(german, "45 %")
        XCTAssertEqual(UsageFormat.percent(45.6, locale: Locale(identifier: "en_US")), "46%")
        XCTAssertEqual(UsageFormat.percent(.nan, locale: Locale(identifier: "en_US")), "0%")
    }
}
