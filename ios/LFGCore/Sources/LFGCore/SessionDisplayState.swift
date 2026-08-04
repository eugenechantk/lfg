import Foundation

/// The one precedence ladder for "what is this agent doing", client side.
///
/// This used to be written out three times — `SessionStore.group(for:)`,
/// `FleetActivitySnapshot.contentState`, and `fleetRowState` on the server — kept
/// in step by comment and code review. That is how the Live Activity once showed
/// ended sessions as "running" while the list beside it showed them correctly:
/// nothing failed, two hand-copied ladders simply drifted.
///
/// `sessionDisplayState` in `src/session-state.ts` is the server's copy of this
/// function, and `SessionDisplayStateTests` pins the two to the same table.
public enum SessionDisplayState: String, Sendable, CaseIterable {
    case needsInput
    case blocked
    case working
    case idle

    /// Order is load-bearing:
    ///
    /// - `needsInput` outranks everything. It is the only state that needs a
    ///   human, so it must survive Live Activity row truncation.
    /// - `blocked` outranks busy. Despite the UI's "Paused" label it means the
    ///   last assistant turn hit a genuine upstream API error — logged out, out of
    ///   credits, 401/403 (`computeStatus`, src/sessions.ts). Such a session makes
    ///   no progress AND asks nothing, so it is not "working".
    /// - `working` — a turn is in flight.
    ///
    /// `closed` is deliberately NOT part of this ladder. It is a fact about
    /// process ownership rather than about the turn, and only the client holds the
    /// cross-host live set needed to decide it — so callers layer it on top. Same
    /// for the list's device-local `unread`, which no other surface shares.
    public static func resolve(
        promptPresent: Bool,
        blocked: Bool,
        busy: Bool
    ) -> SessionDisplayState {
        if promptPresent { return .needsInput }
        if blocked { return .blocked }
        if busy { return .working }
        return .idle
    }
}
