import { randomUUID } from "node:crypto";
import { basename } from "node:path";
import { queryTerms, type IndexEntry } from "./session-index";
import type { ContentHit } from "./session-content-index";

export type RankedSession = {
  agent: "claude" | "codex";
  sessionId: string;
  cwd: string | null;
  project: string;
  title: string;
  lastActivityAt: number;
  lastUserText: string | null;
  matchRole: "user" | "assistant" | null;
  rank: number;
  searchMatched: true;
  closed: true;
};

const PREVIEW_CHARS = 160;

function excerpt(text: string, terms: string[]): string {
  const lower = text.toLowerCase();
  const positions = terms.map((term) => lower.indexOf(term)).filter((index) => index >= 0);
  const at = positions.length ? Math.min(...positions) : 0;
  const start = Math.max(0, at - 40);
  const end = Math.min(text.length, start + PREVIEW_CHARS);
  const oneLine = text.slice(start, end).replace(/\s+/g, " ").trim();
  return `${start ? "…" : ""}${oneLine}${end < text.length ? "…" : ""}`;
}

/** Directory matches, then titles, then other matches; newest first in each group. */
export function rankSessions(
  entries: IndexEntry[],
  hits: Iterable<ContentHit>,
  query: string,
  hidden: (cwd: string | null) => boolean = () => false,
): RankedSession[] {
  const terms = queryTerms(query);
  if (!terms.length) return [];
  const content = new Map<string, { terms: Set<string>; best: ContentHit | null }>();
  for (const hit of hits) {
    const covered = terms.filter((term) => hit.text.toLowerCase().includes(term));
    if (!covered.length) continue;
    const state = content.get(hit.sessionId) ?? { terms: new Set<string>(), best: null };
    covered.forEach((term) => state.terms.add(term));
    const quality = (hit.role === "user" ? 2 : 0) - hit.rank;
    const prior = state.best;
    if (!prior || quality > (prior.role === "user" ? 2 : 0) - prior.rank) state.best = hit;
    content.set(hit.sessionId, state);
  }

  const result: RankedSession[] = [];
  for (const entry of entries) {
    if (hidden(entry.cwd)) continue;
    const fields = [entry.title, entry.project, entry.cwd ?? "", entry.lastUserText ?? "", entry.sessionId];
    const haystack = fields.join("\n").toLowerCase();
    const body = content.get(entry.sessionId);
    if (!terms.every((term) => haystack.includes(term) || body?.terms.has(term))) continue;
    const directory = [entry.cwd ?? "", entry.project].join("\n").toLowerCase();
    const directoryAll = terms.every((term) => directory.includes(term));
    const titleAll = terms.every((term) => entry.title.toLowerCase().includes(term));
    const best = body?.best ?? null;
    result.push({
      agent: entry.agent,
      sessionId: entry.sessionId,
      cwd: entry.cwd,
      project: entry.project || (entry.cwd ? basename(entry.cwd) : "—"),
      title: entry.title,
      lastActivityAt: entry.mtime,
      lastUserText: best ? `${best.role === "user" ? "You" : "Assistant"}: ${excerpt(best.text, terms)}` : entry.lastUserText,
      matchRole: best?.role ?? null,
      rank: directoryAll ? 3 : titleAll ? 2 : 1,
      searchMatched: true,
      closed: true,
    });
  }
  result.sort((a, b) => b.rank - a.rank || b.lastActivityAt - a.lastActivityAt || a.sessionId.localeCompare(b.sessionId));
  return result;
}

type Snapshot = { query: string; excludes: string; created: number; rows: RankedSession[] };

/** Cursors identify a frozen ordered result set while indexing continues. */
export class RankedSearchPager {
  private snapshots = new Map<string, Snapshot>();
  constructor(private readonly ttlMs = 10 * 60_000, private readonly maxSnapshots = 16) {}

  first(query: string, excludes: string, rows: RankedSession[], limit: number) {
    this.evict();
    const id = randomUUID();
    this.snapshots.set(id, { query, excludes, created: Date.now(), rows });
    return this.page(id, 0, limit)!;
  }

  next(cursor: string, query: string, excludes: string, limit: number) {
    const [id, rawOffset] = cursor.split(":");
    const offset = Number(rawOffset);
    const snapshot = this.snapshots.get(id);
    if (!snapshot || snapshot.query !== query || snapshot.excludes !== excludes ||
        !Number.isSafeInteger(offset) || offset < 0 || Date.now() - snapshot.created > this.ttlMs)
      return null;
    return this.page(id, offset, limit);
  }

  private page(id: string, offset: number, limit: number) {
    const rows = this.snapshots.get(id)!.rows;
    const end = Math.min(rows.length, offset + limit);
    return { sessions: rows.slice(offset, end), nextCursor: end < rows.length ? `${id}:${end}` : null };
  }

  private evict() {
    for (const [id, snapshot] of this.snapshots)
      if (Date.now() - snapshot.created > this.ttlMs) this.snapshots.delete(id);
    while (this.snapshots.size >= this.maxSnapshots) this.snapshots.delete(this.snapshots.keys().next().value!);
  }
}
