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

    func testMax5xTierReadsAsMax() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
        XCTAssertEqual(creds.accountTier.displayName, "Max")
    }

    func testMax20xTierReadsAsUltra() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
        XCTAssertEqual(creds.accountTier.displayName, "Ultra")
    }

    func testUltraTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "ultra", rateLimitTier: nil)
        XCTAssertEqual(creds.accountTier.displayName, "Ultra")
    }

    func testUltraDropsALeftoverMultiplier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "ultra", rateLimitTier: "default_claude_max_20x")
        XCTAssertEqual(creds.accountTier.displayName, "Ultra")
        XCTAssertEqual(AccountTier(displayName: "Ultra 20x").displayName, "Ultra")
    }

    func testEnterpriseTier() {
        let creds = ClaudeCredentials(accessToken: "token", subscriptionType: "enterprise", rateLimitTier: nil)
        XCTAssertEqual(creds.accountTier.displayName, "Enterprise")
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

    // MARK: - AccountTier from a cached display name

    func testCachedMax20xRestoresAsUltra() {
        XCTAssertEqual(AccountTier(displayName: "Max 20x").displayName, "Ultra")
    }

    func testCachedMax5xRestoresAsMax() {
        XCTAssertEqual(AccountTier(displayName: "Max 5x").displayName, "Max")
    }

    func testCachedTeam5xKeepsItsMultiplier() {
        XCTAssertEqual(AccountTier(displayName: "Team 5x").displayName, "Team 5x")
    }

    // MARK: - AccountTier Equality

    func testAccountTierEquality() {
        XCTAssertEqual(AccountTier.free, AccountTier(plan: "Free", multiplier: nil))
        XCTAssertNotEqual(AccountTier(plan: "Team", multiplier: "5x"), AccountTier(plan: "Team", multiplier: nil))
    }
}
