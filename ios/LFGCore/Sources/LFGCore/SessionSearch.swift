import Foundation

/// How a typed query is matched against a session.
///
/// This exists so the CLIENT and the HOST agree. Search spans the whole corpus,
/// which means results arrive from two places at once: closed sessions matched
/// by the server (`GET /api/sessions/resumable?q=`, which reads its metadata
/// index) and live sessions matched right here, because the client already holds
/// every live session and asking the host for them again would only duplicate
/// rows. If the two used different rules, typing `fix preamble` would return the
/// closed conversations about both words while silently dropping the live one —
/// a difference the user would read as a bug, not as two code paths.
///
/// The rule, mirroring `src/session-index.ts`: lowercase, split on whitespace,
/// and require EVERY term to appear somewhere in the searchable fields.
public enum SessionSearch {
    /// Split a raw query into match terms. Empty means "not searching".
    public static func terms(_ query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Whether every term appears in at least one of `fields`.
    ///
    /// Terms AND, and each term may land in a different field: `fix preamble`
    /// matches a session whose title says "fix the pump" and whose last message
    /// mentions the preamble. Matching the query as one substring could not.
    public static func matches(terms: [String], fields: [String?]) -> Bool {
        guard !terms.isEmpty else { return true }
        let haystack = fields
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
        guard !haystack.isEmpty else { return false }
        return terms.allSatisfy { haystack.contains($0) }
    }

    public static func matches(terms: [String], session: ResumableSession) -> Bool {
        matches(terms: terms,
                fields: [session.title, session.project, session.cwd,
                         session.lastUserText, session.sessionId])
    }

    /// Merge the search pages returned by every host into one result list.
    ///
    /// Search fans out to all hosts, so this has the same job as the unsearched
    /// closed list's reconcile — dedupe the synced transcripts both machines
    /// enumerate, and drop anything live on ANY host — plus one that is specific
    /// to search: **re-apply the match**.
    ///
    /// `?q=` is a request, not a guarantee. A host on a build that predates the
    /// parameter ignores it and returns its ordinary newest-first page, so a
    /// fleet mid-rollout would merge 60 unrelated rows in as though they had
    /// matched. Re-filtering here makes that host contribute less rather than
    /// contribute noise, and costs one substring scan per row.
    public static func reconcile(perHost: [[ResumableSession]],
                                 terms: [String],
                                 liveIds: Set<String>) -> [ResumableSession] {
        MultiHost.reconcileResumable(
            perHost: perHost.map { $0.filter { matches(terms: terms, session: $0) } },
            liveIds: liveIds)
    }
}
