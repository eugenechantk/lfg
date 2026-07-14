import Foundation

public enum FleetActivitySnapshot {
    public static func contentState(
        sessions: [Session],
        busy: [String: Bool],
        prompts: [String: AgentPrompt],
        hosts: [Host],
        hostBySession: [String: String],
        reachabilityByHost: [String: Reachability],
        priorRows: [LFGFleetAttributes.Row] = [],
        now: Double
    ) -> LFGFleetAttributes.ContentState {
        let hostsById = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0) })
        let priorBySessionAndState = Dictionary(
            uniqueKeysWithValues: priorRows.map { (rowKey(sid: $0.sid, state: $0.state), $0) }
        )

        var working = 0
        var needsInput = 0
        var rows: [LFGFleetAttributes.Row] = []

        for session in sessions {
            let sid = session.sessionId ?? session.id
            let state: String
            if prompts[sid] != nil {
                state = "blocked"
                needsInput += 1
            } else if busy[sid] == true {
                state = "working"
                working += 1
            } else {
                state = "idle"
            }

            guard state != "idle" else { continue }
            let host = hostBySession[sid].flatMap { hostsById[$0] }
            let prior = priorBySessionAndState[rowKey(sid: sid, state: state)]
            rows.append(
                LFGFleetAttributes.Row(
                    sid: sid,
                    title: session.title.isEmpty ? fallbackTitle(for: sid) : session.title,
                    host: host?.label ?? "lfg",
                    state: state,
                    since: prior?.since ?? now
                )
            )
        }

        let orderedRows = rows
            .sorted { lhs, rhs in
                let lhsRank = rowRank(lhs.state)
                let rhsRank = rowRank(rhs.state)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.since != rhs.since { return lhs.since < rhs.since }
                return lhs.sid < rhs.sid
            }
            .prefix(3)

        return LFGFleetAttributes.ContentState(
            working: working,
            needsInput: needsInput,
            rows: Array(orderedRows),
            hosts: hosts.map { host in
                LFGFleetAttributes.ContentState.HostStatus(
                    name: host.label,
                    online: reachabilityByHost[host.id] == .ok
                )
            },
            updatedAt: now
        )
    }

    private static func rowKey(sid: String, state: String) -> String {
        "\(sid)\u{0}\(state)"
    }

    private static func rowRank(_ state: String) -> Int {
        switch state {
        case "blocked": return 0
        case "working": return 1
        default: return 2
        }
    }

    private static func fallbackTitle(for sid: String) -> String {
        if sid.isEmpty { return "Session" }
        return String(sid.prefix(8))
    }
}
