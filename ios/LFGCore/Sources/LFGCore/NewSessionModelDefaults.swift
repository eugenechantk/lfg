import Foundation

// MARK: - Per-directory agent/model default

extension AgentModelSelection {
    /// Use this exact directory's history, otherwise Claude with the CLI default.
    /// Global remembered choices never supply a fresh directory's defaults.
    /// Keep explicit historical models; missing metadata uses the known agent's
    /// CLI default. The caller preserves choices made explicitly in the composer.
    public static func inferred(
        forCwd cwd: String,
        in sessions: [Session],
        fallback _: AgentModelSelection,
        catalog _: ModelCatalogResponse = .fallback
    ) -> AgentModelSelection {
        let target = normalizedPath(cwd)
        guard !target.isEmpty else { return .default }

        // Sorted newest-first here rather than trusting the caller's order: the
        // session list is grouped/sorted for display (by status, by unread, by
        // host) and that ordering has nothing to do with recency.
        let candidates = sessions
            .filter { normalizedPath($0.cwd ?? "") == target }
            .compactMap { session in AgentKind(rawValue: session.agent).map { (session, $0) } }
            .sorted { ($0.0.lastActivityAt ?? 0) > ($1.0.lastActivityAt ?? 0) }

        if let (session, agent) = candidates.first(where: { $0.0.model?.isEmpty == false }),
           let model = session.model, isSafeModelName(model) {
            return AgentModelSelection(agent: agent, model: model)
        }
        if let (_, agent) = candidates.first {
            return AgentModelSelection(agent: agent, model: "")
        }
        return .default
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
