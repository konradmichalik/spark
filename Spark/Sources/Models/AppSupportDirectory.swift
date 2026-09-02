import Foundation

/// The app's own `Application Support/Spark/` directory — shared by every persisted file
/// (`history.json`, `transcript-cache.json`, `data.json`), each of which only needs its own
/// filename appended.
enum AppSupportDirectory {
    static var spark: URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Spark")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
