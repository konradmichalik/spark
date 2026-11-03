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

    /// UserDefaults key carrying a requested view from the URL handler to the popover.
    static let pendingViewKey = "pendingPopoverView"

    /// The view id waiting from before the popover opened, removed so a request is applied once.
    static func takePendingView(from defaults: UserDefaults = .standard) -> String? {
        guard let id = defaults.string(forKey: pendingViewKey) else { return nil }
        defaults.removeObject(forKey: pendingViewKey)
        return id
    }

    /// Posted with the view id when a request arrives while the popover is already open.
    static let viewRequested = Notification.Name("SparkURLViewRequested")

    /// The export ids (`views[].id` in `data.json`) a URL may ask for.
    private static let viewIDs: Set<String> = ["session", "week", "today", "active"]

    /// The `view` of a `spark://show?view=<id>` URL, or nil when it is absent or not an export id.
    static func requestedView(_ url: URL) -> String? {
        guard isShowRequest(url),
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "view" })?.value?.lowercased(),
              viewIDs.contains(value)
        else { return nil }
        return value
    }

    /// Only `active` has its own screen; every other id shows on the overview.
    static func screen(forView id: String) -> PopoverScreen {
        id == "active" ? .sessions : .overview
    }
}
