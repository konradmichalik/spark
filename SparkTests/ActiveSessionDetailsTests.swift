@testable import Spark
import XCTest

final class ActiveSessionDetailsTests: XCTestCase {
    private let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private let sessionId = "1b8386d5-1111-1111-1111-111111111111"

    private func cache(models: [String: Int], first: Date? = nil) -> FileParseCache {
        var bucket = DayAggregate()
        for (model, output) in models {
            bucket.perModel[model] = ModelTokenTotals(output: output)
        }
        return FileParseCache(
            mtime: now.addingTimeInterval(-10), size: 10, parsedByteOffset: 10, dailyBuckets: ["2027-01-15": bucket],
            activity: first.map { ActivitySpan(first: $0, last: now) }
        )
    }

    private var rootPath: String {
        projectsDir.appendingPathComponent("-Users-me-app").appendingPathComponent("\(sessionId).jsonl").path
    }

    private var subagentPath: String {
        projectsDir.appendingPathComponent("-Users-me-app").appendingPathComponent(sessionId)
            .appendingPathComponent("subagents").appendingPathComponent("agent-a.jsonl").path
    }

    // MARK: - Resolver

    func testSessionTakesTheRootFilesMainModel() {
        let files = [
            rootPath: cache(models: ["claude-opus-4-6": 900, "claude-haiku-4-5": 100]),
            subagentPath: cache(models: ["claude-haiku-4-5": 5000])
        ]
        let session = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now).first
        XCTAssertEqual(session?.model, "Opus 4.6")
    }

    func testSessionStartsAtItsEarliestLine() {
        let start = now.addingTimeInterval(-3600)
        let files = [
            rootPath: cache(models: [:], first: start),
            subagentPath: cache(models: [:], first: start.addingTimeInterval(600))
        ]
        let session = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now).first
        XCTAssertEqual(session?.startedAt, start)
        XCTAssertNil(session?.model)
    }

    // MARK: - Row text

    private func session(lastActivity: TimeInterval, model: String? = "Opus 4.6", started: Date? = nil) -> ActiveSession {
        ActiveSession(
            sessionId: sessionId, projectKey: "-Users-me-app", displayName: "app", lastActivity: now.addingTimeInterval(-lastActivity),
            contextTokens: 142_000, model: model, startedAt: started
        )
    }

    func testSubtitleSaysHowLongAgo() {
        XCTAssertEqual(ActiveSessionText.subtitle(session(lastActivity: 10), now: now), "just now")
        XCTAssertEqual(ActiveSessionText.subtitle(session(lastActivity: 59), now: now), "just now")
        XCTAssertEqual(ActiveSessionText.subtitle(session(lastActivity: 130), now: now), "2 min ago")
    }

    func testTooltipNamesSessionStartAndModel() {
        let started = Date(timeIntervalSince1970: 1_799_996_460) // 07:01 UTC
        let text = ActiveSessionText.tooltip(session(lastActivity: 10, started: started), locale: Locale(identifier: "en_GB"), timeZone: utc)
        XCTAssertEqual(text.title, "Session 1B8386D5")
        XCTAssertEqual(text.body, "Started 07:01\nModel: Opus 4.6")
    }

    func testTooltipWithoutDetailsStillNamesTheSession() {
        let text = ActiveSessionText.tooltip(session(lastActivity: 10, model: nil))
        XCTAssertEqual(text.title, "Session 1B8386D5")
        XCTAssertEqual(text.body, "Model not known yet")
    }

    func testAccessibilityLabelReadsTheRow() {
        XCTAssertEqual(ActiveSessionText.accessibilityLabel(session(lastActivity: 130), now: now), "app, 2 min ago, context 142.0K tokens")
    }

    // MARK: - Show more

    func testShowMoreHidesTheRestBehindOneRow() {
        let more = ShowMore(total: 7, limit: 4)
        XCTAssertEqual(more.visibleCount(expanded: false), 4)
        XCTAssertEqual(more.visibleCount(expanded: true), 7)
        XCTAssertEqual(more.label(expanded: false), "Show 3 more")
        XCTAssertEqual(more.label(expanded: true), "Show less")
    }

    func testShowMoreShowsASingleHiddenEntryRightAway() {
        let more = ShowMore(total: 5, limit: 4)
        XCTAssertEqual(more.visibleCount(expanded: false), 5)
        XCTAssertNil(more.label(expanded: false))
        XCTAssertNil(ShowMore(total: 2, limit: 4).label(expanded: false))
    }
}
