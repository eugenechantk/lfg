// "Autopilot already looked at this session, at this size."
//
// Deliberately its own file rather than extra fields on the title override
// record. Two reasons, and the second is the load-bearing one:
//
//   1. `session-titles.json` is read on every session list and every search
//      refresh. It should stay a map of titles, not accumulate bookkeeping.
//   2. A title record without a title is dropped by the parser — correctly, since
//      an empty title is not an override. But the sessions that most need a
//      checkpoint are exactly the ones with NO override yet (they're wearing
//      their first-prompt title, which is what drifts). Storing the checkpoint
//      there would either lose it or force a fake title into the overrides.

export type Checkpoint = {
  /** Transcript size in bytes when autopilot last examined it. */
  bytes: number;
  /** ms epoch of that examination. */
  at: number;
  /**
   * Every genuine user message found through `bytes`, oldest-first and already
   * truncated for the title prompt. Optional for compatibility with checkpoints
   * written before conversation-aware titles shipped.
   */
  userMessages?: string[];
};

export type CheckpointFile = Record<string, Checkpoint>;

export function parseCheckpoints(raw: unknown): CheckpointFile {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: CheckpointFile = {};
  for (const [id, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!id || !value || typeof value !== "object") continue;
    const v = value as Partial<Checkpoint>;
    if (typeof v.bytes !== "number" || !Number.isFinite(v.bytes)) continue;
    if (typeof v.at !== "number" || !Number.isFinite(v.at)) continue;
    const checkpoint: Checkpoint = { bytes: v.bytes, at: v.at };
    if (
      Array.isArray(v.userMessages) &&
      v.userMessages.every((message) => typeof message === "string")
    ) {
      checkpoint.userMessages = v.userMessages;
    }
    out[id] = checkpoint;
  }
  return out;
}

/**
 * Keep only the checkpoints still worth having, so the file tracks the live
 * session population instead of growing without bound.
 *
 * Call it with the run's FULL candidate set (everything inside the recency
 * window), never the selected page — pruning against a page would delete every
 * checkpoint outside it on each run. Dropping a session that has aged out of the
 * window is correct and cheap: it can't be selected anyway, and if it comes back
 * to life it simply gets examined once more.
 */
export function pruneCheckpoints(file: CheckpointFile, knownIds: Set<string>): CheckpointFile {
  const out: CheckpointFile = {};
  for (const [id, cp] of Object.entries(file)) if (knownIds.has(id)) out[id] = cp;
  return out;
}
