import Foundation

/// How a provider's connection stands, for the status dot on its card in Settings > Connections.
enum ConnectionState: Equatable {
    case connected, expired, notFound, off
}

/// The status line under a provider's name: state, plan and sign-in path.
struct ConnectionLine: Equatable {
    let state: ConnectionState
    let text: String
}

enum ConnectionSummary {
    static func claude(isAuthenticated: Bool, needsReconnect: Bool, plan: String?, method: AuthMethod) -> ConnectionLine {
        if needsReconnect {
            return ConnectionLine(state: .expired, text: join(["Session expired", plan]))
        }
        guard isAuthenticated else { return ConnectionLine(state: .notFound, text: "Not connected") }
        return ConnectionLine(state: .connected, text: join(["Connected", plan, signInPath(method)]))
    }

    static func codex(isEnabled: Bool, isAvailable: Bool, needsSignIn: Bool, plan: String?) -> ConnectionLine {
        guard isEnabled else { return ConnectionLine(state: .off, text: "Off") }
        guard isAvailable else { return ConnectionLine(state: .notFound, text: "No ChatGPT sign-in found") }
        let chatGPTPlan = plan.map { "ChatGPT \($0)" }
        if needsSignIn {
            return ConnectionLine(state: .expired, text: join(["Sign-in expired", chatGPTPlan]))
        }
        return ConnectionLine(state: .connected, text: join(["Connected", chatGPTPlan, "via Codex CLI"]))
    }

    private static func signInPath(_ method: AuthMethod) -> String? {
        switch method {
        case .claudeCode: "via the keychain"
        case .longLivedToken: "via long-lived token"
        case .oauth: "via browser sign-in"
        case .none: nil
        }
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The value next to the menu bar ring. The raw values are the stored `menuBarValue` keys.
enum MenuBarValueOption: String, CaseIterable, SegmentLabeled {
    case max, session, weekly, none

    init(stored: String) {
        self = MenuBarValueOption(rawValue: stored) ?? .max
    }

    var segmentLabel: String {
        switch self {
        case .max: "Highest"
        case .session: "Session"
        case .weekly: "Week"
        case .none: "None"
        }
    }
}

/// Smart adapts the refresh rate to activity, fixed polls at one interval. Raw values are the
/// stored `refreshMode` keys.
enum RefreshModeOption: String, CaseIterable, SegmentLabeled {
    case smart, fixed

    var segmentLabel: String { self == .smart ? "Smart" : "Fixed" }
}

/// An interval choice in a segment row.
struct IntervalOption: SegmentLabeled {
    let seconds: TimeInterval
    let segmentLabel: String

    static let refresh = [
        IntervalOption(seconds: 300, segmentLabel: "5 min"),
        IntervalOption(seconds: 600, segmentLabel: "10 min"),
        IntervalOption(seconds: 1800, segmentLabel: "30 min")
    ]

    static let updateCheck = [
        IntervalOption(seconds: 3600, segmentLabel: "1h"),
        IntervalOption(seconds: 10_800, segmentLabel: "3h"),
        IntervalOption(seconds: 21_600, segmentLabel: "6h"),
        IntervalOption(seconds: 43_200, segmentLabel: "12h"),
        IntervalOption(seconds: 86_400, segmentLabel: "24h")
    ]

    /// The option for a stored interval, the first one when the stored value is not offered.
    static func matching(_ seconds: TimeInterval, in options: [IntervalOption]) -> IntervalOption {
        options.first { $0.seconds == seconds } ?? options[0]
    }
}
