import Foundation

/// Reasoning effort for a live session: the vocabulary both CLIs use and how
/// the session menu names it. Mirrors the server's `src/session-effort.ts`.
public enum SessionEffort {
    /// Every level either CLI has shipped, lowest first. Anything else from a
    /// host is dropped rather than offered.
    public static let known = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]

    public static func isKnown(_ level: String) -> Bool { known.contains(level) }

    /// What each CLI offers when the host can't say per model: Claude Code's
    /// `--effort` values, and the levels every current Codex model supports.
    public static func usualLevels(for agent: AgentKind) -> [String] {
        switch agent {
        case .claude: return ["low", "medium", "high", "xhigh", "max"]
        case .codex: return ["low", "medium", "high", "xhigh"]
        }
    }

    /// Menu label, matching the CLIs' own pickers ("Extra high" for xhigh).
    public static func displayName(_ level: String) -> String {
        switch level {
        case "xhigh": return "Extra high"
        default: return level.prefix(1).uppercased() + level.dropFirst()
        }
    }

    /// The Claude model family an alias or full id belongs to.
    static func claudeFamily(of model: String) -> String? {
        let lower = model.lowercased()
        return ["opus", "sonnet", "haiku", "fable"].first { lower.contains($0) }
    }
}
