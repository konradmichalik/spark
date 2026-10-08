@testable import Spark
import XCTest

final class CLIVersionParsingTests: XCTestCase {
    func testClaudeOutputYieldsItsVersion() {
        XCTAssertEqual(CLIVersionClient.parseVersion("2.1.294 (Claude Code)\n"), "2.1.294")
    }

    func testCodexOutputYieldsItsVersion() {
        XCTAssertEqual(CLIVersionClient.parseVersion("codex-cli 0.46.0\n"), "0.46.0")
    }

    func testOutputWithoutAVersionYieldsNothing() {
        XCTAssertNil(CLIVersionClient.parseVersion(""))
        XCTAssertNil(CLIVersionClient.parseVersion("zsh: command not found: codex"))
    }
}

final class AboutTextTests: XCTestCase {
    func testDailyTotalsExplainWhyTheyExist() {
        XCTAssertEqual(
            AboutText.dailyTotalsNote,
            "Spark keeps one token total per day for Claude Code, so reports reach back past the days Claude Code keeps its transcripts."
        )
        XCTAssertEqual(AboutText.exportTitle, "Export daily totals\u{2026}")
        XCTAssertEqual(AboutText.clearTitle, "Clear daily totals")
    }
}
