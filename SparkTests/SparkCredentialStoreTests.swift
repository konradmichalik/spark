import XCTest
@testable import Spark

final class SparkCredentialStoreTests: XCTestCase {

    // MARK: - Empty detection

    func testEmptyStoreHasNoFields() {
        let store = SparkCredentialStore.empty
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.longLivedToken)
        XCTAssertNil(store.oauthToken)
        XCTAssertNil(store.accountTier)
        XCTAssertNil(store.refreshToken)
        XCTAssertNil(store.tokenExpiresAt)
    }

    func testStoreWithAnyFieldIsNotEmpty() {
        XCTAssertFalse(SparkCredentialStore(longLivedToken: "sk-ant-oat01-x").isEmpty)
        XCTAssertFalse(SparkCredentialStore(oauthToken: "tok").isEmpty)
        XCTAssertFalse(SparkCredentialStore(accountTier: "Max 5x").isEmpty)
        XCTAssertFalse(SparkCredentialStore(refreshToken: "rt").isEmpty)
        XCTAssertFalse(SparkCredentialStore(tokenExpiresAt: 123).isEmpty)
    }

    // MARK: - JSON round-trip

    func testFullRoundTrip() throws {
        let original = SparkCredentialStore(
            longLivedToken: "sk-ant-oat01-llt",
            oauthToken: "sk-ant-oat01-oauth",
            accountTier: "Max 5x",
            refreshToken: "sk-ant-ort01-refresh",
            tokenExpiresAt: 1_780_924_522.5
        )
        let data = try XCTUnwrap(original.jsonData)
        let decoded = try XCTUnwrap(SparkCredentialStore(jsonData: data))
        XCTAssertEqual(decoded, original)
    }

    func testPartialRoundTripPreservesNils() throws {
        let original = SparkCredentialStore(longLivedToken: "sk-ant-oat01-only")
        let data = try XCTUnwrap(original.jsonData)
        let decoded = try XCTUnwrap(SparkCredentialStore(jsonData: data))
        XCTAssertEqual(decoded.longLivedToken, "sk-ant-oat01-only")
        XCTAssertNil(decoded.oauthToken)
        XCTAssertNil(decoded.refreshToken)
        XCTAssertTrue(decoded == original)
    }

    func testInitFromGarbageDataReturnsNil() {
        XCTAssertNil(SparkCredentialStore(jsonData: Data("not json".utf8)))
    }

    // MARK: - Legacy migration assembly

    func testMakeFromLegacyValues() {
        let store = SparkCredentialStore.fromLegacy(
            longLivedToken: "sk-ant-oat01-llt",
            oauthToken: "tok",
            accountTier: "Pro",
            refreshToken: "rt",
            tokenExpiresAtRaw: "1780924522.5"
        )
        XCTAssertEqual(store.longLivedToken, "sk-ant-oat01-llt")
        XCTAssertEqual(store.oauthToken, "tok")
        XCTAssertEqual(store.accountTier, "Pro")
        XCTAssertEqual(store.refreshToken, "rt")
        XCTAssertEqual(store.tokenExpiresAt, 1_780_924_522.5)
    }

    func testMakeFromLegacyWithNoValuesIsEmpty() {
        let store = SparkCredentialStore.fromLegacy(
            longLivedToken: nil,
            oauthToken: nil,
            accountTier: nil,
            refreshToken: nil,
            tokenExpiresAtRaw: nil
        )
        XCTAssertTrue(store.isEmpty)
    }

    func testMakeFromLegacyIgnoresUnparsableExpiry() {
        let store = SparkCredentialStore.fromLegacy(
            longLivedToken: nil,
            oauthToken: "tok",
            accountTier: nil,
            refreshToken: nil,
            tokenExpiresAtRaw: "not-a-number"
        )
        XCTAssertEqual(store.oauthToken, "tok")
        XCTAssertNil(store.tokenExpiresAt)
    }
}
