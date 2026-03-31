import XCTest
@testable import Spark

final class AccountTierTests: XCTestCase {

    // MARK: - AccountTier from ClaudeCredentials

    func testProTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "pro", rateLimitTier: "default_claude_pro")
        XCTAssertEqual(creds.accountTier.displayName, "Pro")
    }

    func testMaxTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "max", rateLimitTier: "default_claude_max")
        XCTAssertEqual(creds.accountTier.displayName, "Max")
    }

    func testMax5xTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
        XCTAssertEqual(creds.accountTier.displayName, "Max 5x")
    }

    func testMax20xTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
        XCTAssertEqual(creds.accountTier.displayName, "Max 20x")
    }

    func testTeamTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "team", rateLimitTier: "default_claude_team")
        XCTAssertEqual(creds.accountTier.displayName, "Team")
    }

    func testTeam5xTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "team", rateLimitTier: "default_claude_max_5x")
        XCTAssertEqual(creds.accountTier.displayName, "Team 5x")
    }

    func testTeam20xTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "team", rateLimitTier: "default_claude_max_20x")
        XCTAssertEqual(creds.accountTier.displayName, "Team 20x")
    }

    func testFreeTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: nil, rateLimitTier: "default_claude_ai")
        XCTAssertEqual(creds.accountTier.displayName, "Free")
    }

    func testFreeTierNoFields() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: nil, rateLimitTier: nil)
        XCTAssertEqual(creds.accountTier.displayName, "Free")
    }

    // MARK: - AccountTier Equality

    func testAccountTierEquality() {
        XCTAssertEqual(AccountTier.free, AccountTier(plan: "Free", multiplier: nil))
        XCTAssertNotEqual(AccountTier(plan: "Max", multiplier: "5x"), AccountTier(plan: "Max", multiplier: nil))
    }
}
