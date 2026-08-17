import XCTest
@testable import Spark

final class HistoryPersistenceTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMissingFileReturnsEmptyHistory() {
        let loaded = HistoryPersistence.load(from: tempDir.appendingPathComponent("does-not-exist.json"))
        XCTAssertEqual(loaded, HistoryFile.empty)
    }

    func testRoundTripsSnapshotsAndRollups() throws {
        let url = tempDir.appendingPathComponent("history.json")
        var file = HistoryFile.empty
        file.snapshots = [UsageSnapshot(sessionUtilization: 10, weeklyUtilization: 20)]
        file.rollups["2026-01-01"] = DailyRollup(sessionCount: 3, input: 100, output: 50, cacheCreation: 0, cacheRead: 0)

        HistoryPersistence.save(file, to: url)
        let loaded = HistoryPersistence.load(from: url)

        XCTAssertEqual(loaded.snapshots.count, 1)
        XCTAssertEqual(loaded.rollups["2026-01-01"]?.input, 100)
        XCTAssertEqual(loaded.schemaVersion, HistoryFile.currentSchemaVersion)
    }

    func testDecodesLegacyBareSnapshotArrayAsVersionZero() throws {
        // The format history.json shipped in before rollups existed: a bare JSON array of
        // snapshots, no wrapper object at all.
        let url = tempDir.appendingPathComponent("legacy-history.json")
        let legacySnapshots = [
            UsageSnapshot(sessionUtilization: 42, weeklyUtilization: 65),
            UsageSnapshot(sessionUtilization: 10, weeklyUtilization: 5)
        ]
        try JSONEncoder().encode(legacySnapshots).write(to: url)

        let loaded = HistoryPersistence.load(from: url)

        XCTAssertEqual(loaded.snapshots.count, 2)
        XCTAssertTrue(loaded.rollups.isEmpty)
        XCTAssertEqual(loaded.schemaVersion, HistoryFile.currentSchemaVersion)
    }

    func testUnreadableFileDoesNotThrowAndReturnsEmpty() throws {
        let url = tempDir.appendingPathComponent("garbage.json")
        try Data("not json at all {{{".utf8).write(to: url)

        let loaded = HistoryPersistence.load(from: url)

        XCTAssertEqual(loaded, HistoryFile.empty)
    }

    // MARK: - Rollup merging

    func testMergingAddsNewClosedDays() {
        let closedDays = [
            "2026-01-01": DayAggregate(sessionIds: ["s1"], input: 100, output: 50, cacheCreation: 0, cacheRead: 0)
        ]

        let merged = DailyRollup.merging(closedDays, into: [:])

        XCTAssertEqual(merged["2026-01-01"]?.input, 100)
        XCTAssertEqual(merged["2026-01-01"]?.sessionCount, 1)
    }

    func testMergingNeverOverwritesAnAlreadyRecordedDay() {
        let existing = ["2026-01-01": DailyRollup(sessionCount: 1, input: 999, output: 0, cacheCreation: 0, cacheRead: 0)]
        let closedDays = [
            "2026-01-01": DayAggregate(sessionIds: ["s1", "s2"], input: 5, output: 5, cacheCreation: 0, cacheRead: 0)
        ]

        let merged = DailyRollup.merging(closedDays, into: existing)

        XCTAssertEqual(merged["2026-01-01"]?.input, 999, "an already-recorded closed day must never be recomputed")
    }

    func testMergingLeavesUnrelatedExistingDaysAlone() {
        let existing = ["2025-12-31": DailyRollup(sessionCount: 1, input: 10, output: 0, cacheCreation: 0, cacheRead: 0)]
        let closedDays = [
            "2026-01-01": DayAggregate(sessionIds: ["s1"], input: 100, output: 50, cacheCreation: 0, cacheRead: 0)
        ]

        let merged = DailyRollup.merging(closedDays, into: existing)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged["2025-12-31"]?.input, 10)
        XCTAssertEqual(merged["2026-01-01"]?.input, 100)
    }
}
