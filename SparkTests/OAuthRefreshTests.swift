import XCTest
@testable import Spark

final class OAuthRefreshTests: XCTestCase {

    // MARK: - ClaudeCredentials JSON parsing

    func testParseFullKeychainJSON() throws {
        let json = """
        {
          "claudeAiOauth": {
            "accessToken": "sk-ant-oat01-abc",
            "refreshToken": "sk-ant-ort01-xyz",
            "expiresAt": 1780924522144,
            "scopes": ["user:inference", "user:profile"],
            "subscriptionType": "team",
            "rateLimitTier": "default_claude_max_5x"
          }
        }
        """.data(using: .utf8)!

        let creds = ClaudeCredentials(jsonData: json)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(creds?.refreshToken, "sk-ant-ort01-xyz")
        let expiry = try XCTUnwrap(creds?.expiresAt)
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_780_924_522.144, accuracy: 0.01)
        XCTAssertEqual(creds?.subscriptionType, "team")
        XCTAssertEqual(creds?.rateLimitTier, "default_claude_max_5x")
    }

    func testParseJSONWithoutRefreshToken() {
        let json = """
        {"claudeAiOauth": {"accessToken": "tok", "subscriptionType": "pro"}}
        """.data(using: .utf8)!

        let creds = ClaudeCredentials(jsonData: json)
        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "tok")
        XCTAssertNil(creds?.refreshToken)
        XCTAssertNil(creds?.expiresAt)
    }

    func testParseInvalidJSON() {
        XCTAssertNil(ClaudeCredentials(jsonData: Data("not json".utf8)))
    }

    func testParseJSONMissingToken() {
        let json = """
        {"claudeAiOauth": {"refreshToken": "rt"}}
        """.data(using: .utf8)!
        XCTAssertNil(ClaudeCredentials(jsonData: json))
    }

    // MARK: - Token expiry check

    func testIsExpiredInPast() {
        let past = Date().addingTimeInterval(-3600)
        let creds = ClaudeCredentials(
            accessToken: "t",
            refreshToken: "rt",
            expiresAt: past,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        XCTAssertTrue(creds.isExpiredOrExpiringSoon)
    }

    func testIsExpiredInFuture() {
        let future = Date().addingTimeInterval(3600)
        let creds = ClaudeCredentials(
            accessToken: "t",
            refreshToken: "rt",
            expiresAt: future,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        XCTAssertFalse(creds.isExpiredOrExpiringSoon)
    }

    func testIsExpiringWithinSkew() {
        // 30 seconds in the future — within the 60s skew window
        let soon = Date().addingTimeInterval(30)
        let creds = ClaudeCredentials(
            accessToken: "t",
            refreshToken: "rt",
            expiresAt: soon,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        XCTAssertTrue(creds.isExpiredOrExpiringSoon)
    }

    func testIsExpiredWithoutExpiry() {
        let creds = ClaudeCredentials(
            accessToken: "t",
            refreshToken: nil,
            expiresAt: nil,
            subscriptionType: nil,
            rateLimitTier: nil
        )
        // Without expiry info, assume valid — let the API tell us via 401
        XCTAssertFalse(creds.isExpiredOrExpiringSoon)
    }

    // MARK: - Refresh request building

    func testRefreshRequestURL() {
        let request = UsageClient.buildRefreshRequest(refreshToken: "rt-123")
        XCTAssertEqual(request.url?.absoluteString, "https://console.anthropic.com/v1/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRefreshRequestHeaders() {
        let request = UsageClient.buildRefreshRequest(refreshToken: "rt-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testRefreshRequestBody() throws {
        let request = UsageClient.buildRefreshRequest(refreshToken: "rt-abc")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "rt-abc")
        XCTAssertEqual(json["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
    }

    // MARK: - Refresh response decoding

    func testDecodeRefreshResponse() throws {
        let payload = """
        {
          "access_token": "sk-ant-oat01-new",
          "refresh_token": "sk-ant-ort01-rotated",
          "expires_in": 28800,
          "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let response = try UsageClient.decodeRefreshResponse(payload)
        XCTAssertEqual(response.accessToken, "sk-ant-oat01-new")
        XCTAssertEqual(response.refreshToken, "sk-ant-ort01-rotated")
        XCTAssertEqual(response.expiresIn, 28_800)
    }

    func testDecodeRefreshResponseWithoutRotation() throws {
        // Some OAuth servers don't return a new refresh_token
        let payload = """
        {"access_token": "new", "expires_in": 3600, "token_type": "Bearer"}
        """.data(using: .utf8)!

        let response = try UsageClient.decodeRefreshResponse(payload)
        XCTAssertEqual(response.accessToken, "new")
        XCTAssertNil(response.refreshToken)
        XCTAssertEqual(response.expiresIn, 3_600)
    }
}
