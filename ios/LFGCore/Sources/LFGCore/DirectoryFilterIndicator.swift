import Foundation

/// How the header's directory-filter button should read.
///
/// Split out because the two questions it answers are genuinely different and
/// were conflated: **is a filter configured** (does the list you are looking at
/// exclude anything by directory) versus **how much is it hiding right now**.
///
/// Keying the whole active state off the count made a configured filter
/// invisible whenever none of the hidden directories happened to have a running
/// session — which is most of the time, and exactly the case the button exists
/// to disclose. Mute `~/.gbrain` on Monday, come back on Friday with nothing
/// running there, and the button looks identical to "no filter" while the list
/// silently omits sessions.
public enum DirectoryFilterIndicator: Equatable, Sendable {
    /// No directories are muted — the list is showing everything.
    case off
    /// A filter is configured but currently hides no live session. Still active:
    /// the list is filtered, and closed/idle sessions may be missing from it.
    case active
    /// A filter is configured and is hiding this many live sessions right now.
    case activeWithCount(Int)

    /// - Parameters:
    ///   - hasHiddenDirectories: any directory is muted (literal path or pattern).
    ///   - hiddenLiveSessionCount: live sessions the mute list is hiding, after
    ///     the user/host filters — i.e. rows that would otherwise be on screen.
    public static func resolve(
        hasHiddenDirectories: Bool,
        hiddenLiveSessionCount: Int
    ) -> DirectoryFilterIndicator {
        guard hasHiddenDirectories else { return .off }
        return hiddenLiveSessionCount > 0 ? .activeWithCount(hiddenLiveSessionCount) : .active
    }

    /// Filled icon + accent tint. True for every configured filter, badge or not.
    public var isActive: Bool { self != .off }

    /// The number to badge, or nil when there is nothing live to count.
    public var badge: Int? {
        if case .activeWithCount(let n) = self { return n }
        return nil
    }
}
