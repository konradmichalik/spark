import XCTest
@testable import Spark

final class MenuBarConnectionTests: XCTestCase {
    private let now = Date()

    func testClaudeReconnectDoesNotTouchCodex() {
        let codex = MenuBarConnection.codex(needsSignIn: false, hasError: false, lastUpdated: now.addingTimeInterval(-60))
        XCTAssertFalse(codex.isStale(now: now))
        XCTAssertFalse(codex.isDisconnected)
    }

    func testCodexSignInIsStaleAndDisconnected() {
        let codex = MenuBarConnection.codex(needsSignIn: true, hasError: false, lastUpdated: now)
        XCTAssertTrue(codex.isStale(now: now))
        XCTAssertTrue(codex.isDisconnected)
    }

    func testCodexWithoutDataIsStale() {
        let codex = MenuBarConnection.codex(needsSignIn: false, hasError: false, lastUpdated: nil)
        XCTAssertTrue(codex.isStale(now: now))
    }

    func testClaudeReconnectIsStaleAndDisconnected() {
        let claude = MenuBarConnection.claude(isAuthenticated: true, needsReconnect: true, hasError: false, lastUpdated: now)
        XCTAssertTrue(claude.isStale(now: now))
        XCTAssertTrue(claude.isDisconnected)
    }

    func testLoggedOutClaudeIsStaleAndDisconnected() {
        let claude = MenuBarConnection.claude(isAuthenticated: false, needsReconnect: false, hasError: false, lastUpdated: now)
        XCTAssertTrue(claude.isStale(now: now))
        XCTAssertTrue(claude.isDisconnected)
    }

    func testHealthyClaudeIsFresh() {
        let claude = MenuBarConnection.claude(isAuthenticated: true, needsReconnect: false, hasError: false, lastUpdated: now)
        XCTAssertFalse(claude.isStale(now: now))
        XCTAssertFalse(claude.isDisconnected)
    }

    func testErrorIsStaleButNotDisconnected() {
        let claude = MenuBarConnection.claude(isAuthenticated: true, needsReconnect: false, hasError: true, lastUpdated: now)
        XCTAssertTrue(claude.isStale(now: now))
        XCTAssertFalse(claude.isDisconnected)
    }
}
