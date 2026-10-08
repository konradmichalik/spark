import XCTest
@testable import Spark

final class ExtraUsageTests: XCTestCase {
    /// Live API sends amounts in minor units (cents) plus `decimal_places`. 3988 cents
    /// with decimal_places 2 must resolve to 39.88, not 3988 — regression for the
    /// "€3988 extra usage" display bug.
    func testExtraUsageHonorsDecimalPlaces() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": 4000, "used_credits": 3988.0,
            "utilization": 99.7, "currency": "EUR", "decimal_places": 2,
            "disabled_reason": null
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertEqual(extra.decimalPlaces, 2)
        XCTAssertTrue(extra.hasSpend)
        XCTAssertEqual(extra.spendAmount ?? 0, 39.88, accuracy: 0.0001)
    }

    /// With a monthly limit present, the line combines spend and cap ("39,88 of 40,00 €").
    func testExtraUsageFormatsSpendWithLimit() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": 4000, "used_credits": 3988.0,
            "utilization": 99.7, "currency": "EUR", "decimal_places": 2,
            "disabled_reason": null
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertEqual(extra.limitAmount ?? 0, 40.00, accuracy: 0.0001)
        let accessible = try XCTUnwrap(extra.spendWithLimit)
        XCTAssertTrue(accessible.contains(" of "), "expected 'of' phrasing, got \(accessible)")
        XCTAssertFalse(accessible.contains("/"))
    }

    /// Without a monthly limit the spend line falls back to the bare spent amount.
    func testExtraUsageWithoutLimitFallsBackToSpend() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": null, "used_credits": 240,
            "utilization": null, "currency": "EUR", "decimal_places": 2,
            "disabled_reason": null
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertNil(extra.limitAmount)
        XCTAssertEqual(extra.spendWithLimit, extra.formattedSpend)
        XCTAssertFalse(extra.spendWithLimit?.contains(" of ") ?? true)
    }

    /// Absent `decimal_places` (legacy response) means the value is already in major
    /// units — no scaling applied.
    func testExtraUsageWithoutDecimalPlacesIsUnscaled() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": null, "used_credits": 2.4,
            "utilization": null, "currency": "EUR", "disabled_reason": null
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertNil(extra.decimalPlaces)
        XCTAssertEqual(extra.spendAmount ?? 0, 2.4, accuracy: 0.0001)
    }

    /// `decimal_places` beyond the currency's own default (2) must survive formatting —
    /// a two-decimal currency formatter would otherwise round 3.988 to 3.99.
    func testExtraUsageFormatsBeyondCurrencyDefaultDecimalPlaces() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": 4000, "used_credits": 3988.0,
            "utilization": 99.7, "currency": "EUR", "decimal_places": 3, "disabled_reason": null
        }
        """.utf8)
        let combined = try XCTUnwrap(JSONDecoder().decode(ExtraUsage.self, from: json).spendWithLimit)
        XCTAssertTrue(combined.contains("988") && combined.contains("000"))
    }

    func testExtraUsageNoSpend() throws {
        let json = Data("""
        {
            "is_enabled": true, "monthly_limit": null, "used_credits": 0,
            "utilization": null, "currency": "EUR", "disabled_reason": null
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertFalse(extra.hasSpend)
        XCTAssertNil(extra.formattedSpend)
    }

    func testExtraUsageDisabledHasNoSpend() throws {
        let json = Data("""
        {
            "is_enabled": false, "monthly_limit": null, "used_credits": 5.0,
            "utilization": null, "currency": "USD", "disabled_reason": "billing"
        }
        """.utf8)

        let extra = try JSONDecoder().decode(ExtraUsage.self, from: json)
        XCTAssertFalse(extra.hasSpend)
    }
}
