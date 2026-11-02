import XCTest
@testable import Spark

final class TranscriptCacheModelTests: XCTestCase {
    private var tempDir = FileManager.default.temporaryDirectory
    private var fileURL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectsDir = tempDir.appendingPathComponent("projects/-Users-me-app")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        fileURL = projectsDir.appendingPathComponent("11111111-1111-1111-1111-111111111111.jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func isoString(daysAgo: Int) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(-daysAgo * 24 * 3600)))
    }

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

    func testPerModelTotalsKeepTheOneHourShareOfCacheWrites() throws {
        let content = """
        {"message":{"id":"a","role":"assistant","model":"claude-opus-5",\
        "usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":300,"cache_read_input_tokens":0,\
        "cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":200}}},\
        "timestamp":"\(isoString(daysAgo: 0))","requestId":"req_a"}
        {"message":{"id":"b","role":"assistant","model":"claude-opus-5",\
        "usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":50,"cache_read_input_tokens":0}},\
        "timestamp":"\(isoString(daysAgo: 0))","requestId":"req_b"}\n
        """
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        let totals = try XCTUnwrap(result.modelTotals["claude-opus-5"])
        XCTAssertEqual(totals.cacheCreation, 350, "the 1h share is a subset, not added on top")
        XCTAssertEqual(totals.cacheCreation1h, 200, "an entry without the breakdown counts as 5m")
        XCTAssertEqual(totals.total, 365)
    }

    func testOneHourShareNeverExceedsTheCacheWriteTotal() throws {
        let content = """
        {"message":{"id":"a","role":"assistant","model":"claude-opus-5",\
        "usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,\
        "cache_creation":{"ephemeral_1h_input_tokens":200}}},\
        "timestamp":"\(isoString(daysAgo: 0))","requestId":"req_a"}\n
        """
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.modelTotals["claude-opus-5"]?.cacheCreation1h, 0)
    }

    func testProjectModelTotalsSplitEachProjectByModel() throws {
        let content = line(input: 100, output: 0, isoDate: isoString(daysAgo: 0), messageId: "a", model: "claude-opus-5") + "\n" +
            line(input: 30, output: 0, isoDate: isoString(daysAgo: 0), messageId: "b", model: "claude-sonnet-5") + "\n"
        try content.write(to: fileURL, atomically: false, encoding: .utf8)

        var store = TranscriptCacheStore.empty
        let result = TranscriptCache.aggregate(claudeDir: tempDir, cutoff: nil, store: &store)

        XCTAssertEqual(result.projectModelTotals["-Users-me-app"]?["claude-opus-5"]?.input, 100)
        XCTAssertEqual(result.projectModelTotals["-Users-me-app"]?["claude-sonnet-5"]?.input, 30)
    }
}
