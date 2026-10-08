import XCTest
@testable import Spark

final class CodexEarliestDayTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spark-codex-days-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func touch(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
    }

    func testEarliestDayComesFromTheSessionFolders() throws {
        try touch("sessions/2026/10/05/rollout-2026-10-05T10-00-00-a.jsonl")
        try touch("sessions/2026/09/28/rollout-2026-09-28T10-00-00-b.jsonl")
        try touch("sessions/2025/12/31/rollout-2025-12-31T10-00-00-c.jsonl")
        XCTAssertEqual(CodexEarliestDay.dayKey(in: [root.appendingPathComponent("sessions")]), "2025-12-31")
    }

    func testEmptyAndMissingFoldersHaveNoEarliestDay() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions/2026/10"), withIntermediateDirectories: true)
        XCTAssertNil(CodexEarliestDay.dayKey(in: [root.appendingPathComponent("sessions"), root.appendingPathComponent("nope")]))
    }

    func testArchivedRolloutsAreDatedByTheirFileName() throws {
        try touch("sessions/2026/10/05/rollout-2026-10-05T10-00-00-a.jsonl")
        try touch("archived_sessions/rollout-2026-08-14T09-00-00-z.jsonl")
        let key = CodexEarliestDay.dayKey(in: [root.appendingPathComponent("sessions"), root.appendingPathComponent("archived_sessions")])
        XCTAssertEqual(key, "2026-08-14")
    }

    func testEarlierPeriodConsidersCodexActivity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z"))
        func hasEarlier(offset: Int, codex: String?) -> Bool {
            PeriodReport.hasEarlierPeriod(periodOffset: offset, rollups: [:], earliestExtraDay: codex, now: now, calendar: calendar)
        }
        XCTAssertFalse(hasEarlier(offset: 0, codex: nil))
        XCTAssertTrue(hasEarlier(offset: 0, codex: "2026-09-01"))
        XCTAssertTrue(hasEarlier(offset: 2, codex: "2026-09-01"))
        XCTAssertFalse(hasEarlier(offset: 6, codex: "2026-09-01"))
    }
}
