import XCTest
@testable import Spark

final class PricingClientTests: XCTestCase {
    private var cacheURL = FileManager.default.temporaryDirectory

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let fresh = PricingTable(prices: [
        "claude-sonnet-5-5": ModelPrice(input: 3e-6, output: 15e-6, cacheCreation: 3.75e-6, cacheCreation1h: 6e-6, cacheRead: 3e-7)
    ])
    private let old = PricingTable(prices: [
        "claude-sonnet-4-5": ModelPrice(input: 3e-6, output: 15e-6, cacheCreation: 3.75e-6, cacheCreation1h: 6e-6, cacheRead: 3e-7)
    ])

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("pricing.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
    }

    func testFetchesAndCachesWhenNothingIsCached() async {
        let fresh = fresh
        let table = await PricingClient.currentTable(now: now, cacheURL: cacheURL) { fresh }

        XCTAssertEqual(table, fresh)
        XCTAssertEqual(PricingClient.loadCache(from: cacheURL)?.table, fresh)
    }

    func testFreshCacheSkipsTheNetwork() async {
        PricingClient.saveCache(PricingCache(fetchedAt: now.addingTimeInterval(-3_600), table: old), to: cacheURL)
        let fetched = FetchCounter()

        let table = await PricingClient.currentTable(now: now, cacheURL: cacheURL) { [fresh] in
            await fetched.increment()
            return fresh
        }

        XCTAssertEqual(table, old)
        let count = await fetched.count
        XCTAssertEqual(count, 0)
    }

    func testStaleCacheIsRefreshed() async {
        PricingClient.saveCache(PricingCache(fetchedAt: now.addingTimeInterval(-90_000), table: old), to: cacheURL)

        let fresh = fresh
        let table = await PricingClient.currentTable(now: now, cacheURL: cacheURL) { fresh }

        XCTAssertEqual(table, fresh)
        XCTAssertEqual(PricingClient.loadCache(from: cacheURL)?.fetchedAt, now)
    }

    func testStaleCacheIsUsedWhenTheFetchFails() async {
        PricingClient.saveCache(PricingCache(fetchedAt: now.addingTimeInterval(-90_000), table: old), to: cacheURL)

        let table = await PricingClient.currentTable(now: now, cacheURL: cacheURL) { throw URLError(.notConnectedToInternet) }

        XCTAssertEqual(table, old)
    }

    func testReturnsNilWhenOfflineWithoutCache() async {
        let table = await PricingClient.currentTable(now: now, cacheURL: cacheURL) { throw URLError(.notConnectedToInternet) }

        XCTAssertNil(table)
    }

    func testUnreadableCacheFileCountsAsNoCache() throws {
        try Data("garbage".utf8).write(to: cacheURL)

        XCTAssertNil(PricingClient.loadCache(from: cacheURL))
    }
}

private actor FetchCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
