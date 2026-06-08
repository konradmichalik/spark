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

    // MARK: - Token validation

    func testValidLongLivedTokenAccepted() {
        // setup-token output starts with sk-ant-oat (long-lived OAuth tokens)
        XCTAssertTrue(KeychainService.isLikelyValidLongLivedToken("sk-ant-oat01-abcdef"))
    }

    func testEmptyTokenRejected() {
        XCTAssertFalse(KeychainService.isLikelyValidLongLivedToken(""))
        XCTAssertFalse(KeychainService.isLikelyValidLongLivedToken("   "))
    }

    func testWhitespaceTrimmed() {
        // User-pasted tokens often have trailing whitespace from copy/paste
        XCTAssertTrue(KeychainService.isLikelyValidLongLivedToken("  sk-ant-oat01-xyz\n"))
    }

    func testObviouslyWrongTokenRejected() {
        XCTAssertFalse(KeychainService.isLikelyValidLongLivedToken("hello world"))
        XCTAssertFalse(KeychainService.isLikelyValidLongLivedToken("short"))
    }

    // MARK: - SettingsTab

    func testAdvancedSettingsTabExists() {
        let tab: SettingsTab = .advanced
        XCTAssertEqual(tab, .advanced)
    }
}
