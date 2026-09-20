// Pure decision logic for the fleet Live Activity aggregator. No I/O, no clock.
//
// Every lfg host publishes only its own sessions (a "slice"). A Live Activity push
// REPLACES the card's whole content — iOS never merges two senders — so the merge
// has to happen before the push, and exactly one party may push. That party is this
// Worker. The rules mirror `reduceFleetLiveActivity` in src/push/watcher.ts, applied
// to the union of slices instead of one host's sessions.

export type RowState = "working" | "needsInput";
export type Row = { sid: string; title: string; state: RowState; since: number };
export type Slice = { hostId: string; hostName?: string; rows: Row[]; receivedAt: number };
export type ContentState = { working: number; needsInput: number; rows: Row[]; more: number; updatedAt: number };
export type Card = { startedAt: number; contentState?: ContentState };
export type Veto = { population: string[] } | null;

/** A host that stops publishing is a host whose sessions nobody can vouch for. It
 *  heartbeats every 30 s, so three missed beats drop its rows off the card. */
export const SLICE_TTL_S = 90;
export const MAX_ROWS = 3;

export type Decision = {
  action: null | { event: "start" | "update" | "end"; priority: 5 | 10 };
  content: ContentState;
  nextCard: Card | null;
  population: string[];
  vetoed: boolean;
};

/** Live slices only, one row per session id. During a host-to-host move the same
 *  sid can briefly appear on two hosts; the most recently received slice wins. */
export function unionRows(slices: Slice[], now: number): Row[] {
  const bySid = new Map<string, { row: Row; at: number }>();
  for (const s of slices) {
    if (now - s.receivedAt > SLICE_TTL_S) continue;
    for (const row of s.rows) {
      if (!row.sid || (row.state !== "working" && row.state !== "needsInput")) continue;
      const seen = bySid.get(row.sid);
      if (!seen || s.receivedAt > seen.at) bySid.set(row.sid, { row, at: s.receivedAt });
    }
  }
  return [...bySid.values()].map((v) => v.row);
}

/** Needs-input first so the actionable sessions survive truncation, then oldest
 *  first; sid as the final tiebreak so two hosts' rows order the same every time. */
export function orderRows(rows: Row[]): Row[] {
  return [...rows].sort((a, b) => {
    if (a.state !== b.state) return a.state === "needsInput" ? -1 : 1;
    if (a.since !== b.since) return a.since - b.since;
    return a.sid < b.sid ? -1 : a.sid > b.sid ? 1 : 0;
  });
}

export function contentFor(rows: Row[], now: number): ContentState {
  const ordered = orderRows(rows);
  return {
    working: rows.filter((r) => r.state === "working").length,
    needsInput: rows.filter((r) => r.state === "needsInput").length,
    rows: ordered.slice(0, MAX_ROWS).map((r) => ({ sid: r.sid, title: r.title, state: r.state, since: r.since })),
    more: Math.max(0, ordered.length - MAX_ROWS),
    updatedAt: now,
  };
}

/** `updatedAt` is excluded: it changes on every evaluation. */
export function sameContent(a: ContentState | undefined, b: ContentState): boolean {
  if (!a) return false;
  if (a.working !== b.working || a.needsInput !== b.needsInput || a.more !== b.more) return false;
  if (a.rows.length !== b.rows.length) return false;
  return a.rows.every((r, i) => {
    const o = b.rows[i]!;
    return r.sid === o.sid && r.title === o.title && r.state === o.state && r.since === o.since;
  });
}

export function decide(args: { slices: Slice[]; card: Card | null; clientEnded?: Veto; now: number }): Decision {
  const rows = unionRows(args.slices, args.now);
  const content = contentFor(rows, args.now);
  const population = rows.map((r) => r.sid).sort();
  const total = rows.length;
  const done = (action: Decision["action"], nextCard: Card | null, vetoed = false): Decision =>
    ({ action, content, nextCard, population, vetoed });

  if (!args.card) {
    if (total === 0) return done(null, null);
    const veto = args.clientEnded?.population ?? [];
    // The phone ended its card against this very population; a restart would only
    // be ended again. Only a session it had not seen justifies a new card.
    if (veto.length > 0 && population.every((sid) => veto.includes(sid))) return done(null, null, true);
    return done({ event: "start", priority: 10 }, { startedAt: args.now, contentState: content });
  }

  // Nothing running anywhere: the card goes at once (Eugene, 2026-09-19).
  if (total === 0) return done({ event: "end", priority: 10 }, null);

  if (sameContent(args.card.contentState, content)) return done(null, args.card);

  // Always 10. Priority 5 is delivered "based on power considerations" and showed
  // up on the phone as a visible lag (Eugene, 2026-09-20); a fleet changes tens of
  // times an hour, well inside the frequent-updates budget.
  return done({ event: "update", priority: 10 }, { ...args.card, contentState: content });
}

/**
 * What the CHANNEL should be told, independent of whether the Worker believes a
 * card exists. A broadcast to a channel nobody listens on is a no-op, while a card
 * the Worker does not know about — created by the app, reported to a host that was
 * asleep — is exactly the card that must not go stale. So the channel is kept
 * current on every change of content; "a card exists" gates only `start`, the one
 * push that is not idempotent.
 */
export function broadcastFor(last: ContentState | undefined, content: ContentState): "update" | "end" | null {
  if (sameContent(last, content)) return null;
  const total = content.working + content.needsInput;
  if (total > 0) return "update";
  const lastTotal = last ? last.working + last.needsInput : 0;
  return lastTotal > 0 ? "end" : null;
}

// ---- wire payloads (pinned to src/push/liveactivity.ts) ----

export const relevanceScore = (c: Pick<ContentState, "needsInput">): number => (c.needsInput > 0 ? 100 : 90);

export function startBody(content: ContentState, attributesType: string, channelId: string | undefined) {
  return {
    aps: {
      timestamp: content.updatedAt,
      event: "start",
      "content-state": content,
      "relevance-score": relevanceScore(content),
      "attributes-type": attributesType,
      attributes: { fleetId: "fleet" },
      // Omitted rather than sent empty: a card started against an invalid channel
      // id does not start at all.
      ...(channelId ? { "input-push-channel": channelId } : {}),
      alert: { title: "lfg", body: "LFG sessions are active." },
    },
  };
}

export function updateBody(content: ContentState) {
  return {
    aps: {
      timestamp: content.updatedAt,
      event: "update",
      "content-state": content,
      "relevance-score": relevanceScore(content),
    },
  };
}

/** `dismissal-date` in the past (now) removes the card from the Lock Screen at once. */
export function endBody(content: ContentState, now: number) {
  return { aps: { timestamp: content.updatedAt, event: "end", "content-state": content, "dismissal-date": now } };
}
