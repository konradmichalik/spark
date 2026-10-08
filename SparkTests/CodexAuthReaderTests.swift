import XCTest
@testable import Spark

final class CodexAuthReaderTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeAuth(_ json: String) throws -> URL {
        let url = tempDir.appendingPathComponent("auth.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    // MARK: - CodexHome

    func testHomeDefaultsToDotCodex() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertEqual(CodexHome.resolve(environmentValue: nil, homeDirectory: home).path, "/Users/test/.codex")
        XCTAssertEqual(CodexHome.resolve(environmentValue: "  ", homeDirectory: home).path, "/Users/test/.codex")
    }

    func testHomeHonorsEnvironmentOverride() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertEqual(CodexHome.resolve(environmentValue: "/opt/codex", homeDirectory: home).path, "/opt/codex")
        XCTAssertEqual(CodexHome.resolve(environmentValue: "~/work/codex", homeDirectory: home).path, "/Users/test/work/codex")
    }

    // MARK: - Credentials

    func testReadsChatGPTTokens() throws {
        let url = try writeAuth("""
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": { "id_token": "id", "access_token": "access-123", "refresh_token": "refresh", "account_id": "acct-1" },
          "last_refresh": "2026-10-07T08:00:00Z"
        }
        """)

        let credentials = CodexAuthReader.read(from: url)

        XCTAssertEqual(credentials?.accessToken, "access-123")
        XCTAssertEqual(credentials?.accountId, "acct-1")
    }

    func testMissingAccountIdIsAllowed() throws {
        let url = try writeAuth("""
        { "tokens": { "access_token": "access-123" } }
        """)

        XCTAssertEqual(CodexAuthReader.read(from: url)?.accessToken, "access-123")
        XCTAssertNil(CodexAuthReader.read(from: url)?.accountId)
    }

    /// API-key users have no ChatGPT plan, so there is no plan usage to show.
    func testApiKeyOnlyAuthReturnsNil() throws {
        let url = try writeAuth("""
        { "auth_mode": "apikey", "OPENAI_API_KEY": "sk-test", "tokens": null }
        """)

        XCTAssertNil(CodexAuthReader.read(from: url))
    }

    func testEmptyTokenReturnsNil() throws {
        let url = try writeAuth("""
        { "tokens": { "access_token": "" } }
        """)

        XCTAssertNil(CodexAuthReader.read(from: url))
    }

    func testMissingOrGarbageFileReturnsNil() throws {
        XCTAssertNil(CodexAuthReader.read(from: tempDir.appendingPathComponent("nope.json")))
        XCTAssertNil(CodexAuthReader.read(from: try writeAuth("not json")))
    }
}
