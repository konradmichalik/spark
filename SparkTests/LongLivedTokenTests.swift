import XCTest
@testable import Spark

final class LongLivedTokenTests: XCTestCase {

    // MARK: - AuthMethod

    func testLongLivedTokenAuthMethodCase() {
        let method: AuthMethod = .longLivedToken
        XCTAssertEqual(method.rawValue, "Long-lived Token")
    }

    func testExistingAuthMethodsUnchanged() {
        XCTAssertEqual(AuthMethod.none.rawValue, "none")
        XCTAssertEqual(AuthMethod.claudeCode.rawValue, "Claude Code")
    }

    // MARK: - Keychain account constants

    func testLongLivedTokenAccountName() {
        // Stable account name keeps stored tokens across app updates
        XCTAssertEqual(KeychainService.longLivedTokenAccount, "long-lived-token")
    }

    // MARK: - Token cleaning + validation

    func testValidLongLivedTokenAccepted() {
        XCTAssertEqual(
            KeychainService.cleanedLongLivedToken("sk-ant-oat01-abcdef"),
            "sk-ant-oat01-abcdef"
        )
    }

    func testEmptyTokenRejected() {
        XCTAssertNil(KeychainService.cleanedLongLivedToken(""))
        XCTAssertNil(KeychainService.cleanedLongLivedToken("   "))
    }

    func testWhitespaceTrimmedFromValidToken() {
        // User-pasted tokens often have trailing whitespace from copy/paste
        XCTAssertEqual(
            KeychainService.cleanedLongLivedToken("  sk-ant-oat01-xyz\n"),
            "sk-ant-oat01-xyz"
        )
    }

    func testObviouslyWrongTokenRejected() {
        XCTAssertNil(KeychainService.cleanedLongLivedToken("hello world"))
        XCTAssertNil(KeychainService.cleanedLongLivedToken("short"))
    }

    // MARK: - SettingsTab

    func testAdvancedSettingsTabExists() {
        let tab: SettingsTab = .advanced
        XCTAssertEqual(tab, .advanced)
    }
}
