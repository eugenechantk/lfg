import Foundation

/// The Subagents pill above the composer (S2, canvas board `s2-view`):
/// a ring of done (green) and failed (red) work, then "1 running · 3/4 done".
public struct SubagentPill: Equatable, Sendable {
    public let total: Int
    public let runningCount: Int
    public let doneCount: Int
    public let failedCount: Int

    public init(agents: [ChildAgentSession]) {
        total = agents.count
        runningCount = agents.filter { $0.status == .running }.count
        failedCount = agents.filter { $0.status == .failed }.count
        // Stopped and unknown agents are over, so they count toward "done".
        doneCount = total - runningCount - failedCount
    }

    public var isEmpty: Bool { total == 0 }

    /// The green label, nil when nothing runs.
    public var running: String? { runningCount > 0 ? "\(runningCount) running" : nil }

    /// The grey tally. Finished = done + failed.
    public var progress: String {
        let tally = "\(doneCount + failedCount)/\(total) done"
        return running == nil ? tally : "· \(tally)"
    }

    public var doneFraction: Double { total == 0 ? 0 : Double(doneCount) / Double(total) }
    public var failedFraction: Double { total == 0 ? 0 : Double(failedCount) / Double(total) }

    public var accessibilityLabel: String {
        var parts: [String] = []
        if runningCount > 0 { parts.append("\(runningCount) running") }
        if doneCount > 0 { parts.append("\(doneCount) done") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return "Subagents: " + parts.joined(separator: ", ")
    }
}
