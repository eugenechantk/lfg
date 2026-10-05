// A stop that lfg itself CONFIRMED, kept as evidence that a turn is over.
//
// WHY THIS EXISTS. `turn-state.ts` closes an interrupted turn on the
// `[Request interrupted` marker — but Claude Code only writes that marker once
// the turn has produced something. Press Stop before the first assistant row and
// Claude REWINDS instead: the prompt goes back into the composer and the
// transcript gains nothing. Its newest decisive line is still the prompt, so it
// reads `running`; `Stop` does not fire on Escape, so the hook layer cannot
// retract it either. The session sat "Working" until `STALL_MS` (15 min) while
// the agent was idle and Eugene pressed Stop again
// (`lfg-e4d53c`, 2026-10-04 — `.claude/feature/stop-clears-busy-before-first-reply.md`).
//
// The transcript carries no trace of the rewind at all, so no transcript reading
// can fix this. lfg does hold one piece of evidence nothing else has: the
// interrupt endpoint watched the pane go idle right after its Escape.
//
// RECENCY, LIKE THE OTHER LAYERS. The mark closes a turn only until either layer
// speaks again — a new prompt, the hook announcing one, assistant output from a
// stop that did not really take. "Speaks" means a DECISIVE record: Claude also
// appends `ai-title`, `last-prompt` and friends after a turn opens, and letting
// those cancel the mark (as an mtime comparison would) re-opens the very turn it
// closed. So the mark keeps the transcript size it saw and only a line
// `classifyTurnLine` has an opinion on, appended past that size, supersedes it.
//
// IN MEMORY ON PURPOSE. A restart loses every mark and `STALL_MS` still bounds
// the latch. Writing it into the lease would push a host-local judgement into
// the synced tree for the peer host to read back as fact.

import { classifyTurnLine } from "./turn-state.ts";

type Mark = {
  /** When the stop was confirmed, on this host's clock — compared to `hook.at`. */
  at: number;
  transcriptPath: string | null;
  /** Transcript bytes already known to hold no decisive line. */
  checkedSize: number;
};

const marks = new Map<string, Mark>();
/** Bound the map so a long-lived server doesn't keep marks for dead sessions. */
const MAX_MARKS = 256;
/** More than this appended since the stop is a live session, not metadata. */
const MAX_UNCHECKED_BYTES = 1 << 20;

export type InterruptBaseline = { at: number; transcriptPath: string | null; size: number };

/**
 * Take this BEFORE sending the Escape. A message already waiting in Claude's own
 * queue starts the moment the stop lands, and its user row and hook can both be
 * written before the stop is confirmed. Measured from after the confirm, that new
 * turn would read idle until its first reply — tens of seconds at high effort.
 * Measured from before, its records are "since the stop" and cancel the mark.
 */
export function interruptBaseline(
  transcriptPath: string | null | undefined,
  at: number = Date.now(),
): InterruptBaseline {
  let size = 0;
  try {
    if (transcriptPath) size = Bun.file(transcriptPath).size;
  } catch {}
  return { at, transcriptPath: transcriptPath ?? null, size };
}

/** Call only when the stop was CONFIRMED (`interruptAndConfirm` → `stopped: true`). */
export function noteConfirmedInterrupt(sessionId: string, baseline: InterruptBaseline): void {
  marks.delete(sessionId); // re-insert so eviction stays oldest-first
  if (marks.size >= MAX_MARKS) {
    const oldest = marks.keys().next().value;
    if (oldest !== undefined) marks.delete(oldest);
  }
  marks.set(sessionId, {
    at: baseline.at,
    transcriptPath: baseline.transcriptPath,
    checkedSize: baseline.size,
  });
}

/**
 * Does a confirmed stop still stand — has neither layer spoken since?
 * A superseded mark is dropped, so it cannot revive on a later tick.
 */
export async function interruptStands(
  sessionId: string,
  transcriptPath: string | null | undefined,
  hookAt: number | null,
): Promise<boolean> {
  const m = marks.get(sessionId);
  if (!m) return false;
  const stands = (hookAt == null || hookAt <= m.at) && (await noDecisiveSince(m, transcriptPath));
  if (!stands) marks.delete(sessionId);
  return stands;
}

async function noDecisiveSince(m: Mark, transcriptPath: string | null | undefined): Promise<boolean> {
  // A different transcript (the session continued elsewhere) is new activity we
  // cannot prove quiet. This layer may add certainty, never invent it.
  if ((transcriptPath ?? null) !== m.transcriptPath) return false;
  if (!transcriptPath) return true;
  let size: number;
  try {
    size = Bun.file(transcriptPath).size;
  } catch {
    return false;
  }
  if (size === m.checkedSize) return true;
  if (size < m.checkedSize || size - m.checkedSize > MAX_UNCHECKED_BYTES) return false;
  // The pump, the push watcher and the REST list all ask in the same tick, so a
  // second reader can resume here after the first already advanced the mark.
  // Advance from where THIS read started, never by adding twice.
  const from = m.checkedSize;
  const tail = await Bun.file(transcriptPath).slice(from, size).text();
  // Only whole lines count; a line still being written is judged next tick. A
  // fragment at the front (the stop landed mid-write) fails to parse and is
  // ignored — it belongs to the turn that was stopped.
  const end = tail.lastIndexOf("\n");
  if (end < 0) return true;
  for (const line of tail.slice(0, end).split("\n")) {
    if (classifyTurnLine(line) != null) return false;
  }
  m.checkedSize = Math.max(m.checkedSize, from + Buffer.byteLength(tail.slice(0, end + 1)));
  return true;
}

/** Test seam. */
export function __resetInterruptMarks(): void {
  marks.clear();
}
