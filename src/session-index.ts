// A metadata index over EVERY session transcript on this host, so search can
// span the whole corpus instead of whatever page the client happens to have
// loaded.
//
// Why an index at all: the searchable fields (title, project, cwd, last user
// text) are not on disk as metadata — each one costs a head read plus a
// tail scan of the transcript. `listResumable` can afford that because it only
// enriches the newest `limit` rows; a search cannot, because the match may be
// the 4,000th-newest conversation. Measured on the Pro (2026-08-11): 5,318
// transcripts, 1.4 GB, full enrichment 431 ms warm — cheap enough to build once
// and then refresh incrementally by mtime, and far too expensive to redo per
// keystroke.
//
// Everything here is pure: entry shape, the reuse/enrich diff, query matching,
// and cursor paging. The filesystem side (enumerate, enrich, persist) lives in
// `sessions.ts`, which owns those primitives already. That split is what lets
// the interesting logic be unit-tested without a transcript corpus.

/** Bump when the entry shape changes; a mismatched file is discarded, not migrated. */
export const SEARCH_INDEX_VERSION = 1;

/** One indexed session: the searchable metadata plus what invalidates it. */
export type IndexEntry = {
  agent: "claude" | "codex";
  sessionId: string;
  /** Transcript path — part of the cache key: a synced conversation can move. */
  path: string;
  mtime: number;
  cwd: string | null;
  project: string;
  title: string;
  lastUserText: string | null;
};

/** What an enumeration pass knows before paying for enrichment. */
export type IndexCandidate = {
  agent: "claude" | "codex";
  sessionId: string;
  path: string;
  mtime: number;
};

export type SearchIndexFile = {
  version: number;
  entries: IndexEntry[];
};

/**
 * Read a persisted index leniently. Anything malformed — wrong version, not an
 * object, a row missing its identity — yields an empty index rather than
 * throwing: the whole point of the file is to save work, so a corrupt one costs
 * one rebuild, never a failed search.
 */
export function parseIndexFile(raw: unknown): IndexEntry[] {
  if (!raw || typeof raw !== "object") return [];
  const file = raw as Partial<SearchIndexFile>;
  if (file.version !== SEARCH_INDEX_VERSION) return [];
  if (!Array.isArray(file.entries)) return [];
  const out: IndexEntry[] = [];
  for (const e of file.entries) {
    if (!e || typeof e !== "object") continue;
    const { sessionId, path, mtime } = e as IndexEntry;
    if (typeof sessionId !== "string" || !sessionId) continue;
    if (typeof path !== "string" || !path) continue;
    if (typeof mtime !== "number" || !Number.isFinite(mtime)) continue;
    out.push({
      agent: (e as IndexEntry).agent === "codex" ? "codex" : "claude",
      sessionId,
      path,
      mtime,
      cwd: typeof (e as IndexEntry).cwd === "string" ? (e as IndexEntry).cwd : null,
      project: typeof (e as IndexEntry).project === "string" ? (e as IndexEntry).project : "—",
      title: typeof (e as IndexEntry).title === "string" ? (e as IndexEntry).title : "—",
      lastUserText:
        typeof (e as IndexEntry).lastUserText === "string" ? (e as IndexEntry).lastUserText : null,
    });
  }
  return out;
}

export function serializeIndex(entries: IndexEntry[]): SearchIndexFile {
  return { version: SEARCH_INDEX_VERSION, entries };
}

export type RefreshPlan = {
  /** Cached entries still valid — same path AND same mtime. */
  reuse: IndexEntry[];
  /** Candidates that must be read: new, moved, or modified since indexing. */
  stale: IndexCandidate[];
  /** Indexed sessions no longer on disk; dropped from the next index. */
  dropped: number;
};

/**
 * Partition an enumeration against the cached index. This is what makes a
 * search cost a stat pass instead of a corpus read: only transcripts whose
 * (path, mtime) changed get re-enriched.
 *
 * The mtime must match exactly, not merely be "not newer". A transcript synced
 * back from another host can land with an OLDER mtime than the one we indexed,
 * and its content is then also older — treating that as fresh would serve a
 * title the file no longer has.
 */
export function planRefresh(prev: IndexEntry[], candidates: IndexCandidate[]): RefreshPlan {
  const byId = new Map(prev.map((e) => [e.sessionId, e]));
  const reuse: IndexEntry[] = [];
  const stale: IndexCandidate[] = [];
  const seen = new Set<string>();
  for (const c of candidates) {
    // An enumeration can legitimately offer the same sessionId twice (a synced
    // conversation present under two encoded project dirs). Keep the first —
    // callers hand us candidates newest-first — so the index has one row per
    // conversation and paging can't return a duplicate.
    if (seen.has(c.sessionId)) continue;
    seen.add(c.sessionId);
    const cached = byId.get(c.sessionId);
    if (cached && cached.path === c.path && cached.mtime === c.mtime) reuse.push(cached);
    else stale.push(c);
  }
  return { reuse, stale, dropped: prev.length - reuse.length };
}

/**
 * Split a raw query into lowercased terms. Multiple terms AND together, so
 * "preamble pane" finds the session about both rather than only the sessions
 * whose text contains that exact phrase.
 */
export function queryTerms(q: string): string[] {
  return q
    .toLowerCase()
    .split(/\s+/)
    .map((t) => t.trim())
    .filter(Boolean);
}

/** Everything a query is matched against, lowercased and joined. */
export function entryHaystack(e: IndexEntry): string {
  return [e.title, e.project, e.cwd, e.lastUserText, e.sessionId]
    .filter((v): v is string => typeof v === "string" && v.length > 0)
    .join("\n")
    .toLowerCase();
}

export function matchesTerms(e: IndexEntry, terms: string[]): boolean {
  if (terms.length === 0) return true;
  const hay = entryHaystack(e);
  return terms.every((t) => hay.includes(t));
}

/**
 * Every entry matching `terms` that is older than the `before` cursor, newest
 * first.
 *
 * Liveness is deliberately NOT applied here — "does something hold a fresh
 * lease" is an async filesystem question, and it belongs with the caller that
 * fills the page (mirroring `listResumable`). This returns the full match set so
 * the caller can walk it, skipping live rows, until the page is full.
 *
 * The cursor is strict (`mtime < before`), the same comparison the unsearched
 * resumable list uses. Two transcripts sharing an exact millisecond mtime at a
 * page boundary would drop the second; that is existing behaviour, and search
 * paging matching list paging is worth more than fixing it in one of the two.
 */
export function matchingEntries(
  entries: IndexEntry[],
  terms: string[],
  before: number | null,
): IndexEntry[] {
  const hits = entries.filter(
    (e) => (before == null || e.mtime < before) && matchesTerms(e, terms),
  );
  hits.sort((a, b) => (b.mtime === a.mtime ? a.sessionId.localeCompare(b.sessionId) : b.mtime - a.mtime));
  return hits;
}

/**
 * Overlay user-set title overrides onto the index. Overrides live in their own
 * file and change without touching the transcript, so they cannot be baked in
 * at enrichment time — a renamed session would keep matching (and displaying)
 * its old first-prompt title until the conversation next got written to.
 */
export function applyTitleOverrides(
  entries: IndexEntry[],
  overrides: Record<string, string>,
): IndexEntry[] {
  if (!overrides || Object.keys(overrides).length === 0) return entries;
  return entries.map((e) => {
    const t = overrides[e.sessionId];
    return t ? { ...e, title: t } : e;
  });
}
