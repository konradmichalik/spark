import XCTest
@testable import Spark

final class ClaudeConfigDirectoryTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test")

    func testResolvesDefaultClaudeDirectoryWhenItExists() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: nil,
            homeDirectory: home,
            directoryExists: { $0.path == "/Users/test/.claude" }
        )
        XCTAssertEqual(resolution.roots.map(\.path), ["/Users/test/.claude"])
        XCTAssertEqual(resolution.primary?.path, "/Users/test/.claude")
    }

    func testFallsBackToConfigClaudeWhenDotClaudeMissing() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: nil,
            homeDirectory: home,
            directoryExists: { $0.path == "/Users/test/.config/claude" }
        )
        XCTAssertEqual(resolution.roots.map(\.path), ["/Users/test/.config/claude"])
    }

    func testEnvironmentVariableTakesPriorityOverDefaults() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: "/custom/claude-config",
            homeDirectory: home,
            directoryExists: { _ in true }
        )
        XCTAssertEqual(resolution.primary?.path, "/custom/claude-config")
    }

    func testEnvironmentVariableSupportsCommaSeparatedList() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: "/custom/a, /custom/b",
            homeDirectory: home,
            directoryExists: { _ in true }
        )
        XCTAssertEqual(
            resolution.roots.map(\.path),
            ["/custom/a", "/custom/b", "/Users/test/.claude", "/Users/test/.config/claude"]
        )
    }

    func testScansAllExistingRootsNotJustTheFirst() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: nil,
            homeDirectory: home,
            directoryExists: { _ in true }
        )
        XCTAssertEqual(resolution.roots.count, 2)
    }

    func testNoRootsResolvedWhenNoneExist() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: nil,
            homeDirectory: home,
            directoryExists: { _ in false }
        )
        XCTAssertTrue(resolution.roots.isEmpty)
        XCTAssertNil(resolution.primary)
    }

    func testBlankEnvironmentEntriesAreIgnored() {
        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: "/custom/a,,  ,/custom/b",
            homeDirectory: home,
            directoryExists: { _ in true }
        )
        XCTAssertEqual(resolution.roots.prefix(2).map(\.path), ["/custom/a", "/custom/b"])
    }

    func testDeduplicatesResolvedRootsAfterSymlinkResolution() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let realDir = tempDir.appendingPathComponent("real-claude")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let symlinkDir = tempDir.appendingPathComponent("symlink-claude")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: realDir)

        let resolution = ClaudeConfigDirectory.resolve(
            environmentValue: "\(symlinkDir.path),\(realDir.path)",
            homeDirectory: tempDir.appendingPathComponent("no-such-home")
        )

        XCTAssertEqual(resolution.roots.count, 1)
    }
}
