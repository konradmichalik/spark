import XCTest
@testable import Spark

final class TranscriptCacheTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory
    private var fileURL = FileManager.default.temporaryDirectory
    private var projectsDir = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        projectsDir = tempDir.appendingPathComponent("projects/-Users-me-app")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        fileURL = projectsDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func line(input: Int, output: Int, isoDate: String, messageId: String) -> String {
        """
        {"message":{"id":"\(messageId)","role":"assistant",\
        "usage":{"input_tokens":\(input),"output_tokens":\(output)}},\
        "timestamp":"\(isoDate)","requestId":"req_\(messageId)"}
        """
    }

    private func isoString(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600)))
    }

    @discardableResult
    private func writeAndCaptureAttributes(_ content: String, atomically: Bool = false) throws -> (mtime: Date, size: Int64) {
        try content.write(to: fileURL, atomically: atomically, encoding: .utf8)
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        // swiftlint:disable:next force_unwrapping
        return (values.contentModificationDate!, Int64(values.fileSize!))
    }

    private func resetModificationDate(_ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fileURL.path)
    }

    // MARK: - Unchanged file

    func testUnchangedFileIsNeverReopened() throws {
        try writeAndCaptureAttributes(line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n")
        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 100)

        // Corrupt the file's content without touching mtime/size — if the implementation
        // reopens it despite an unchanged cache entry, the corrupted (non-JSON) content fails
        // to decode and the total would drop to 0.
        let attrs = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let originalMtime = try XCTUnwrap(attrs.contentModificationDate)
        let originalSize = try XCTUnwrap(attrs.fileSize)
        try String(repeating: "X", count: originalSize).write(to: fileURL, atomically: false, encoding: .utf8)
        try resetModificationDate(originalMtime)

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 100, "unchanged mtime+size must reuse the cached bucket, not reread the file")
    }

    // MARK: - Appended file

    func testAppendedFileParsesOnlyTheNewByteRange() throws {
        let (originalMtime, originalSize) = try writeAndCaptureAttributes(
            line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n"
        )
        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 100)

        // Corrupt the original (already-cached) prefix in place, keeping it the same byte
        // length, then append a new valid line. If the implementation re-reads from the start
        // instead of resuming at the cached offset, the corrupted prefix fails to decode and
        // only the appended 10 would be counted.
        let corruptedPrefix = String(repeating: "X", count: Int(originalSize) - 1) + "\n"
        let appended = line(input: 10, output: 1, isoDate: isoString(daysAgo: 0), messageId: "b") + "\n"
        try (corruptedPrefix + appended).write(to: fileURL, atomically: false, encoding: .utf8)
        _ = originalMtime // mtime is expected to change here — the file genuinely grew.

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 110, "must merge cached prefix totals with freshly parsed suffix totals")
    }

    // MARK: - Truncated / rewritten file

    func testTruncatedOrRewrittenFileTriggersFullReparse() throws {
        try writeAndCaptureAttributes(
            line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n" +
            line(input: 200, output: 75, isoDate: isoString(daysAgo: 0), messageId: "b") + "\n"
        )
        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 300)

        // Replace with fresh, smaller content — a rewritten transcript, not an append.
        try (line(input: 5, output: 5, isoDate: isoString(daysAgo: 0), messageId: "c") + "\n")
            .write(to: fileURL, atomically: false, encoding: .utf8)

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 5, "a shrunk file must be fully reparsed, not merged with stale cached totals")
    }

    // MARK: - Dedup state persisted across incremental scans

    func testDuplicateMessageRequestIdPairStraddlingIncrementalScansIsCountedOnce() throws {
        try writeAndCaptureAttributes(
            line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n"
        )
        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 100)

        // Append a second usage-bearing entry sharing the same message id (and, per the fixture
        // helper, the same requestId) — the real duplicate-entry pattern Claude Code writes for
        // one streamed response. This second entry is parsed in a separate, later
        // `parseByteRange` call than the first, so it's only deduped correctly if dedup state
        // persists across incremental scans rather than resetting every call.
        let currentContent = try String(contentsOf: fileURL, encoding: .utf8)
        try (currentContent + line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n")
            .write(to: fileURL, atomically: false, encoding: .utf8)

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 100, "a duplicate (messageId, requestId) pair must be counted once across scans")
    }

    // MARK: - Unterminated trailing line

    func testUnterminatedTrailingLineIsNotCountedUntilComplete() throws {
        let completeLine = line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n"
        let incompleteLine = line(input: 20, output: 10, isoDate: isoString(daysAgo: 0), messageId: "b")
        // No trailing newline on the second line — simulates the writer being mid-flush on it.
        try writeAndCaptureAttributes(completeLine + incompleteLine)

        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 100, "an unterminated trailing line must not be counted yet")

        // The writer finishes flushing the line by appending the trailing newline.
        try (completeLine + incompleteLine + "\n").write(to: fileURL, atomically: false, encoding: .utf8)

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 120, "the now-complete line must be picked up on the next scan")
    }

    // MARK: - Lagging parsedByteOffset

    func testLaggingParsedByteOffsetIsRetriedDespiteMatchingMtimeAndSize() throws {
        try writeAndCaptureAttributes(
            line(input: 100, output: 50, isoDate: isoString(daysAgo: 0), messageId: "a") + "\n"
        )
        var store = TranscriptCacheStore.empty
        let first = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(first.input, 100)

        let path = try XCTUnwrap(store.files.keys.first)
        let cached = try XCTUnwrap(store.files[path])
        XCTAssertEqual(cached.parsedByteOffset, cached.size, "a full, up-to-date parse must record the offset at EOF")

        // Simulate a previous scan that recorded the file's current mtime/size but was
        // interrupted before it finished parsing (or before any buckets were merged in) —
        // parsedByteOffset is left short of size even though mtime/size already look "current".
        store.files[path] = FileParseCache(mtime: cached.mtime, size: cached.size, parsedByteOffset: 0, dailyBuckets: [:])

        let second = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(second.input, 100, "a lagging parsedByteOffset must be retried, not fast-pathed as already parsed")
        XCTAssertEqual(store.files[path]?.parsedByteOffset, store.files[path]?.size)
    }

    // MARK: - Period filtering from cache

    func testCutoffFiltersCachedDayBucketsWithoutReopeningTheFile() throws {
        let (originalMtime, _) = try writeAndCaptureAttributes(
            line(input: 100, output: 0, isoDate: isoString(daysAgo: 10), messageId: "old") + "\n" +
            line(input: 7, output: 0, isoDate: isoString(daysAgo: 0), messageId: "new") + "\n"
        )
        var store = TranscriptCacheStore.empty
        let all = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)
        XCTAssertEqual(all.input, 107)

        // Corrupt on disk without changing mtime/size, then re-aggregate with a narrower
        // cutoff. If this reopened the file, decoding the corrupted bytes would fail entirely.
        let size = try XCTUnwrap(try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try String(repeating: "X", count: size).write(to: fileURL, atomically: false, encoding: .utf8)
        try resetModificationDate(originalMtime)

        let today = TranscriptCache.aggregate(
            claudeDir: tempDir,
            cutoff: Calendar.current.startOfDay(for: Date()),
            store: &store
        )
        XCTAssertEqual(today.input, 7, "only today's cached bucket should be summed, purely from the existing cache")
    }

    func testUpperCutoffExcludesDayBucketsAfterIt() throws {
        try writeAndCaptureAttributes(
            line(input: 100, output: 0, isoDate: isoString(daysAgo: 10), messageId: "old") + "\n" +
            line(input: 20, output: 0, isoDate: isoString(daysAgo: 5), messageId: "middle") + "\n" +
            line(input: 7, output: 0, isoDate: isoString(daysAgo: 0), messageId: "new") + "\n"
        )
        var store = TranscriptCacheStore.empty

        let upToFiveDaysAgo = TranscriptCache.aggregate(
            claudeDir: tempDir,
            cutoff: nil,
            upperCutoff: Calendar.current.startOfDay(for: Date().addingTimeInterval(-5 * 24 * 3600)),
            store: &store
        )

        XCTAssertEqual(upToFiveDaysAgo.input, 120, "today's bucket is after the upper cutoff and must be excluded")
    }

    /// The combination production actually uses for a past week's live scan: both a lower and an
    /// upper bound at once, isolating a single middle bucket between two others.
    func testCutoffAndUpperCutoffTogetherIsolateOnlyTheMiddleBucket() throws {
        try writeAndCaptureAttributes(
            line(input: 100, output: 0, isoDate: isoString(daysAgo: 10), messageId: "old") + "\n" +
            line(input: 20, output: 0, isoDate: isoString(daysAgo: 5), messageId: "middle") + "\n" +
            line(input: 7, output: 0, isoDate: isoString(daysAgo: 0), messageId: "new") + "\n"
        )
        var store = TranscriptCacheStore.empty

        let onlyFiveDaysAgo = TranscriptCache.aggregate(
            claudeDir: tempDir,
            cutoff: Calendar.current.startOfDay(for: Date().addingTimeInterval(-6 * 24 * 3600)),
            upperCutoff: Calendar.current.startOfDay(for: Date().addingTimeInterval(-4 * 24 * 3600)),
            store: &store
        )

        XCTAssertEqual(onlyFiveDaysAgo.input, 20, "only the middle bucket falls within both bounds")
    }

    // MARK: - Persistence / schema version

    func testVersionMismatchDiscardsThePersistedStore() throws {
        let cacheFileURL = tempDir.appendingPathComponent("stale-cache.json")
        let staleStore = TranscriptCacheStore(schemaVersion: TranscriptCacheStore.currentSchemaVersion - 1, files: [
            "/some/path.jsonl": FileParseCache(mtime: Date(), size: 10, parsedByteOffset: 10, dailyBuckets: [:])
        ])
        try JSONEncoder().encode(staleStore).write(to: cacheFileURL)

        let loaded = TranscriptCachePersistence.load(from: cacheFileURL)

        XCTAssertTrue(loaded.files.isEmpty)
        XCTAssertEqual(loaded.schemaVersion, TranscriptCacheStore.currentSchemaVersion)
    }

    func testMatchingSchemaVersionIsPreserved() throws {
        let cacheFileURL = tempDir.appendingPathComponent("valid-cache.json")
        var store = TranscriptCacheStore.empty
        store.files["/some/path.jsonl"] = FileParseCache(
            mtime: Date(),
            size: 10,
            parsedByteOffset: 10,
            dailyBuckets: ["2026-01-01": DayAggregate(sessionIds: ["s1"], input: 5, output: 5, cacheCreation: 0, cacheRead: 0)]
        )
        TranscriptCachePersistence.save(store, to: cacheFileURL)

        let loaded = TranscriptCachePersistence.load(from: cacheFileURL)

        XCTAssertEqual(loaded, store)
    }

    func testMissingCacheFileReturnsEmptyStore() {
        let loaded = TranscriptCachePersistence.load(from: tempDir.appendingPathComponent("does-not-exist.json"))
        XCTAssertEqual(loaded, TranscriptCacheStore.empty)
    }

    // MARK: - Per-model breakdown

    private func line(input: Int, output: Int, isoDate: String, messageId: String, model: String) -> String {
        """
        {"message":{"id":"\(messageId)","role":"assistant","model":"\(model)",\
        "usage":{"input_tokens":\(input),"output_tokens":\(output)}},\
        "timestamp":"\(isoDate)","requestId":"req_\(messageId)"}
        """
    }

    func testPerModelBucketAttributesTokensToTheCorrectRawModelId() throws {
        let content = line(input: 100, output: 0, isoDate: isoString(daysAgo: 0), messageId: "a", model: "claude-opus-5") + "\n" +
            line(input: 30, output: 0, isoDate: isoString(daysAgo: 0), messageId: "b", model: "claude-sonnet-5") + "\n" +
            line(input: 20, output: 0, isoDate: isoString(daysAgo: 0), messageId: "c", model: "claude-opus-5") + "\n"
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.modelTotals["claude-opus-5"]?.total, 120)
        XCTAssertEqual(result.modelTotals["claude-sonnet-5"]?.total, 30)
    }

    func testSyntheticModelMarkerIsExcludedFromTheModelBreakdown() throws {
        let content = line(input: 100, output: 0, isoDate: isoString(daysAgo: 0), messageId: "a", model: "<synthetic>") + "\n"
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertTrue(result.modelTotals.isEmpty)
        XCTAssertEqual(result.input, 100, "the entry still counts toward overall totals — only the model breakdown excludes it")
    }

    func testPerModelRealExcludesCacheReadsButTotalIncludesThem() throws {
        let content = """
        {"message":{"id":"a","role":"assistant","model":"claude-opus-5",\
        "usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":2,"cache_read_input_tokens":1000}},\
        "timestamp":"\(isoString(daysAgo: 0))","requestId":"req_a"}\n
        """
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.modelTotals["claude-opus-5"]?.real, 17)
        XCTAssertEqual(result.modelTotals["claude-opus-5"]?.total, 1_017)
    }
}
