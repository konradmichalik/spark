import XCTest
@testable import Spark

final class ActiveSessionsTests: XCTestCase {
    private let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cache(mtime: Date, cwd: String? = nil, contextTokens: Int? = nil) -> FileParseCache {
        FileParseCache(
            mtime: mtime,
            size: 10,
            parsedByteOffset: 10,
            dailyBuckets: [:],
            discoveredCwd: cwd,
            lastContextTokens: contextTokens
        )
    }

    private func path(project: String, sessionId: String) -> String {
        projectsDir.appendingPathComponent(project).appendingPathComponent("\(sessionId).jsonl").path
    }

    private func subagentPath(project: String, sessionId: String, agent: String) -> String {
        projectsDir
            .appendingPathComponent(project)
            .appendingPathComponent(sessionId)
            .appendingPathComponent("subagents")
            .appendingPathComponent("agent-\(agent).jsonl")
            .path
    }

    // MARK: - Window membership

    func testFileWithinWindowIsActive() {
        let sessionId = "11111111-1111-1111-1111-111111111111"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-60))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.map(\.sessionId), [sessionId])
    }

    func testFileOutsideWindowIsNotActive() {
        let sessionId = "22222222-2222-2222-2222-222222222222"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-301))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertTrue(sessions.isEmpty)
    }

    func testFutureMtimeBeyondClockSkewToleranceIsNotActive() {
        let sessionId = "33333333-3333-3333-3333-333333333333"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(61))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertTrue(sessions.isEmpty, "a future mtime beyond the clock-skew tolerance must not be treated as active")
    }

    // MARK: - Subagent attribution

    func testSubagentWriteKeepsParentSessionActiveWhileParentFileIsStale() {
        let sessionId = "44444444-4444-4444-4444-444444444444"
        let files = [
            path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-400)),
            subagentPath(project: "-Users-me-app", sessionId: sessionId, agent: "abc"): cache(mtime: now.addingTimeInterval(-10))
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.map(\.sessionId), [sessionId])
        XCTAssertEqual(sessions.first?.lastActivity, now.addingTimeInterval(-10))
    }

    func testParentFileCwdWinsOverSubagentCwdForDisplayName() {
        let sessionId = "55555555-5555-5555-5555-555555555555"
        let files = [
            path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-10), cwd: "/Users/me/app"),
            subagentPath(project: "-Users-me-app", sessionId: sessionId, agent: "abc"):
                cache(mtime: now.addingTimeInterval(-5), cwd: "/Users/me/app/subdir")
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.first?.displayName, "app")
        XCTAssertEqual(sessions.first?.cwd, "/Users/me/app", "the root file's cwd must win, since it's the authoritative one")
    }

    func testSessionWithoutAnyDiscoveredCwdExposesNilCwd() {
        let sessionId = "12121212-1212-1212-1212-121212121212"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-10))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertNil(sessions.first?.cwd, "no file in this session carried a discovered cwd yet")
    }

    // MARK: - Context tokens

    /// The subagent runs its own separate, smaller conversation — its context size is not the
    /// main conversation's, so it must never be shown as if it were.
    func testRootFileContextTokensWinOverSubagentContextTokens() {
        let sessionId = "13131313-1313-1313-1313-131313131313"
        let files = [
            path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-10), contextTokens: 142_000),
            subagentPath(project: "-Users-me-app", sessionId: sessionId, agent: "abc"):
                cache(mtime: now.addingTimeInterval(-5), contextTokens: 5_000)
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.first?.contextTokens, 142_000)
    }

    func testContextTokensIsNilWhenTheRootFileHasNoUsageYet() {
        let sessionId = "14141414-1414-1414-1414-141414141414"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-10))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertNil(sessions.first?.contextTokens)
    }

    // MARK: - Disambiguation

    func testTwoSessionsInTheSameProjectGetDisambiguatingSuffix() {
        let sessionA = "66666666-6666-6666-6666-666666666666"
        let sessionB = "77777777-7777-7777-7777-777777777777"
        let files = [
            path(project: "-Users-me-app", sessionId: sessionA): cache(mtime: now.addingTimeInterval(-10)),
            path(project: "-Users-me-app", sessionId: sessionB): cache(mtime: now.addingTimeInterval(-20))
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.displayName), ["app", "app"], "the project name itself must stay clean")
        XCTAssertEqual(sessions.compactMap(\.sessionIdSuffix), [String(sessionA.prefix(8)), String(sessionB.prefix(8))])
    }

    func testSingleSessionInAProjectHasNoDisambiguatingSuffix() {
        let sessionId = "88888888-8888-8888-8888-888888888888"
        let files = [path(project: "-Users-me-app", sessionId: sessionId): cache(mtime: now.addingTimeInterval(-10))]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.first?.displayName, "app")
        XCTAssertNil(sessions.first?.sessionIdSuffix, "a lone session in its project needs no disambiguation")
    }

    // MARK: - Unrecognized path shapes

    func testUnrecognizedPathShapeIsIgnored() {
        let files = [
            projectsDir.appendingPathComponent("orphan.jsonl").path: cache(mtime: now.addingTimeInterval(-10))
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - Sort order

    func testResultsAreSortedByMostRecentActivityFirstWithSessionIdTiebreak() {
        let sessionA = "99999999-9999-9999-9999-999999999999"
        let sessionB = "10101010-1010-1010-1010-101010101010"
        let sessionC = "20202020-2020-2020-2020-202020202020"
        let files = [
            path(project: "-Users-me-app", sessionId: sessionA): cache(mtime: now.addingTimeInterval(-10)),
            path(project: "-Users-me-other", sessionId: sessionB): cache(mtime: now.addingTimeInterval(-1)),
            path(project: "-Users-me-third", sessionId: sessionC): cache(mtime: now.addingTimeInterval(-1))
        ]

        let sessions = ActiveSessionResolver.resolve(files: files, projectsDirs: [projectsDir], now: now)

        XCTAssertEqual(sessions.map(\.sessionId), [sessionB, sessionC, sessionA])
    }

    // MARK: - Activity label

    /// A freshly-written session shows nothing at all rather than a label every row would repeat
    /// verbatim — the column only earns its place once a session starts aging.
    func testActivityLabelIsAbsentWhileTheSessionIsFresh() {
        let session = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(-5))
        XCTAssertNil(session.activityLabel(now: now))

        let futureSession = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(5))
        XCTAssertNil(futureSession.activityLabel(now: now), "negative elapsed must be clamped to zero, not shown")
    }

    /// The row's status dot colors by freshness, so this has to stay in lockstep with whether a
    /// label is shown — otherwise a row could show both an orange "still hot" dot and an elapsed
    /// time, which contradict each other.
    func testFreshnessTracksWhetherAnActivityLabelIsShown() {
        let fresh = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(-5))
        XCTAssertTrue(fresh.isFresh(now: now))
        XCTAssertNil(fresh.activityLabel(now: now))

        let aging = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(-45))
        XCTAssertFalse(aging.isFresh(now: now))
        XCTAssertNotNil(aging.activityLabel(now: now))
    }

    func testActivityLabelAppearsOnceTheSessionAges() {
        let seconds = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(-45))
        XCTAssertEqual(seconds.activityLabel(now: now), "45s")

        let minutes = ActiveSession(sessionId: "s", projectKey: "p", displayName: "p", lastActivity: now.addingTimeInterval(-190))
        XCTAssertEqual(minutes.activityLabel(now: now), "3m")
    }

    // MARK: - Integration: real fixture tree through TranscriptCache.aggregate

    /// Feeds the resolver the actual `store.files` a real scan produces, rather than a
    /// hand-built dictionary — this is where a path-resolution mismatch (e.g. `/var` vs
    /// `/private/var` on macOS temp dirs) would surface, since `resolve` re-derives session IDs
    /// from those exact keys.
    func testResolverWorksAgainstAStoreProducedByARealAggregateScan() throws {
        let tempClaudeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempClaudeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempClaudeDir) }

        let sessionId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let transcriptURL = tempClaudeDir
            .appendingPathComponent("projects/-Users-me-app/\(sessionId).jsonl")
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"message":{"role":"user"},"timestamp":"2026-01-01T00:00:00Z","sessionId":"\(sessionId)","cwd":"/Users/me/app"}\n
        """.write(to: transcriptURL, atomically: true, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        _ = TranscriptCache.aggregate(claudeDir: tempClaudeDir, cutoff: nil, store: &store)

        let resolvedProjectsDir = TranscriptCache.resolvedPath(tempClaudeDir.appendingPathComponent("projects"))
        let sessions = ActiveSessionResolver.resolve(files: store.files, projectsDirs: [resolvedProjectsDir])

        XCTAssertEqual(sessions.map(\.sessionId), [sessionId])
        XCTAssertEqual(sessions.first?.displayName, "app")
    }
}
