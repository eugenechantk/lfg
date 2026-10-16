import Foundation

/// One row of the S2 Subagents sheet (board `s2-subagents`): a status mark,
/// the task, "Running" or the result, then "general-purpose · 1m 12s".
public struct SubagentRow: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case running, done, failed, stopped }
    /// How the second line reads: green while running, red on failure.
    public enum Tone: Equatable, Sendable { case live, result, failed, secondary }

    public let mark: Mark
    public let title: String
    public let line: String
    public let tone: Tone
    public let meta: String

    public init(_ agent: ChildAgentSession, nowMs: Double) {
        title = agent.description
        let result = agent.result.flatMap { $0.isEmpty ? nil : $0 }
        switch agent.status {
        case .running:
            mark = .running; line = "Running"; tone = .live
        case .completed:
            mark = .done; line = result ?? "Done"; tone = .result
        case .failed:
            mark = .failed; line = result ?? "Failed"; tone = .failed
        case .stopped:
            mark = .stopped; line = result ?? "Stopped"; tone = .secondary
        case .unknown:
            mark = .stopped; line = "Status unknown"; tone = .secondary
        }
        var parts = [agent.agentType]
        if let start = agent.startedAt {
            let end = agent.status == .running ? nowMs : (agent.finishedAt ?? agent.lastActivityAt ?? nowMs)
            parts.append(Self.duration(ms: end - start))
        }
        meta = parts.joined(separator: " · ")
    }

    /// "48s", "1m 12s", "2m 05s" (board `s2-subagents`).
    public static func duration(ms: Double) -> String {
        let seconds = max(0, Int((ms / 1000).rounded()))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: "%dm %02ds", minutes, seconds % 60) }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}

extension SubagentPill {
    /// The Subagents sheet's line under its title: "1 running · 2 done · 1 failed".
    public var sheetSummary: String {
        var parts: [String] = []
        if runningCount > 0 { parts.append("\(runningCount) running") }
        if doneCount > 0 { parts.append("\(doneCount) done") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return parts.joined(separator: " · ")
    }
}
