import XCTest
@testable import Spark

final class ExternalExportTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(views: [ExternalExportView] = []) -> ExternalExportFile {
        ExternalExportFile(app: "spark", displayName: "Spark", ttlSeconds: 300, views: views)
    }

    // MARK: - Serializer

    func testRoundTripsSchema() throws {
        let url = tempDir.appendingPathComponent("data.json")
        let view = ExternalExportView(
            id: "session",
            label: "Session",
            value: "68%",
            detail: "reset 16:00",
            progress: 0.68,
            state: .ok,
            trend: [1, 2, 3]
        )
        ExternalExportPersistence.write(makeFile(views: [view]), to: url)

        let decoded = try JSONDecoder().decode(ExternalExportFile.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded.schemaVersion, ExternalExportFile.currentSchemaVersion)
        XCTAssertEqual(decoded.app, "spark")
        XCTAssertEqual(decoded.displayName, "Spark")
        XCTAssertEqual(decoded.ttlSeconds, 300)
        XCTAssertEqual(decoded.views.first?.id, "session")
        XCTAssertEqual(decoded.views.first?.detail, "reset 16:00")
        XCTAssertEqual(decoded.views.first?.progress, 0.68)
        XCTAssertEqual(decoded.views.first?.state, .ok)
        XCTAssertEqual(decoded.views.first?.trend, [1, 2, 3])
    }

    func testEmptyStateStillEncodesValidJSON() throws {
        let url = tempDir.appendingPathComponent("data.json")
        let idleView = ExternalExportView(id: "active", label: "Active", value: "0", state: .idle)
        ExternalExportPersistence.write(makeFile(views: [idleView]), to: url)

        let decoded = try JSONDecoder().decode(ExternalExportFile.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded.views.first?.state, .idle)
        XCTAssertNil(decoded.views.first?.detail)
        XCTAssertNil(decoded.views.first?.trend)
    }

    // MARK: - Atomic write

    func testWriteLeavesNoStrayTempFile() {
        let url = tempDir.appendingPathComponent("data.json")
        ExternalExportPersistence.write(makeFile(), to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("tmp").path))
    }

    func testWrittenFileHasOwnerOnlyPermissions() throws {
        let url = tempDir.appendingPathComponent("data.json")
        ExternalExportPersistence.write(makeFile(), to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testSecondWriteReplacesFirstAtomically() throws {
        let url = tempDir.appendingPathComponent("data.json")
        ExternalExportPersistence.write(makeFile(views: [ExternalExportView(id: "a", label: "A", value: "1")]), to: url)
        ExternalExportPersistence.write(makeFile(views: [ExternalExportView(id: "b", label: "B", value: "2")]), to: url)

        let decoded = try JSONDecoder().decode(ExternalExportFile.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded.views.map(\.id), ["b"])
    }

    // MARK: - Delete

    func testDeleteRemovesFile() {
        let url = tempDir.appendingPathComponent("data.json")
        ExternalExportPersistence.write(makeFile(), to: url)

        ExternalExportPersistence.delete(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteIsANoOpWhenFileIsMissing() {
        let url = tempDir.appendingPathComponent("does-not-exist.json")

        ExternalExportPersistence.delete(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Error state

    func testWriteToMissingDirectoryDoesNotThrowOrCreateAnything() {
        let url = tempDir.appendingPathComponent("missing-subdir").appendingPathComponent("data.json")

        ExternalExportPersistence.write(makeFile(), to: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

// MARK: - ExternalExportBuilder

final class ExternalExportBuilderTests: XCTestCase {
    private func usageData(session: Double = 0, weekly: Double = 0) -> UsageData {
        UsageData(
            session: UsageBucket(utilization: session, resetsAt: nil),
            weekly: UsageBucket(utilization: weekly, resetsAt: nil),
            weeklySonnet: nil,
            weeklyOpus: nil,
            weeklyFable: nil,
            extraUsage: nil
        )
    }

    private func makeInput(
        usageData: UsageData? = nil,
        liveStats: LiveStats? = nil,
        activeSessions: [ActiveSession] = [],
        sessionTrend: [Double] = [],
        warningThreshold: Double = 75,
        criticalThreshold: Double = 90
    ) -> ExternalExportInput {
        ExternalExportInput(
            usageData: usageData ?? self.usageData(),
            liveStats: liveStats,
            activeSessions: activeSessions,
            sessionTrend: sessionTrend,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }

    func testStateIsOkBelowWarningThreshold() {
        let state = ExternalExportBuilder.state(for: 50, input: makeInput())
        XCTAssertEqual(state, .ok)
    }

    func testStateIsWarnAtWarningThreshold() {
        let state = ExternalExportBuilder.state(for: 75, input: makeInput())
        XCTAssertEqual(state, .warn)
    }

    func testStateIsCriticalAtCriticalThreshold() {
        let state = ExternalExportBuilder.state(for: 90, input: makeInput())
        XCTAssertEqual(state, .critical)
    }

    func testActiveViewIsIdleWhenNoSessions() {
        let views = ExternalExportBuilder.views(makeInput())

        let active = views.first { $0.id == "active" }
        XCTAssertEqual(active?.value, "0")
        XCTAssertEqual(active?.state, .idle)
    }

    func testActiveViewShowsCountAndNewestSessionName() {
        let session = ActiveSession(
            sessionId: "s1",
            projectKey: "proj",
            displayName: "my-project",
            lastActivity: Date()
        )
        let views = ExternalExportBuilder.views(makeInput(activeSessions: [session]))

        let active = views.first { $0.id == "active" }
        XCTAssertEqual(active?.value, "1")
        XCTAssertEqual(active?.detail, "my-project")
        XCTAssertEqual(active?.state, .ok)
    }

    func testSessionAndWeekReflectUtilizationAndThresholdState() {
        let views = ExternalExportBuilder.views(makeInput(usageData: usageData(session: 92, weekly: 40)))

        let session = views.first { $0.id == "session" }
        let week = views.first { $0.id == "week" }
        XCTAssertEqual(session?.value, "92%")
        XCTAssertEqual(session?.state, .critical)
        XCTAssertEqual(session?.progress, 0.92)
        XCTAssertEqual(week?.value, "40%")
        XCTAssertEqual(week?.state, .ok)
    }

    func testSessionTrendIsOmittedWhenEmptyButPresentOtherwise() {
        let emptyTrendViews = ExternalExportBuilder.views(makeInput(sessionTrend: []))
        XCTAssertNil(emptyTrendViews.first { $0.id == "session" }?.trend)

        let withTrendViews = ExternalExportBuilder.views(makeInput(sessionTrend: [12, 18, 24]))
        XCTAssertEqual(withTrendViews.first { $0.id == "session" }?.trend, [12, 18, 24])
    }

    func testTodayViewFallsBackWhenLiveStatsIsNil() {
        let views = ExternalExportBuilder.views(makeInput())

        let today = views.first { $0.id == "today" }
        XCTAssertEqual(today?.value, "0")
        XCTAssertNil(today?.detail)
    }

    func testTodayViewReflectsLiveStats() {
        let stats = LiveStats(
            period: .today,
            messageCount: 10,
            sessionCount: 3,
            inputTokens: 500_000,
            outputTokens: 500_000,
            cacheCreationTokens: 200_000,
            cacheReadTokens: 100_000
        )
        let views = ExternalExportBuilder.views(makeInput(liveStats: stats))

        let today = views.first { $0.id == "today" }
        XCTAssertEqual(today?.value, formatTokenCount(stats.realTokens))
        XCTAssertEqual(today?.detail, "3 sessions")
    }

    func testFileCarriesSchemaVersionAndTtl() {
        let file = ExternalExportBuilder.file(makeInput(), ttlSeconds: 360)

        XCTAssertEqual(file.schemaVersion, ExternalExportFile.currentSchemaVersion)
        XCTAssertEqual(file.app, "spark")
        XCTAssertEqual(file.ttlSeconds, 360)
        XCTAssertEqual(file.views.count, 4)
    }
}
