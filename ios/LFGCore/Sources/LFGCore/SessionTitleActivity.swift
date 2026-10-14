import Foundation

/// The in-flight activity a session's title bar shows under its title, with a
/// spinner. One line has room for one activity, so the precedence lives here
/// instead of in the view's `if/else` chain.
public enum SessionTitleActivity: Equatable, Sendable {
    /// A cross-provider model switch, with its already-worded status.
    case modelSwitch(String)
    /// A fork request is running. The fork lands as a new session, which the
    /// app then opens — until then this is the only sign anything happened.
    case forking
    case movingHost
    case running

    public var label: String {
        switch self {
        case .modelSwitch(let status): status
        case .forking: "Forking…"
        case .movingHost: "Moving host…"
        case .running: "Running"
        }
    }

    /// User-started actions outrank the turn's own `busy`: a fork or move is
    /// what the user just asked for, while "Running" is background state.
    public static func resolve(
        modelSwitchStatus: String?,
        forking: Bool,
        movingHost: Bool,
        busy: Bool
    ) -> SessionTitleActivity? {
        if let modelSwitchStatus { return .modelSwitch(modelSwitchStatus) }
        if forking { return .forking }
        if movingHost { return .movingHost }
        if busy { return .running }
        return nil
    }
}
