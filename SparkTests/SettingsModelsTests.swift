import XCTest
@testable import Spark

final class ConnectionSummaryTests: XCTestCase {
    func testClaudeConnectedNamesPlanAndSignInPath() {
        let line = ConnectionSummary.claude(isAuthenticated: true, needsReconnect: false, plan: "Max 5×", method: .claudeCode)
        XCTAssertEqual(line, ConnectionLine(state: .connected, text: "Connected · Max 5× · via the keychain"))
    }

    func testClaudeWithLongLivedTokenAndNoPlan() {
        let line = ConnectionSummary.claude(isAuthenticated: true, needsReconnect: false, plan: nil, method: .longLivedToken)
        XCTAssertEqual(line.text, "Connected · via long-lived token")
    }

    func testClaudeNeedingReconnectIsExpiredEvenWhileAuthenticated() {
        let line = ConnectionSummary.claude(isAuthenticated: true, needsReconnect: true, plan: "Pro", method: .claudeCode)
        XCTAssertEqual(line, ConnectionLine(state: .expired, text: "Session expired · Pro"))
    }

    func testClaudeWithoutSignIn() {
        let line = ConnectionSummary.claude(isAuthenticated: false, needsReconnect: false, plan: nil, method: .none)
        XCTAssertEqual(line, ConnectionLine(state: .notFound, text: "Not connected"))
    }

    func testCodexStates() {
        XCTAssertEqual(
            ConnectionSummary.codex(isEnabled: false, isAvailable: true, needsSignIn: false, plan: "Plus"),
            ConnectionLine(state: .off, text: "Off")
        )
        XCTAssertEqual(
            ConnectionSummary.codex(isEnabled: true, isAvailable: false, needsSignIn: false, plan: nil),
            ConnectionLine(state: .notFound, text: "No ChatGPT sign-in found")
        )
        XCTAssertEqual(
            ConnectionSummary.codex(isEnabled: true, isAvailable: true, needsSignIn: true, plan: "Plus"),
            ConnectionLine(state: .expired, text: "Sign-in expired · ChatGPT Plus")
        )
        XCTAssertEqual(
            ConnectionSummary.codex(isEnabled: true, isAvailable: true, needsSignIn: false, plan: "Pro"),
            ConnectionLine(state: .connected, text: "Connected · ChatGPT Pro · via Codex CLI")
        )
    }
}

final class MenuBarSettingsTests: XCTestCase {
    func testFootnoteNamesClaudeWhenCodexIsOff() {
        XCTAssertEqual(MenuBarFootnote.text(codexIsActive: false), "The menu bar shows Claude. Turn on Codex in Connections to switch.")
    }

    func testFootnoteFollowsTheTabWhenCodexIsOn() {
        XCTAssertEqual(MenuBarFootnote.text(codexIsActive: true), "The menu bar shows the provider of the tab you opened last.")
    }

    func testValueOptionsKeepTheStoredKeys() {
        XCTAssertEqual(MenuBarValueOption.allCases.map(\.rawValue), ["max", "session", "weekly", "none"])
        XCTAssertEqual(MenuBarValueOption.allCases.map(\.segmentLabel), ["Highest", "Session", "Week", "None"])
    }

    func testUnknownStoredValueFallsBackToHighest() {
        XCTAssertEqual(MenuBarValueOption(stored: "both"), .max)
        XCTAssertEqual(MenuBarValueOption(stored: "session"), .session)
    }
}
