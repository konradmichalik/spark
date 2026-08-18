import CoreServices
import Foundation

/// Watches directory roots recursively for filesystem changes, using FSEvents — the only macOS
/// API that watches an entire directory tree without needing one file descriptor per file, which
/// matters here since a project's transcripts can number in the hundreds, including subagent
/// transcripts nested two levels deep under `<sessionId>/subagents/`. Coalesces rapid bursts of
/// writes (e.g. a streamed response landing as several near-simultaneous appends) into a single
/// callback via `latency`.
final class TranscriptFileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let latency: CFTimeInterval

    init(paths: [String], latency: CFTimeInterval = 2.0, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.latency = latency
        start(paths: paths)
    }

    deinit {
        stop()
    }

    private func start(paths: [String]) {
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<TranscriptFileWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            UInt32(kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(created)
    }

    /// Stops watching. Safe to call more than once (e.g. before sleep, then again from `deinit`).
    /// FSEvents streams don't survive a suspend/resume cycle cleanly, so this is always paired
    /// with re-arming a fresh watcher on wake rather than left running across it.
    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
