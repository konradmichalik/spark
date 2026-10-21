import XCTest
@testable import Spark

final class CodexHistoryTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func usage(session: Double? = nil, week: Double? = nil) throws -> CodexUsage {
        let windows = [(session, 18_000), (week, 604_800)].compactMap { value, duration -> String? in
            value.map { #"{"used_percent":\#($0),"limit_window_seconds":\#(duration)}"# }
        }
        let entries = zip(["primary_window", "secondary_window"], windows).map { #""\#($0)":\#($1)"# }
        let json = #"{"rate_limit":{\#(entries.joined(separator: ","))}}"#
        return CodexUsage(response: try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8)))
    }

    func testRecordsBothLimitsAndResetWithoutInterpolation() throws {
        let first = CodexHistory.recording(try usage(session: 80, week: 40), in: [], at: now)
        let history = CodexHistory.recording(try usage(session: 0, week: 41), in: first, at: now.addingTimeInterval(300))
        XCTAssertEqual(history.map(\.sessionHistoryValue), [80, 0])
        XCTAssertEqual(history.map(\.weeklyHistoryValue), [40, 41])
        XCTAssertEqual(history.last?.timestamp, now.addingTimeInterval(300))
    }

    func testWeeklyOnlyOmitsSessionFromChartPeaksAndLatestReadout() throws {
        let first = CodexHistory.recording(try usage(session: 80, week: 40), in: [], at: now.addingTimeInterval(-1800))
        let history = CodexHistory.recording(try usage(week: 0), in: first, at: now)
        let columns = HistoryColumns.make(history, now: now)
        XCTAssertNil(columns.last?.session)
        XCTAssertEqual(columns.last?.weekly, 0)
        let onlyWeekly = Array(history.suffix(1))
        XCTAssertNil(HistorySummary.make(onlyWeekly).peakSession)
        XCTAssertEqual(HistorySummary.make(onlyWeekly).peakWeek, 0)
        XCTAssertEqual(HistoryColumns.spokenLatest(columns, locale: Locale(identifier: "en_US")), "Latest: week 0%")
    }

    func testSessionOnlyAndNoSupportedWindows() throws {
        let history = CodexHistory.recording(try usage(session: 12), in: [], at: now)
        XCTAssertEqual(history.last?.sessionHistoryValue, 12)
        XCTAssertNil(history.last?.weeklyHistoryValue)
        XCTAssertEqual(CodexHistory.recording(try usage(), in: history, at: now), history)
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(
            #"{"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":2592000}}}"#.utf8
        ))
        XCTAssertTrue(CodexHistory.recording(CodexUsage(response: response), in: [], at: now).isEmpty)
    }

    func testRetentionOnAppendAndLoadAndSeparateClaudeFile() throws {
        let old = UsageSnapshot(timestamp: now.addingTimeInterval(-300), sessionUtilization: 4, weeklyUtilization: 8)
        let oversized = Array(repeating: old, count: 8641)
        let url = directory.appendingPathComponent("codex-history.json")
        let claudeURL = directory.appendingPathComponent("history.json")
        let claude = HistoryFile(schemaVersion: 1, snapshots: [old], rollups: ["2026-01-01": DailyRollup(sessionCount: 2)])
        HistoryPersistence.save(claude, to: claudeURL)
        HistoryPersistence.save(HistoryFile(schemaVersion: 1, snapshots: oversized, rollups: [:]), to: url)
        XCTAssertEqual(CodexHistory.load(from: url).count, 8640)
        let recorded = CodexHistory.recording(try usage(week: 22), in: oversized, at: now)
        XCTAssertEqual(recorded.count, 8640)
        XCTAssertEqual(recorded.last?.weeklyHistoryValue, 22)
        CodexHistory.save(recorded, to: url)
        XCTAssertEqual(CodexHistory.load(from: url), recorded)
        XCTAssertEqual(HistoryPersistence.load(from: claudeURL), claude)
    }

    func testMissingAndCorruptHistoryStartEmpty() throws {
        let url = directory.appendingPathComponent("codex-history.json")
        XCTAssertTrue(CodexHistory.load(from: url).isEmpty)
        try Data("broken".utf8).write(to: url)
        XCTAssertTrue(CodexHistory.load(from: url).isEmpty)
    }

    func testLegacySnapshotWithoutMetadataKeepsBothLimits() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","timestamp":0,"sessionUtilization":0,"weeklyUtilization":15}"#
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.sessionHistoryValue, 0)
        XCTAssertEqual(snapshot.weeklyHistoryValue, 15)
    }

    func testWeeklyLineStartsAgainAfterMissingWindowOrCollapsedGap() {
        let columns = [
            HistoryColumn(session: 10, weekly: 20),
            HistoryColumn(session: 12, weekly: nil),
            HistoryColumn(session: 14, weekly: 25),
            HistoryColumn(session: 15, weekly: 26),
            HistoryColumn(session: nil, weekly: nil),
            HistoryColumn(session: nil, weekly: nil),
            HistoryColumn(session: nil, weekly: nil),
            HistoryColumn(session: nil, weekly: 30)
        ]
        let items = HistoryLayout.items(columns)
        XCTAssertEqual(HistoryLayout.weeklySegmentStarts(items: items, columns: columns), [0, 2, 5])
    }

    @MainActor
    func testAppliedUsagePersistsAcrossStateRecreationAndDisabledResponseIsIgnored() throws {
        let url = directory.appendingPathComponent("codex-history.json")
        let state = CodexState(historyURL: url)
        let wasEnabled = state.isEnabled
        defer { state.isEnabled = wasEnabled }
        state.isEnabled = true
        state.applyUsage(try usage(session: 28, week: 7))
        XCTAssertEqual(state.history.last?.sessionHistoryValue, 28)
        let restored = CodexState(historyURL: url)
        XCTAssertEqual(restored.history, state.history)
        state.isEnabled = false
        state.applyUsage(try usage(session: 99, week: 99))
        XCTAssertEqual(state.usage?.usageData.session?.utilization, 28)
        XCTAssertEqual(CodexHistory.load(from: url), restored.history)
    }
}
