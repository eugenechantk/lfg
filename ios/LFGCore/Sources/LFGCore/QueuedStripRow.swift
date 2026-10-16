import Foundation

/// One row of the soft strip above the composer (S2, boards `s2-queued` and
/// `s2-queued-failed`): its icon, its tag, and the menu that opens at the row.
public struct QueuedStripRow: Equatable, Sendable {
    public enum Icon: Equatable, Sendable { case spinner, clock, failed }

    public enum Action: Equatable, Sendable {
        case sendNow, trySendingNow, retry, edit, remove, delete

        public var title: String {
            switch self {
            case .sendNow: "Send now"
            case .trySendingNow: "Try sending now"
            case .retry: "Retry"
            case .edit: "Edit"
            case .remove: "Remove"
            case .delete: "Delete"
            }
        }

        public var subtitle: String? { self == .sendNow ? "Stops the current step first" : nil }
        public var isDestructive: Bool { self == .remove || self == .delete }
    }

    public let icon: Icon
    /// "Queued" or "Not sent", after the text. Nil for a plain queued row.
    public let tag: String?
    public let tagIsError: Bool
    public let actions: [Action]
    /// Why the menu is short: the agent already holds the message.
    public let menuNote: String?
    public let accessibilityLabel: String

    /// `serverStatus` is the host's queue status for this message: `pending`
    /// while lfg holds it, `queued` once the agent has it in its own queue
    /// (the host then refuses removal, so Edit and Remove would fail).
    public init(failed: Bool, queuedOffline: Bool, queuedForResume: Bool,
                serverStatus: String?, agent: String) {
        if failed {
            icon = .failed; tag = "Not sent"; tagIsError = true
            actions = [.retry, .edit, .delete]; menuNote = nil
            accessibilityLabel = "Message not sent. Options"
            return
        }
        tagIsError = false
        accessibilityLabel = "Queued message options"
        if queuedOffline {
            icon = .clock; tag = "Queued"
            actions = [.trySendingNow, .edit, .remove]; menuNote = nil
        } else if queuedForResume {
            icon = .spinner; tag = "Queued"
            actions = [.remove]; menuNote = nil
        } else if serverStatus == "queued" {
            icon = .spinner; tag = nil
            actions = [.sendNow]
            menuNote = "Already with \(agent == "codex" ? "Codex" : "Claude")"
        } else {
            icon = .spinner; tag = nil
            actions = [.sendNow, .edit, .remove]; menuNote = nil
        }
    }
}
