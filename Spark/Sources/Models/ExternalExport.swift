import Darwin
import Foundation

// MARK: - External Export Schema
//
// A generic, versioned snapshot of the app's already-computed state, written to
// `data.json` for external consumers (e.g. a Stream Deck plugin) to read. The contract is
// deliberately identical across the author's other menu bar apps, so a consumer needs no
// per-app code — only `app` differs.

enum ExternalExportState: String, Codable, Equatable, Sendable {
    case ok, warn, critical, idle
}

struct ExternalExportView: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    var detail: String?
    var progress: Double?
    var state: ExternalExportState?
    var trend: [Double]?
}

struct ExternalExportFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let app: String
    let displayName: String
    let updatedAt: String
    let ttlSeconds: Int
    let views: [ExternalExportView]

    init(
        schemaVersion: Int = ExternalExportFile.currentSchemaVersion,
        app: String,
        displayName: String,
        updatedAt: Date = Date(),
        ttlSeconds: Int,
        views: [ExternalExportView]
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.displayName = displayName
        self.updatedAt = ISO8601DateFormatter().string(from: updatedAt)
        self.ttlSeconds = ttlSeconds
        self.views = views
    }
}

// MARK: - Persistence

/// Writes/removes `data.json` for external consumers. Both operations fail silently: a write
/// a consumer can't yet see, or a delete of a file that's already gone, are not error
/// conditions worth surfacing anywhere in the UI.
enum ExternalExportPersistence {
    /// Writes atomically: encodes to a `.tmp` sibling, restricts it to owner-only permissions
    /// (the payload can contain project/session names), then `rename()`s it over the target so a
    /// concurrently-reading consumer never observes a partially written file.
    static func write(_ file: ExternalExportFile, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }

        let tempURL = url.appendingPathExtension("tmp")
        // Permissions are set at creation, not via a follow-up `setAttributes` call, so the file
        // is never briefly world-readable between being written and being restricted.
        let created = FileManager.default.createFile(
            atPath: tempURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        guard created, rename(tempURL.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
    }

    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - View Builder

/// Pure mapping from already-computed app state to the export schema — kept separate from
/// `AppState` (rather than as private methods there) so it's directly unit-testable, mirroring
/// `ActiveSessionResolver`/`SessionProjection`.
struct ExternalExportInput {
    let usageData: UsageData
    let liveStats: LiveStats?
    let activeSessions: [ActiveSession]
    let sessionTrend: [Double]
    let warningThreshold: Double
    let criticalThreshold: Double
}

enum ExternalExportBuilder {
    static func file(_ input: ExternalExportInput, ttlSeconds: Int) -> ExternalExportFile {
        ExternalExportFile(
            app: "spark",
            displayName: "Spark",
            ttlSeconds: ttlSeconds,
            views: views(input)
        )
    }

    static func views(_ input: ExternalExportInput) -> [ExternalExportView] {
        let usageData = input.usageData
        let liveStats = input.liveStats
        let activeSessions = input.activeSessions

        return [
            ExternalExportView(
                id: "session",
                label: "Session",
                value: "\(Int(usageData.sessionUtilization))%",
                detail: usageData.session?.timeUntilReset.map { "resets \($0)" },
                progress: usageData.sessionUtilization / 100,
                state: state(for: usageData.sessionUtilization, input: input),
                trend: input.sessionTrend.isEmpty ? nil : input.sessionTrend
            ),
            ExternalExportView(
                id: "week",
                label: "Woche",
                value: "\(Int(usageData.weeklyUtilization))%",
                detail: usageData.weekly?.timeUntilReset.map { "resets \($0)" },
                progress: usageData.weeklyUtilization / 100,
                state: state(for: usageData.weeklyUtilization, input: input)
            ),
            ExternalExportView(
                id: "today",
                label: "Heute",
                value: liveStats.map { formatTokenCount($0.realTokens) } ?? "0",
                detail: liveStats.map { "\($0.sessionCount) sessions" }
            ),
            ExternalExportView(
                id: "active",
                label: "Aktiv",
                value: "\(activeSessions.count)",
                detail: activeSessions.first?.displayName,
                state: activeSessions.isEmpty ? .idle : .ok
            )
        ]
    }

    static func state(for utilization: Double, input: ExternalExportInput) -> ExternalExportState {
        if utilization >= input.criticalThreshold { return .critical }
        if utilization >= input.warningThreshold { return .warn }
        return .ok
    }
}
