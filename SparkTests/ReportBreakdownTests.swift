@testable import Spark
import XCTest

final class ReportBreakdownTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let berlin = TestCalendar.berlin().timeZone

    private func session(_ id: String, _ tokens: Int, start: Date? = nil, duration: TimeInterval? = nil) -> SessionUsage {
        SessionUsage(id: id, displayName: "app-\(id)", tokens: tokens, start: start, duration: duration)
    }

    private func cost(byProject: [String: Double] = [:], bySession: [String: Double] = [:]) -> CostSummary {
        CostSummary(total: 0, byModel: [:], byProject: byProject, bySession: bySession, unpricedModels: [])
    }

    func testModelRowsShareTheRowTotalAndScaleToTheTopRow() {
        let claude = ModelRow.rows(from: ["claude-opus-4-1": 600, "claude-sonnet-4-5": 100])
        let codex = CodexReportData(dayTokens: [:], modelTokens: ["gpt-5.5": 300])

        let rows = ReportBreakdown.models(.all, claude: claude, codex: codex, locale: english)

        XCTAssertEqual(rows.map(\.name), ["Opus", "gpt-5.5", "Sonnet"])
        XCTAssertEqual(rows.map(\.detail), ["60%", "30%", "10%"])
        XCTAssertEqual(rows.prefix(2).map(\.barPercent), [100, 50])
        XCTAssertEqual(rows.last?.barPercent ?? 0, 16.67, accuracy: 0.01)
        XCTAssertEqual(rows.map(\.providers), [[.claude], [.codex], [.claude]])
        XCTAssertEqual(rows.first?.tooltip, claude.first?.versionSummary)
    }

    func testLogosOnlyInAll() {
        let claude = ModelRow.rows(from: ["claude-opus-4-1": 600])

        let rows = ReportBreakdown.models(.claude, claude: claude, codex: nil, locale: english)

        XCTAssertEqual(rows.map(\.providers), [[]])
    }

    func testTinyShareReadsBelowOnePercent() {
        let claude = ModelRow.rows(from: ["claude-opus-4-1": 1000, "claude-sonnet-4-5": 2])

        let rows = ReportBreakdown.models(.claude, claude: claude, codex: nil, locale: english)

        XCTAssertEqual(rows.last?.detail, "<1%")
    }

    func testProjectRowsMergeProvidersAndMarkClaudeOnlyCost() {
        let claude = [
            ProjectUsage(key: "-work-app", displayName: "app", tokens: 600, cwd: "/work/app"),
            ProjectUsage(key: "-work-site", displayName: "site", tokens: 150, cwd: "/work/site")
        ]
        let codex = CodexReportData(dayTokens: [:], modelTokens: [:], projectTokens: ["/work/app/": 200, "/work/cli": 50])
        let summary = cost(byProject: ["-work-app": 12.5, "-work-site": 1])

        let rows = ReportBreakdown.projects(.all, claude: claude, cost: summary, codex: codex, locale: english)

        XCTAssertEqual(rows.map(\.name), ["app", "site", "cli"])
        XCTAssertEqual(rows.map(\.providers), [[.claude, .codex], [.claude], [.codex]])
        XCTAssertEqual(rows.map(\.detail), ["80%", "15%", "5%"])
        XCTAssertEqual(rows.first?.tooltip, "800 tokens\n\u{2248} $12.50 at API list prices, Claude only")
        XCTAssertEqual(rows[1].tooltip, "150 tokens\n\u{2248} $1.00 at API list prices")
        XCTAssertEqual(rows.last?.tooltip, "50 tokens")
        XCTAssertEqual(rows.first?.path, "/work/app")
    }

    func testCodexScopeProjectsCarryNoCost() {
        let claude = [ProjectUsage(key: "-work-app", displayName: "app", tokens: 600, cwd: "/work/app")]
        let codex = CodexReportData(dayTokens: [:], modelTokens: [:], projectTokens: ["/work/app": 200])

        let rows = ReportBreakdown.projects(.codex, claude: claude, cost: cost(byProject: ["-work-app": 3]), codex: codex, locale: english)

        XCTAssertEqual(rows.map(\.tooltip), ["200 tokens"])
        XCTAssertEqual(rows.map(\.providers), [[]])
    }

    func testSessionsMergeByTokensAndKeepTheTopTen() {
        let claude = (1...10).map { session("c\($0)", $0 * 100) }
        let codex = CodexReportData(dayTokens: [:], modelTokens: [:], topSessions: [session("x1", 950), session("x2", 50)])

        let rows = ReportBreakdown.sessions(
            .all, claude: claude, cost: cost(bySession: ["c10": 2]), codex: codex, locale: english, timeZone: berlin
        )

        XCTAssertEqual(rows.count, 10)
        XCTAssertEqual(rows.prefix(3).map(\.tokens), [1000, 950, 900])
        XCTAssertEqual(rows.prefix(2).map(\.providers), [[.claude], [.codex]])
        XCTAssertEqual(rows.first?.tooltip, "1.0K tokens\n\u{2248} $2.00 at API list prices")
        XCTAssertEqual(rows[1].tooltip, "950 tokens")
        XCTAssertEqual(Set(rows.map(\.id)).count, 10, "Ids stay unique across providers")
        XCTAssertEqual(rows.first?.barPercent, 100)
    }

    func testSessionDetailIsStartAndDuration() {
        let start = TestCalendar.date("2026-08-20", time: "14:20")
        let rows = ReportBreakdown.sessions(
            .claude, claude: [session("a", 10, start: start, duration: 7500), session("b", 5, start: start, duration: 30)],
            cost: nil, codex: nil, locale: english, timeZone: berlin
        )

        XCTAssertEqual(rows.map(\.detail), ["Thu 2:20\u{202F}PM \u{00B7} 2h 5m", "Thu 2:20\u{202F}PM"])
    }

    func testRowsForAReportReadItsLists() {
        let report = PeriodReport.build(
            rollups: [:], modelTotals: ["claude-opus-4-1": 10],
            topProjects: [ProjectUsage(key: "-work-app", displayName: "app", tokens: 10, cwd: "/work/app")],
            topSessions: [session("a", 10)]
        )

        XCTAssertEqual(ReportBreakdown.rows(.models, scope: .claude, report: report, codex: nil).map(\.name), ["Opus"])
        XCTAssertEqual(ReportBreakdown.rows(.projects, scope: .claude, report: report, codex: nil).map(\.name), ["app"])
        XCTAssertEqual(ReportBreakdown.rows(.sessions, scope: .claude, report: report, codex: nil).map(\.name), ["app-a"])
        XCTAssertEqual(ReportBreakdown.rows(.sessions, scope: .codex, report: report, codex: nil), [])
    }
}
