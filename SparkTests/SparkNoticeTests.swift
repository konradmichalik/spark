import AppKit
import XCTest
@testable import Spark

final class SparkNoticeTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .current
    /// Wednesday, 7 October 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_374_400)

    private func usage(
        provider: UsageProvider = .claude, window: String = "Session", value: Double, tone: UsageTone = .warning,
        resetIn: TimeInterval? = nil, limitIn: TimeInterval? = nil
    ) -> SparkNotice {
        NoticeWording.usage(
            provider: provider, window: window, value: value, tone: tone,
            resetsAt: resetIn.map { now.addingTimeInterval($0) }, limitIn: limitIn, now: now, locale: locale, timeZone: utc
        )
    }

    func testUsageTitleNamesProviderWindowAndValue() {
        XCTAssertEqual(usage(value: 78).title, "Claude · Session at 78%")
        XCTAssertEqual(usage(provider: .codex, window: "Week", value: 92, tone: .critical).title, "Codex · Week at 92%")
    }

    func testUsageBodyLeadsWithTheProjectionWhenTheLimitComesFirst() {
        let notice = usage(value: 78, resetIn: 6_540, limitIn: 2_400)
        XCTAssertEqual(notice.body, "At this pace the limit is reached in ~40m. Resets in 1h 49m.")
    }

    func testUsageBodyShowsWhatIsLeftAndTheResetWithoutAProjection() {
        XCTAssertEqual(usage(value: 78, resetIn: 6_540).body, "22% left. Resets in 1h 49m.")
        XCTAssertEqual(usage(value: 78).body, "22% left.")
    }

    func testUsageBodyNamesTheDayForAResetMoreThanADayAway() {
        // Monday, 12 October 2026, 09:00 UTC.
        let notice = usage(provider: .codex, window: "Week", value: 92, tone: .critical, resetIn: 421_200)
        XCTAssertEqual(notice.body, "8% left until Mon 09:00.")
    }

    func testUsageNeverReportsANegativeRemainder() {
        XCTAssertEqual(usage(value: 104, tone: .critical).body, "0% left.")
    }

    func testUsageCarriesARingInItsToneAndItsProvidersThread() {
        let notice = usage(provider: .codex, window: "Week", value: 92, tone: .critical)
        XCTAssertEqual(notice.ring, .usage(value: 92, tone: .critical))
        XCTAssertEqual(notice.thread, "codex")
        XCTAssertEqual(notice.provider, .codex)
    }

    func testResetHasAnEmptyRingAndNamesTheNextReset() {
        let notice = NoticeWording.reset(
            provider: .claude, window: "Session", nextReset: now.addingTimeInterval(5 * 3600), now: now, locale: locale, timeZone: utc
        )
        XCTAssertEqual(notice.title, "Claude · Session reset")
        XCTAssertEqual(notice.body, "Fully available again. Next reset at 17:00.")
        XCTAssertEqual(notice.ring, .reset)
        XCTAssertEqual(notice.thread, "claude")
    }

    func testResetWithoutAKnownNextReset() {
        let notice = NoticeWording.reset(provider: .claude, window: "Week", nextReset: nil, now: now, locale: locale, timeZone: utc)
        XCTAssertEqual(notice.body, "Fully available again.")
    }

    func testSystemMessagesHaveNoRing() {
        let messages = [
            NoticeWording.status("Major outage"),
            NoticeWording.disconnected(),
            NoticeWording.appUpdate(version: "0.14.0"),
            NoticeWording.cliUpdate(latest: "2.1.0", installed: "2.0.9", command: "brew upgrade claude-code"),
            NoticeWording.test
        ]
        XCTAssertTrue(messages.allSatisfy { $0.ring == nil })
    }

    func testClaudeSystemMessagesStayInTheClaudeThread() {
        XCTAssertEqual(NoticeWording.status("Major outage").title, "Claude · Major outage")
        XCTAssertEqual(NoticeWording.status("Major outage").thread, "claude")
        XCTAssertEqual(NoticeWording.disconnected().title, "Claude · Disconnected")
        XCTAssertEqual(NoticeWording.disconnected().provider, .claude)
        XCTAssertEqual(NoticeWording.cliUpdate(latest: "2.1.0", installed: "2.0.9", command: "x").thread, "claude")
    }

    func testAppMessagesUseTheSparkThreadAndOpenNoTab() {
        let update = NoticeWording.appUpdate(version: "0.14.0")
        XCTAssertEqual(update.title, "Spark 0.14.0 is available")
        XCTAssertEqual(update.thread, "spark")
        XCTAssertNil(update.provider)
    }

    func testCLIUpdateNamesBothVersionsAndTheCommand() {
        let notice = NoticeWording.cliUpdate(latest: "2.1.0", installed: "2.0.9", command: "brew upgrade claude-code")
        XCTAssertEqual(notice.title, "Claude Code 2.1.0 is available")
        XCTAssertEqual(notice.body, "You have 2.0.9. Update with brew upgrade claude-code.")
    }
}

final class NotificationRingTests: XCTestCase {
    func testUsageRingFillsLikeTheMenuBarGlyph() {
        let ring = NotificationRing.usage(value: 45, tone: .normal)
        XCTAssertEqual(ring.opacities, MenuBarGlyph(value: 45, tone: .normal).opacities)
        XCTAssertEqual(ring.label, "45")
    }

    func testResetRingIsEmptyInkWithAZero() {
        XCTAssertEqual(NotificationRing.reset.opacities, MenuBarGlyph(value: 0, tone: .normal).opacities)
        XCTAssertFalse(NotificationRing.reset.opacities.contains(1))
        XCTAssertEqual(NotificationRing.reset.tone, .normal)
        XCTAssertEqual(NotificationRing.reset.label, "0")
    }

    func testRingTakesTheToneOfItsState() {
        XCTAssertEqual(NotificationRing.usage(value: 78, tone: .warning).tone, .warning)
        XCTAssertEqual(NotificationRing.usage(value: 92, tone: .critical).tone, .critical)
    }

    func testLabelRoundsAndClamps() {
        XCTAssertEqual(NotificationRing.usage(value: 77.6, tone: .warning).label, "78")
        XCTAssertEqual(NotificationRing.usage(value: 140, tone: .critical).label, "100")
    }

    func testRenderedImageIsAPNG() throws {
        let data = try XCTUnwrap(NotificationRing.usage(value: 78, tone: .warning).pngData(appearance: NSAppearance(named: .aqua)))
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
