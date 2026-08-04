// Layer 1 of the session-state stack: what the agent said about itself.
//
// Layers 2 (transcript, `turn-state.ts`) and 3 (pane, `isBusy`) both INFER turn
// state from artifacts the agent happens to leave behind. Hooks are different in
// kind: `UserPromptSubmit` and `Stop` are the agent announcing its own
// transitions, so there is nothing to spoof and nothing to parse.
//
// Claude Code 2.1.220 and codex 0.145.0 emit the same event names with the same
// `session_id` field, so one hook script (`scripts/lfg-agent-hook.py`) feeds both.
//
// THE CATCH, and why this layer does not simply outrank the others: `Stop` does
// not fire on an ESC interrupt. lfg interrupts on every steering send, so a
// hook-wins-always design would latch `running` on the product's most common send
// path — strictly worse than the pane bug this whole effort began with. See
// `sessionTurnState` for the recency arbitration that resolves it.

import { join } from "node:path";
import { homedir } from "node:os";
import { leasePathForTranscript } from "./leases.ts";
import type { TurnState } from "./turn-state.ts";

/** `ended` is a session-lifecycle fact, not a turn fact — see `HookState`. */
export type HookRecordState = TurnState | "ended";

export type HookState = {
  state: HookRecordState;
  /** ms since epoch, stamped by the hook process itself. */
  at: number;
  event?: string;
  transcript?: string | null;
};

export const agentStateDir = (): string =>
  process.env.LFG_AGENT_STATE_DIR ?? join(homedir(), ".lfg", "agent-state");

const VALID: ReadonlySet<string> = new Set(["running", "idle", "ended"]);

/** Exported for tests; `hookState` is the caching entry point. */
export function parseHookState(text: string): HookState | null {
  let x: unknown;
  try {
    x = JSON.parse(text);
  } catch {
    return null;
  }
  if (!x || typeof x !== "object") return null;
  const r = x as Record<string, unknown>;
  const state = typeof r.state === "string" ? r.state : "";
  // `at` is the fallback store's field; `stateAt` is the lease's. One parser
  // serves both so callers never care which file answered.
  const at =
    typeof r.stateAt === "number" ? r.stateAt : typeof r.at === "number" ? r.at : NaN;
  // A record without a usable timestamp cannot take part in recency arbitration,
  // and a hook state that can't be ordered is worse than no hook state at all.
  if (!VALID.has(state) || !Number.isFinite(at)) return null;
  return {
    state: state as HookRecordState,
    at,
    event:
      typeof r.stateEvent === "string"
        ? r.stateEvent
        : typeof r.event === "string"
          ? r.event
          : undefined,
    transcript: typeof r.transcript === "string" ? r.transcript : null,
  };
}

// Same memo strategy as `turn-state.ts`: the file is rewritten wholesale on every
// transition, so (size, mtime) unchanged means verdict unchanged. Turns a
// per-session-per-tick parse into a per-session-per-tick stat.
const cache = new Map<string, { size: number; mtime: number; value: HookState | null }>();
const CACHE_MAX = 256;
let reads = 0;

/**
 * The agent's own last word on this session, or `null` when it has none — no
 * hooks installed, a session older than the install, an unreadable or torn file.
 *
 * `null` means "no opinion", never "idle". Every caller falls through to the
 * layer below, so this can add certainty but can never silently mark a running
 * session finished.
 */
export async function hookState(
  sessionId: string,
  transcriptPath?: string | null,
): Promise<HookState | null> {
  if (!sessionId) return null;
  // The lease is where the hook writes when it has a transcript path, which is
  // the normal case — one record per session, in the synced tree, shared with
  // lfg's liveness fields. The host-local store is only the fallback for
  // payloads that arrived without a transcript.
  const path = transcriptPath
    ? leasePathForTranscript(sessionId, transcriptPath)
    : join(agentStateDir(), `${sessionId}.json`);
  const f = Bun.file(path);
  let size = 0;
  let mtime = 0;
  try {
    size = f.size;
    if (size === 0) return null;
    mtime = (await f.stat()).mtimeMs;
  } catch {
    return null;
  }

  const hit = cache.get(path);
  if (hit && hit.size === size && hit.mtime === mtime) return hit.value;

  reads++;
  let value: HookState | null = null;
  try {
    value = parseHookState(await f.text());
  } catch {
    value = null;
  }
  if (cache.size >= CACHE_MAX && !cache.has(path)) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(path, { size, mtime, value });
  return value;
}

export function forgetHookState(sessionId: string, transcriptPath?: string | null): void {
  cache.delete(join(agentStateDir(), `${sessionId}.json`));
  if (transcriptPath) cache.delete(leasePathForTranscript(sessionId, transcriptPath));
}

/** Test seams, mirroring `turn-state.ts`. */
export function __resetHookStateCache(): void {
  cache.clear();
  reads = 0;
}
export function __hookStateReadCount(): number {
  return reads;
}
