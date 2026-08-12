import XCTest
@testable import Spark

final class CLIVersionClientTests: XCTestCase {

    // MARK: - BrewCask decoding

    func testBrewCaskDecodesVersion() throws {
        let json = Data("""
        {"token":"claude-code","name":["Claude Code"],"version":"2.1.221"}
        """.utf8)
        let cask = try JSONDecoder().decode(CLIVersionClient.BrewCask.self, from: json)
        XCTAssertEqual(cask.version, "2.1.221")
    }

    // MARK: - isNewer (pre-existing behavior, not previously covered)

    func testIsNewerDetectsGreaterVersion() {
        XCTAssertTrue(CLIVersionClient.isNewer("2.1.228", than: "2.1.221"))
        XCTAssertFalse(CLIVersionClient.isNewer("2.1.221", than: "2.1.228"))
        XCTAssertFalse(CLIVersionClient.isNewer("2.1.221", than: "2.1.221"))
    }
}
