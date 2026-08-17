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

    func aggregate(claudeDir: URL, cutoff: Date?) -> TranscriptTotals {
        var current = store ?? TranscriptCachePersistence.load()
        let result = TranscriptCache.aggregate(claudeDir: claudeDir, cutoff: cutoff, store: &current)
        store = current
        TranscriptCachePersistence.save(current)
        return result
    }

    /// Every calendar day strictly before today, merged across every cached file's day buckets —
    /// the source data for permanent rollups. Reads whatever the cache currently holds (loading
    /// from disk if this is the first call this launch) without triggering a fresh scan; call
    /// `aggregate` first if the cache might be stale.
    func closedDayRollups(claudeDir: URL) -> [String: DayAggregate] {
        let current = store ?? TranscriptCachePersistence.load()
        let today = TranscriptCache.dayKey(for: Date())

        var merged: [String: DayAggregate] = [:]
        for file in current.files.values {
            for (day, bucket) in file.dailyBuckets where day < today {
                merged[day, default: DayAggregate()].merge(bucket)
            }
        }
        return merged
    }
}
