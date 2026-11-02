import Foundation

/// The `spark://` URLs other tools can open. Kept apart from `AppDelegate` so it is directly unit-testable.
enum SparkURL {
    static let scheme = "spark"

    /// `spark://show`, with or without a trailing slash. Anything else is ignored.
    static func isShowRequest(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == "show"
            && ["", "/"].contains(url.path)
    }
}
