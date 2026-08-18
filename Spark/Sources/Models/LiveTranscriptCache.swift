import Foundation

// MARK: - Persistence

enum TranscriptCachePersistence {
    static var defaultFileURL: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transcript-cache.json")
    }

    static func load(from url: URL = defaultFileURL) -> TranscriptCacheStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(TranscriptCacheStore.self, from: data),
              store.schemaVersion == TranscriptCacheStore.currentSchemaVersion else {
            return .empty
        }
        return store
    }

    static func save(_ store: TranscriptCacheStore, to url: URL = defaultFileURL) {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Concurrency-safe production entry point

/// Serializes access to the shared in-memory + on-disk cache so overlapping stats refreshes
/// (e.g. a rapid period switch while a broader-period scan is still running) can't race on it.
actor LiveTranscriptCache {
    static let shared = LiveTranscriptCache()

    private var store: TranscriptCacheStore?

    // swiftlint:disable large_tuple
    func aggregate(
        claudeDirs: [URL],
        cutoff: Date?
    ) -> (sessionIds: Set<String>, input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        // swiftlint:enable large_tuple
        var current = store ?? TranscriptCachePersistence.load()

        var sessionIds: Set<String> = []
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0

        for claudeDir in claudeDirs {
            let result = TranscriptCache.aggregate(claudeDir: claudeDir, cutoff: cutoff, store: &current)
            sessionIds.formUnion(result.sessionIds)
            totalInput += result.input
            totalOutput += result.output
            totalCacheCreation += result.cacheCreation
            totalCacheRead += result.cacheRead
        }

        store = current
        TranscriptCachePersistence.save(current)
        return (sessionIds, totalInput, totalOutput, totalCacheCreation, totalCacheRead)
    }
}
