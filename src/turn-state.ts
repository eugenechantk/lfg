// Is this session mid-turn? Asked of the TRANSCRIPT, not the terminal.
//
// The original signal was `isBusy(pane)` — regexes over a `tmux capture-pane`
// dump. In a pane, agent output and TUI chrome are the same string, so a session
// that merely PRINTED "esc to interrupt" pinned itself busy for as long as that
// text stayed on screen (`.claude/diagnosis-session-stuck-running.md`). In this
// repo, which documents its own busy detection, that is routine traffic.
//
// The transcript carries a real turn boundary that lfg was ignoring:
// `{"type":"system","subtype":"turn_duration"}`, written at the end of every
// completed turn (present since at least Claude Code 2.1.170). Reading structured
// records instead of rendered text removes the whole spoofing class — an agent
// cannot write its way into a `turn_duration` record.
//
// It also reaches further than a pane can. `~/.claude/projects` is synced between
// hosts, so a host can derive turn state for a session it has no pane for; pane
// scraping structurally cannot.
//
// ORDERING DECIDES, NOT TIMESTAMPS. The obvious formulation — "is the newest
// message newer than the newest turn end" — imports clock skew between two synced
// machines for no benefit. Scanning back and taking the first decisive record
// needs no clock at all.

import { scanBack } from "./transcript.ts";

export type TurnState = "running" | "idle";

/** The answer is nearly always the last line; `scanBack` grows this on a miss. */
const SCAN_START_BYTES = 8 * 1024;
/** Bound the memo so long-lived servers don't accumulate dead transcripts. */
const CACHE_MAX = 256;

// An INTERRUPTED turn never writes `turn_duration` — measured across the real
// corpus (session 82dedc0e: one prompt, zero turn-end records, final line is the
// interrupt marker). lfg interrupts on every steering `send`, not just an
// explicit /interrupt, so treating the marker as a boundary is what keeps this
// signal from latching busy more often than the pane bug it replaces.
const INTERRUPT_RE = /^\[Request interrupted/;

type Line = {
  type?: unknown;
  subtype?: unknown;
  isMeta?: unknown;
  message?: { role?: unknown; content?: unknown };
};

/** First non-null wins when scanning newest-first. Null = keep looking. */
export function classifyTurnLine(line: string): TurnState | null {
  let x: Line;
  try {
    x = JSON.parse(line) as Line;
  } catch {
    return null;
  }
  if (!x || typeof x !== "object") return null;

  if (x.type === "system") {
    // Only `turn_duration` is a boundary. `away_summary` is appended minutes
    // later and `stop_hook_summary` sits just before the boundary — neither may
    // re-open or close a turn on its own.
    return x.subtype === "turn_duration" ? "idle" : null;
  }

  if (x.type === "assistant") return "running";

  if (x.type === "user") {
    const c = x.message?.content;
    // Interrupts arrive as a plain string, or as a single text block depending
    // on where in the turn the Escape landed. Check both before concluding
    // "a user record means a turn is under way".
    const text =
      typeof c === "string"
        ? c
        : Array.isArray(c) && typeof (c[0] as { text?: unknown })?.text === "string"
          ? ((c[0] as { text: string }).text)
          : null;
    if (text != null && INTERRUPT_RE.test(text.trim())) return "idle";
    if (x.isMeta === true) return null; // injected context, not a turn signal
    if (c == null || (Array.isArray(c) && c.length === 0)) return null;
    return "running"; // typed prompt or tool_result — either way, mid-turn
  }

  // `mode`, `ai-title`, `last-prompt`, `file-history-*`, codex rollout records…
  return null;
}

// A transcript is append-only, so an unchanged size means an unchanged verdict.
// That turns a per-session-per-second rescan into a per-session-per-second stat.
const cache = new Map<string, { size: number; state: TurnState | null }>();
let scans = 0;

/**
 * `"running"` | `"idle"`, or `null` when the transcript can't answer — a codex
 * rollout, an unreadable file, a format we don't recognize. Null means "no
 * opinion", never "idle": callers keep whatever fallback they already had, so
 * this can add certainty but never silently mark a running session finished.
 */
export async function transcriptTurnState(path: string): Promise<TurnState | null> {
  let size = 0;
  try {
    size = Bun.file(path).size;
  } catch {
    return null;
  }
  if (size === 0) return null;

  const hit = cache.get(path);
  if (hit && hit.size === size) return hit.state;

  scans++;
  const state = await scanBack(path, classifyTurnLine, { startBytes: SCAN_START_BYTES });
  if (cache.size >= CACHE_MAX && !cache.has(path)) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(path, { size, state });
  return state;
}

export function forgetTurnState(path: string): void {
  cache.delete(path);
}

/** Test seams. */
export function __resetTurnStateCache(): void {
  cache.clear();
  scans = 0;
}
export function __turnStateScanCount(): number {
  return scans;
}
