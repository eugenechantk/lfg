// Combines the session-state layers into one verdict.
//
//   1. hooks      — `hook-state.ts`, the agent announcing its own transitions
//   2. transcript — `turn-state.ts`, a turn boundary the agent wrote down
//   3. pane       — `isBusy(pane)`, the caller's fallback when this returns null
//
// WHY THIS IS NOT A PRIORITY LADDER. The obvious design — hooks always beat the
// transcript because hooks are authoritative — is wrong, and wrong in the
// direction that hurts most. `Stop` does not fire when a turn is interrupted with
// Escape, and lfg interrupts on EVERY steering send (see `sendq.ts`), so the hook
// file is left reading `running` on the product's most common send path. A
// rank-based stack would latch busy there permanently: the same failure mode as
// the pane bug that started this work, just relocated.
//
// So the two layers arbitrate BY RECENCY. Whichever wrote last describes the
// session more currently, and the interrupt resolves itself: no `Stop` fires, but
// the transcript records `[Request interrupted` after the stale hook write, so the
// transcript is newer and wins.
//
// Note this compares two clocks on ONE host — the hook's `at` and the transcript's
// mtime, both stamped locally. That is deliberate and different from the reasoning
// inside `turn-state.ts`, which refuses to compare timestamps because `~/.claude`
// is SYNCED between machines and record timestamps can come from a peer. File
// mtime is local metadata; sync rewrites it on arrival.

import { stat } from "node:fs/promises";
import { hookState } from "./hook-state.ts";
import { transcriptTurnState, type TurnState } from "./turn-state.ts";

export type StateVerdict = {
  state: TurnState;
  /** Which layer decided. Carried for logging and for the state debug endpoint. */
  source: "hook" | "transcript";
};

/**
 * `running` / `idle` with the layer that decided, or `null` when neither layer
 * has an opinion — no hooks installed AND an unreadable/unrecognized transcript.
 *
 * Null means "no opinion", never "idle": callers keep their existing pane
 * fallback, so this can add certainty but never silently mark a running session
 * finished. That invariant is what makes the stack safe to extend.
 */
export async function sessionTurnState(args: {
  sessionId?: string | null;
  transcriptPath?: string | null;
}): Promise<StateVerdict | null> {
  const [hook, transcript] = await Promise.all([
    args.sessionId ? hookState(args.sessionId, args.transcriptPath) : Promise.resolve(null),
    args.transcriptPath ? transcriptTurnState(args.transcriptPath) : Promise.resolve(null),
  ]);

  // `ended` is a lifecycle fact, not a turn fact. For "is a turn in flight" a
  // finished process is idle; whether the session should disappear from the list
  // is `closed`, computed elsewhere.
  const hookTurn: TurnState | null = hook ? (hook.state === "ended" ? "idle" : hook.state) : null;

  if (hookTurn == null) return transcript ? { state: transcript, source: "transcript" } : null;
  if (transcript == null) return { state: hookTurn, source: "hook" };

  let transcriptAt = 0;
  try {
    transcriptAt = (await stat(args.transcriptPath!)).mtimeMs;
  } catch {
    // The transcript answered a moment ago but can't be stat'd now (rotated,
    // unlinked). Without a timestamp it cannot win a recency contest, so defer
    // to the layer that can prove when it spoke.
    return { state: hookTurn, source: "hook" };
  }

  // Ties go to the transcript. The two are written within ~200ms of each other at
  // a turn boundary, and the transcript is the layer that can express "this turn
  // was interrupted" — a tie is far more likely to be that boundary than a hook
  // arriving late.
  return hook!.at > transcriptAt
    ? { state: hookTurn, source: "hook" }
    : { state: transcript, source: "transcript" };
}

// ---- the display ladder ----
//
// Three consumers used to re-derive this precedence independently:
// `SessionStore.group(for:)`, `FleetActivitySnapshot.contentState`, and
// `fleetRowState` in push/watcher.ts. They were kept in step by comment and code
// review, and that has already shipped one bug where ended sessions read
// "running" on the Live Activity while the list showed them correctly. This is
// the single definition for the server side; `SessionState.swift` in LFGCore is
// its counterpart, and `session-state-parity.test.ts` pins the two together.
//
// Order is load-bearing:
//   prompt  — an agent asking you something outranks everything. It is the only
//             state that needs a human, so it must survive row truncation.
//   blocked — an upstream API error (logged out, out of credits, 401/403; see
//             `computeStatus`). Despite the client's "Paused" label this session
//             is making no progress AND asking nothing, so it is not "working".
//   busy    — a turn is in flight.
//   idle    — everything else.
//
// `closed` is deliberately absent: it is not a property of the agent's turn but
// of process ownership, and only a client holds the cross-host live set needed to
// decide it. See .claude/feature/closed-state-derivation.md.

export type SessionDisplayState = "needsInput" | "blocked" | "working" | "idle";

export function sessionDisplayState(s: {
  promptPresent?: boolean | null;
  blocked?: boolean | null;
  busy?: boolean | null;
}): SessionDisplayState {
  if (s.promptPresent) return "needsInput";
  if (s.blocked) return "blocked";
  if (s.busy) return "working";
  return "idle";
}
