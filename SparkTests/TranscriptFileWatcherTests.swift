import XCTest
@testable import Spark

final class TranscriptFileWatcherTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Exercises the real FSEvents mechanism end to end: a genuine write to a genuine file under
    /// the watched root must trigger the callback. This is an OS-boundary integration test rather
    /// than a pure unit test — there's no meaningful way to verify "FSEvents actually detects a
    /// change" without asking the real filesystem to report one.
    func testDetectsAWriteUnderTheWatchedRoot() throws {
        let expectation = expectation(description: "file change detected")
        // FSEvents can deliver more than one callback for a single write (e.g. separate
        // create/modify events); the test only needs to observe at least one.
        expectation.assertForOverFulfill = false
        let watcher = TranscriptFileWatcher(paths: [tempDir.path], latency: 0.1) {
            expectation.fulfill()
        }

        // FSEventStreamStart needs a moment to actually begin listening before the write happens,
        // or the write can race the stream's setup and be missed.
        Thread.sleep(forTimeInterval: 0.5)
        try "hello".write(to: tempDir.appendingPathComponent("test.jsonl"), atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 5)
        watcher.stop()
    }

    /// A subagent transcript sits two directory levels below a session file
    /// (`<sessionId>/subagents/agent-*.jsonl`) — FSEvents must still catch a write there, since
    /// it's the majority of transcript files on a real installation.
    func testDetectsAWriteInANestedSubagentDirectory() throws {
        let subagentsDir = tempDir
            .appendingPathComponent("session-id")
            .appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagentsDir, withIntermediateDirectories: true)

        let expectation = expectation(description: "nested file change detected")
        expectation.assertForOverFulfill = false
        let watcher = TranscriptFileWatcher(paths: [tempDir.path], latency: 0.1) {
            expectation.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.5)
        try "hello".write(to: subagentsDir.appendingPathComponent("agent-abc.jsonl"), atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 5)
        watcher.stop()
    }

    func testEmptyPathsDoesNotCrash() {
        let watcher = TranscriptFileWatcher(paths: [], latency: 0.1) {
            XCTFail("should never fire with no watched paths")
        }
        watcher.stop()
    }

    func testStoppingTwiceIsSafe() {
        let watcher = TranscriptFileWatcher(paths: [tempDir.path], latency: 0.1) {}
        watcher.stop()
        watcher.stop()
    }
}
