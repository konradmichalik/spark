import XCTest
@testable import Spark

final class ProjectBreakdownTests: XCTestCase {

    // MARK: - Pure path -> project key derivation

    func testProjectKeyIsFirstPathComponentAfterProjectsDir() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir
            .appendingPathComponent("-Users-me-app")
            .appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")

        XCTAssertEqual(
            TranscriptCache.projectKey(forTranscriptAt: transcript, projectsDir: projectsDir),
            "-Users-me-app"
        )
    }

    func testProjectKeyForSubagentTranscriptIsSameAsParentSession() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir
            .appendingPathComponent("-Users-me-app")
            .appendingPathComponent("11111111-1111-1111-1111-111111111111")
            .appendingPathComponent("subagents")
            .appendingPathComponent("agent-abc.jsonl")

        XCTAssertEqual(
            TranscriptCache.projectKey(forTranscriptAt: transcript, projectsDir: projectsDir),
            "-Users-me-app"
        )
    }

    func testProjectKeyIsNilForAFileDirectlyUnderProjectsDir() {
        let projectsDir = URL(fileURLWithPath: "/home/.claude/projects")
        let transcript = projectsDir.appendingPathComponent("orphan.jsonl")

        XCTAssertNil(TranscriptCache.projectKey(forTranscriptAt: transcript, projectsDir: projectsDir))
    }

    // MARK: - Full scan against a real fixture tree

    private var tempDir = FileManager.default.temporaryDirectory
    private var projectDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        projectDir = tempDir.appendingPathComponent("projects/-Users-me-app")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func line(input: Int, messageId: String, cwd: String? = nil) -> String {
        let cwdField = cwd.map { ",\"cwd\":\"\($0)\"" } ?? ""
        return """
        {"message":{"id":"\(messageId)","role":"assistant",\
        "usage":{"input_tokens":\(input),"output_tokens":0}},\
        "timestamp":"\(ISO8601DateFormatter().string(from: Date()))","requestId":"req_\(messageId)"\(cwdField)}
        """
    }

    func testProjectTotalsAttributeTokensToTheEncodedProjectDirectory() throws {
        let fileURL = projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        try (line(input: 100, messageId: "a") + "\n").write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.projectTotals["-Users-me-app"]?.total, 100)
    }

    func testProjectDisplayNameIsResolvedFromCwd() throws {
        let fileURL = projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        try (line(input: 10, messageId: "a", cwd: "/Users/konrad/dev/typo3-routing") + "\n")
            .write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.projectDisplayNames["-Users-me-app"], "/Users/konrad/dev/typo3-routing")
    }

    func testProjectDisplayNameIsAbsentWhenNoCwdEverAppears() throws {
        let fileURL = projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        try (line(input: 10, messageId: "a") + "\n").write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertNil(result.projectDisplayNames["-Users-me-app"])
    }

    func testProjectDisplayNameSurvivesAnIncrementalRescanThatFindsNoNewCwd() throws {
        // The resolved name was captured on the initial parse; a later incremental append with
        // no cwd field in the new lines must not clear it.
        let fileURL = projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        try (line(input: 10, messageId: "a", cwd: "/Users/konrad/dev/typo3-routing") + "\n")
            .write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        _ = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        try handle.write(contentsOf: Data((line(input: 5, messageId: "b") + "\n").utf8))
        try handle.close()

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(second.projectDisplayNames["-Users-me-app"], "/Users/konrad/dev/typo3-routing")
        XCTAssertEqual(second.projectTotals["-Users-me-app"]?.total, 15)
    }

    func testProjectRealExcludesCacheReadsButTotalIncludesThem() throws {
        let fileURL = projectDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
        let content = """
        {"message":{"id":"a","role":"assistant",\
        "usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2,"cache_read_input_tokens":1000}},\
        "timestamp":"\(ISO8601DateFormatter().string(from: Date()))","requestId":"req_a"}\n
        """
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.projectTotals["-Users-me-app"]?.real, 17)
        XCTAssertEqual(result.projectTotals["-Users-me-app"]?.total, 1_017)
    }
}
