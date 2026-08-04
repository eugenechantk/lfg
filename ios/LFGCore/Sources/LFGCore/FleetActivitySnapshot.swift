import Foundation

/// Reduces `SessionStore`'s live state into the single aggregate Live Activity
/// content state. Pure so it can be unit-tested without ActivityKit, and shared
/// by the app-driven controller and (in shape) the server's push reducer.
public enum FleetActivitySnapshot {
    /// How many rows the lock-screen card renders before folding the rest into
    /// "N More". The lock screen is a fixed ~160pt frame that *center-clips*
    /// overheight content — which silently drops the header — so this is a
    /// height budget, not a style choice.
    public static let maxRows = 3

    public static func contentState(
        sessions: [Session],
        busy: [String: Bool],
        prompts: [String: AgentPrompt],
        priorRows: [LFGFleetAttributes.Row] = [],
        now: Double
    ) -> LFGFleetAttributes.ContentState {
        // Keyed by session *and* state so that a session changing state restarts
        // its timer, rather than inheriting the elapsed time of its previous one.
        let priorBySessionAndState = Dictionary(
            priorRows.map { (rowKey(sid: $0.sid, state: $0.state), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var working = 0
        var needsInput = 0
        var rows: [LFGFleetAttributes.Row] = []

        for session in sessions {
            let sid = session.sessionId ?? session.id
            let state: String

            // This ladder MUST mirror `SessionStore.group(for:)`'s precedence, or
            // the card contradicts the list the user is looking at. Two traps live
            // in the order:
            //
            //  - `closed` is checked FIRST and is client-synthesized (the server
            //    never sends it). `busy` is seeded only for *live* sessions and is
            //    never cleared when one closes, so a session that was working when
            //    you ended it keeps `busy == true` forever. Without this guard it
            //    renders as "working" permanently.
            //  - `isBlocked` ("Paused") outranks busy and is neither working nor
            //    needs-input, so it does not belong on the card at all.
            if session.closed { continue }

            if prompts[sid] != nil {
                state = "needsInput"
                needsInput += 1
            } else if session.isBlocked {
                continue
            } else if busy[sid] == true {
                state = "working"
                working += 1
            } else {
                // Idle. Never shown — which is also why there is no "unread"
                // count here: unread is a property of idle sessions.
                continue
            }

            let prior = priorBySessionAndState[rowKey(sid: sid, state: state)]
            rows.append(
                LFGFleetAttributes.Row(
                    sid: sid,
                    title: session.title.isEmpty ? fallbackTitle(for: sid) : session.title,
                    state: state,
                    since: prior?.since ?? now
                )
            )
        }

        // Needs-input first so the actionable sessions survive truncation, then
        // oldest-first within a state.
        let ordered = rows.sorted { lhs, rhs in
            let lhsRank = rowRank(lhs.state)
            let rhsRank = rowRank(rhs.state)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.since != rhs.since { return lhs.since < rhs.since }
            return lhs.sid < rhs.sid
        }

        return LFGFleetAttributes.ContentState(
            working: working,
            needsInput: needsInput,
            rows: Array(ordered.prefix(maxRows)),
            more: max(0, ordered.count - maxRows),
            updatedAt: now
        )
    }

    private static func rowKey(sid: String, state: String) -> String {
        "\(sid)\u{0}\(state)"
    }

    private static func rowRank(_ state: String) -> Int {
        state == "needsInput" ? 0 : 1
    }

    private static func fallbackTitle(for sid: String) -> String {
        if sid.isEmpty { return "Session" }
        return String(sid.prefix(8))
    }
}
