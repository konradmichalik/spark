@testable import Spark
import XCTest

final class ReportScopingTests: XCTestCase {
    private let calendar = TestCalendar.berlin()

    private func date(_ day: String) -> Date {
        TestCalendar.date(day, calendar: calendar)
    }

    /// Week of 2026-08-14 to 2026-08-20 (today 2026-08-21 not rolled up), previous week 08-07 to 08-13.
    private func report(claudeCurrent: Int, claudePrevious: Int) -> PeriodReport {
        PeriodReport.build(
            rollups: [
                "2026-08-15": DailyRollup(sessionCount: 1, input: claudeCurrent),
                "2026-08-08": DailyRollup(sessionCount: 1, input: claudePrevious)
            ],
            now: date("2026-08-21"), calendar: calendar
        )
    }

    private let codex = CodexReportData(
        dayTokens: ["2026-08-16": 300, "2026-08-09": 100, "2026-08-21": 50, "2026-08-01": 999],
        modelTokens: ["gpt-5.5": 300, "gpt-5.5-codex": 100]
    )

    func testHiddenCodexForcesClaude() {
        XCTAssertEqual(ReportScoping.effective(.all, codexShown: false), .claude)
        XCTAssertEqual(ReportScoping.effective(.codex, codexShown: false), .claude)
        XCTAssertEqual(ReportScoping.effective(.codex, codexShown: true), .codex)
    }

    func testDayTokensCombineByScope() {
        let claude = ["a": 10, "b": 5]
        let other = ["b": 1, "c": 2]
        XCTAssertEqual(ReportScoping.dayTokens(.all, claude: claude, codex: other), ["a": 10, "b": 6, "c": 2])
        XCTAssertEqual(ReportScoping.dayTokens(.claude, claude: claude, codex: other), claude)
        XCTAssertEqual(ReportScoping.dayTokens(.codex, claude: claude, codex: other), other)
    }

    func testTotalsPerScope() {
        let report = report(claudeCurrent: 1000, claudePrevious: 500)
        let claudeOnly = ReportScoping.totals(.claude, report: report, codex: codex, calendar: calendar)
        XCTAssertEqual(claudeOnly.current, 1000)
        XCTAssertEqual(claudeOnly.trendPercent, 100)
        let all = ReportScoping.totals(.all, report: report, codex: codex, calendar: calendar)
        XCTAssertEqual(all.current, 1300, "Codex tokens of today and of before the previous week stay out")
        XCTAssertEqual(all.previous, 600)
        XCTAssertEqual(all.trendPercent ?? 0, 116.666, accuracy: 0.01)
        let codexOnly = ReportScoping.totals(.codex, report: report, codex: codex, calendar: calendar)
        XCTAssertEqual([codexOnly.current, codexOnly.previous], [300, 100])
        XCTAssertEqual(codexOnly.trendPercent, 200)
    }

    func testNoPreviousCodexTokensMeansNoTrend() {
        let report = report(claudeCurrent: 1000, claudePrevious: 0)
        let onlyCurrent = CodexReportData(dayTokens: ["2026-08-16": 300], modelTokens: [:])
        XCTAssertNil(ReportScoping.totals(.codex, report: report, codex: onlyCurrent, calendar: calendar).trendPercent)
        XCTAssertNil(ReportScoping.totals(.all, report: report, codex: onlyCurrent, calendar: calendar).trendPercent)
    }

    func testUnloadedCodexCountsAsNothing() {
        let report = report(claudeCurrent: 1000, claudePrevious: 500)
        XCTAssertEqual(ReportScoping.totals(.all, report: report, codex: nil, calendar: calendar).current, 1000)
    }

    func testSectionVisibilityPerScope() {
        XCTAssertTrue(ReportScoping.showsClaudeSections(.claude))
        XCTAssertTrue(ReportScoping.showsClaudeSections(.all))
        XCTAssertFalse(ReportScoping.showsClaudeSections(.codex))
    }

    func testClaudeOnlySectionsAreLabelledInAll() {
        XCTAssertEqual(ReportScoping.title("TOP PROJECTS", scope: .all), "TOP PROJECTS \u{00B7} CLAUDE")
        XCTAssertEqual(ReportScoping.title("TOP PROJECTS", scope: .claude), "TOP PROJECTS")
    }

    func testCostTooltipNamesClaudeOnlyInAll() {
        XCTAssertTrue(ReportScoping.costTooltip("Estimated.", scope: .all).hasPrefix("Claude only."))
        XCTAssertEqual(ReportScoping.costTooltip("Estimated.", scope: .claude), "Estimated.")
    }

    func testModelRowsMergeLargestFirst() {
        let claudeRows = ModelRow.rows(from: ["claude-opus-4-5": 200, "claude-sonnet-4-5": 50])
        let all = ReportScoping.modelRows(.all, claude: claudeRows, codex: codex)
        XCTAssertEqual(all.map(\.tokens), [300, 200, 100, 50])
        XCTAssertEqual(all.map(\.label), ["gpt-5.5", "Opus", "gpt-5.5-codex", "Sonnet"])
        XCTAssertEqual(ReportScoping.modelRows(.codex, claude: claudeRows, codex: codex).map(\.label), ["gpt-5.5", "gpt-5.5-codex"])
        XCTAssertEqual(ReportScoping.modelRows(.claude, claude: claudeRows, codex: codex).map(\.label), ["Opus", "Sonnet"])
    }

    func testCodexReportDataKnowsUse() {
        XCTAssertTrue(codex.hasUse)
        XCTAssertFalse(CodexReportData(dayTokens: [:], modelTokens: [:]).hasUse)
    }

    func testCachedCodexDataOnlyBelongsToTheSamePeriod() {
        XCTAssertEqual(ReportScoping.codexData(codex, loadedFor: "week-1", wanted: "week-1"), codex)
        XCTAssertNil(ReportScoping.codexData(codex, loadedFor: "week-1", wanted: "week-2"))
        XCTAssertNil(ReportScoping.codexData(nil, loadedFor: "week-1", wanted: "week-1"))
        XCTAssertNil(ReportScoping.codexData(codex, loadedFor: nil, wanted: "week-1"))
    }
}
