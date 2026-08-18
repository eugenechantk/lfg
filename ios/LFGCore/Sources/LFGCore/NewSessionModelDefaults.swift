import Foundation

// MARK: - Per-directory agent/model default

extension AgentModelSelection {
    /// The agent/model a new session in `cwd` should default to, inferred from the
    /// newest session that directory already has.
    ///
    /// The globally-remembered pair (`AppSettings.lastNewSessionModelSelection`) is
    /// the wrong default the moment you work across projects with different
    /// runtimes: start one codex session in repo A and every new session in repo B
    /// silently proposes codex too. A directory, by contrast, is a strong signal —
    /// the work in it has a runtime, and the last session there is the best
    /// available statement of what it is.
    ///
    /// Two tiers, because a session can be known without its model being known:
    ///
    /// 1. The newest session in `cwd` whose model is readable — that pair, resolved
    ///    through `restoring` so a retired catalog entry degrades to the agent's
    ///    current default rather than leaking into a create request.
    /// 2. Failing that, the newest session in `cwd` with a recognizable agent, on
    ///    that agent's default model. A transcript with no assistant turn (or a
    ///    server too old to report `model` on closed rows) still tells us the
    ///    runtime, and "codex on its default model" beats "claude" for a codex
    ///    directory.
    ///
    /// Falls back to `fallback` when the directory has no usable history at all.
    ///
    /// Matching is on the exact directory, with only trailing slashes normalized —
    /// deliberately no ancestor walk. `~/dev/foo/sub` is its own workspace and may
    /// well run a different runtime than `~/dev/foo`; guessing across that boundary
    /// would be a claim this function cannot support, and the fallback is already
    /// a reasonable answer.
    public static func inferred(
        forCwd cwd: String,
        in sessions: [Session],
        fallback: AgentModelSelection
    ) -> AgentModelSelection {
        let target = normalizedPath(cwd)
        guard !target.isEmpty else { return fallback }

        // Sorted newest-first here rather than trusting the caller's order: the
        // session list is grouped/sorted for display (by status, by unread, by
        // host) and that ordering has nothing to do with recency.
        let candidates = sessions
            .filter { normalizedPath($0.cwd ?? "") == target }
            .filter { AgentKind(rawValue: $0.agent) != nil }
            .sorted { ($0.lastActivityAt ?? 0) > ($1.lastActivityAt ?? 0) }

        if let withModel = candidates.first(where: { ($0.model?.isEmpty == false) }) {
            return .restoring(agentRawValue: withModel.agent, model: withModel.model)
        }
        if let withAgent = candidates.first {
            // No model to restore, so `restoring` supplies the agent's default.
            return .restoring(agentRawValue: withAgent.agent, model: nil)
        }
        return fallback
    }

    /// Trailing-slash-insensitive path comparison. `/repo` and `/repo/` are the
    /// same directory, and both forms reach the client: the picker hands over a
    /// scanned repo path, while "Add directory by path…" takes whatever was typed.
    private static func normalizedPath(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
