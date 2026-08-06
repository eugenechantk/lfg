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
  /**
   * The verdict said `running`, but whichever layer said it last spoke more than
   * `STALL_MS` ago, so `state` was demoted to `idle`. Carried for the state debug
   * endpoint and `data/ops.log`; the display ladder does not read it (see below).
   */
  stalled?: true;
};

/**
 * How long a `running` verdict may go without either layer writing again before
 * it stops counting as a turn in flight.
 *
 * WHY THIS EXISTS. Every layer here is EDGE-TRIGGERED on a turn boundary, and a
 * turn that dies mid-flight emits no closing edge in any of them:
 *
 *   hook        `UserPromptSubmit` opens it; `Stop` fires only on a CLEAN end
 *   transcript  a user row opens it; `turn_duration` is never written
 *   pane        the spinner is painted once and never repainted
 *
 * So a session wedged by an upstream error (logged out, out of credits) reported
 * `busy` forever — `.claude/diagnosis-stop-close-noop-20260806.md`, where one sat
 * "running" for 8 hours with a dead process behind it. Two staleness rules already
 * existed (`REST_BUSY_WINDOW_MS`, `BARE_BUSY_WINDOW_MS`) but both are wired as a
 * fallback for the ABSENCE of a verdict, so neither could ever fire on a session
 * that had one. This is the level-triggered check that was missing.
 *
 * WHY 15 MINUTES. A live turn is silent for the length of one tool call, and Bash
 * alone permits a 10-minute timeout, so the 12s used for the no-verdict fallback
 * would flap constantly. 15 minutes is the first threshold that cannot be reached
 * by a turn that is merely quiet.
 *
 * WHY NOT PERSISTED. Stall is a pure function of (verdict, last write, now), and
 * all three are already in hand here — computed at read time it cannot go stale.
 * Writing it into the lease instead would break that file's two-writer ownership
 * split (`state` is the hook's), would always be the newest `stateAt` and so would
 * permanently out-vote the transcript below, and would propagate a derived
 * judgement into the SYNCED tree for the peer host to read back as fact.
 */
export const STALL_MS = 15 * 60_000;

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
  /** Test seam. Real callers use the clock. */
  now?: number;
}): Promise<StateVerdict | null> {
  const now = args.now ?? Date.now();
  const [hook, transcript] = await Promise.all([
    args.sessionId ? hookState(args.sessionId, args.transcriptPath) : Promise.resolve(null),
    args.transcriptPath ? transcriptTurnState(args.transcriptPath) : Promise.resolve(null),
  ]);

  // The stall check needs the timestamp of the layer that DECIDED, not the newest
  // timestamp available — a fresh hook heartbeat must not vouch for a transcript
  // that stopped growing, and vice versa. `decide` pairs every verdict with the
  // moment its own layer last spoke.
  //
  // Both candidates are agent-sourced. `hook.at` is `stateAt`, stamped by the hook
  // when the agent transitioned; the transcript's is its mtime, stamped when the
  // agent last wrote. Deliberately NOT the lease's `heartbeatAt`: that is written
  // by `startLeaseHeartbeat` from lfg's own enumeration, so it proves only that
  // this host can still see the pane.
  const decide = (state: TurnState, source: "hook" | "transcript", at: number): StateVerdict =>
    state === "running" && now - at > STALL_MS
      ? { state: "idle", source, stalled: true }
      : { state, source };

  // `ended` is a lifecycle fact, not a turn fact. For "is a turn in flight" a
  // finished process is idle; whether the session should disappear from the list
  // is `closed`, computed elsewhere.
  const hookTurn: TurnState | null = hook ? (hook.state === "ended" ? "idle" : hook.state) : null;

  // A transcript-only verdict still needs a timestamp to be stall-checked, so the
  // stat that used to happen only in the arbitration branch now happens whenever
  // the transcript has an opinion. It is one stat per session per poll against a
  // file `transcriptTurnState` just read — cheap next to the `ps`/`tmux` spawns in
  // the same pass.
  let transcriptAt: number | null = null;
  if (transcript != null && args.transcriptPath) {
    try {
      transcriptAt = (await stat(args.transcriptPath)).mtimeMs;
    } catch {
      transcriptAt = null;
    }
  }

  if (hookTurn == null) {
    if (transcript == null) return null;
    // Unreadable mtime (rotated, unlinked) means we cannot prove staleness. Report
    // the verdict as-is rather than demoting on a guess — this function may add
    // certainty, never invent it.
    return transcriptAt == null
      ? { state: transcript, source: "transcript" }
      : decide(transcript, "transcript", transcriptAt);
  }
  if (transcript == null) return decide(hookTurn, "hook", hook!.at);

  if (transcriptAt == null) {
    // The transcript answered a moment ago but can't be stat'd now (rotated,
    // unlinked). Without a timestamp it cannot win a recency contest, so defer
    // to the layer that can prove when it spoke.
    return decide(hookTurn, "hook", hook!.at);
  }

  // Ties go to the transcript. The two are written within ~200ms of each other at
  // a turn boundary, and the transcript is the layer that can express "this turn
  // was interrupted" — a tie is far more likely to be that boundary than a hook
  // arriving late.
  return hook!.at > transcriptAt
    ? decide(hookTurn, "hook", hook!.at)
    : decide(transcript, "transcript", transcriptAt);
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
