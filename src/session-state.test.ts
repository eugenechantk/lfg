import { test, expect, describe, beforeEach } from "bun:test";
import { mkdtempSync, writeFileSync, utimesSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sessionTurnState, resolveBusy, STALL_MS } from "./session-state.ts";
import { __resetHookStateCache } from "./hook-state.ts";
import { __resetTurnStateCache } from "./turn-state.ts";

const dir = mkdtempSync(join(tmpdir(), "session-state-"));
const stateDir = join(dir, "agent-state");
process.env.LFG_AGENT_STATE_DIR = stateDir;
require("node:fs").mkdirSync(stateDir, { recursive: true });

let n = 0;

/**
 * Fixture timestamps are RELATIVE ORDERING, not absolute time — `1_000` vs
 * `9_000` only ever meant "the hook spoke before the transcript". Anchoring them
 * near `now` became load-bearing when `sessionTurnState` gained the STALL_MS
 * guard: at the raw epoch values these fixtures used to carry, every `running`
 * verdict is ~56 years stale and would be demoted, so the arbitration tests would
 * pass for entirely the wrong reason. Offsets stay as written; the base moves.
 */
const BASE = Date.now() - 10_000;
const at = (offset: number) => BASE + offset;

/** Write hook-owned fields into the LEASE, where the hook now writes them.
 *  Every fixture transcript lives in `dir`, so the lease path for any of them is
 *  `dir/<sid>.lease.json`. lfg's liveness fields are included to prove the
 *  arbitration reads the shared record without disturbing them. */
const hook = (sid: string, state: string, offset: number) =>
  writeFileSync(
    join(dir, `${sid}.lease.json`),
    JSON.stringify({
      hostId: "host-a",
      pid: 1,
      acquiredAt: 1,
      heartbeatAt: 1,
      state,
      stateAt: at(offset),
    }),
  );

/** Write a transcript whose mtime is pinned to `BASE + offset`. */
const transcript = (lines: unknown[], offset: number): string => {
  const p = join(dir, `t${n++}.jsonl`);
  writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  utimesSync(p, new Date(at(offset)), new Date(at(offset)));
  return p;
};

const assistantRec = { type: "assistant", message: { role: "assistant", content: [] } };
const turnEnd = { type: "system", subtype: "turn_duration" };
const interrupted = {
  type: "user",
  message: { role: "user", content: "[Request interrupted by user]" },
};

beforeEach(() => {
  __resetHookStateCache();
  __resetTurnStateCache();
});

describe("sessionTurnState arbitration", () => {
  test("neither layer has an opinion → null (caller keeps its pane fallback)", async () => {
    expect(await sessionTurnState({ sessionId: "absent", transcriptPath: null })).toBeNull();
  });

  test("hooks not installed → the transcript decides", async () => {
    const tp = transcript([assistantRec], 5_000);
    const got = await sessionTurnState({ sessionId: "no-hooks", transcriptPath: tp });
    expect(got).toEqual({ state: "running", source: "transcript" });
  });

  test("transcript unreadable → the hook decides", async () => {
    hook("h1", "running", 5_000);
    const got = await sessionTurnState({ sessionId: "h1", transcriptPath: join(dir, "nope.jsonl") });
    expect(got).toEqual({ state: "running", source: "hook" });
  });

  test("mid-turn: transcript is newer and agrees → running", async () => {
    hook("h2", "running", 1_000);
    const tp = transcript([assistantRec], 9_000);
    const got = await sessionTurnState({ sessionId: "h2", transcriptPath: tp });
    expect(got).toEqual({ state: "running", source: "transcript" });
  });

  test("turn end: both say idle regardless of who wins the tie", async () => {
    hook("h3", "idle", 9_000);
    const tp = transcript([assistantRec, turnEnd], 9_000);
    expect((await sessionTurnState({ sessionId: "h3", transcriptPath: tp }))?.state).toBe("idle");
  });

  // THE case this whole design exists for. ESC fires no `Stop`, so the hook file
  // is stranded at "running"; the transcript records the interrupt afterwards and
  // must win, or lfg latches busy on every steering send.
  test("ESC interrupt: stale running hook loses to a newer interrupt marker", async () => {
    hook("h4", "running", 1_000);
    const tp = transcript([assistantRec, interrupted], 9_000);
    const got = await sessionTurnState({ sessionId: "h4", transcriptPath: tp });
    expect(got).toEqual({ state: "idle", source: "transcript" });
  });

  test("new turn after a Stop: hook is newer than a stale transcript → running", async () => {
    hook("h5", "running", 9_000);
    const tp = transcript([assistantRec, turnEnd], 1_000);
    const got = await sessionTurnState({ sessionId: "h5", transcriptPath: tp });
    expect(got).toEqual({ state: "running", source: "hook" });
  });

  test("SessionEnd maps to idle for turn purposes", async () => {
    hook("h6", "ended", 9_000);
    const tp = transcript([assistantRec], 1_000);
    const got = await sessionTurnState({ sessionId: "h6", transcriptPath: tp });
    expect(got).toEqual({ state: "idle", source: "hook" });
  });

  test("a torn hook write is ignored, not fatal — transcript still answers", async () => {
    writeFileSync(join(stateDir, "h7.json"), '{"state":"run');
    const tp = transcript([assistantRec], 5_000);
    const got = await sessionTurnState({ sessionId: "h7", transcriptPath: tp });
    expect(got).toEqual({ state: "running", source: "transcript" });
  });

  test("a ticking transcript keeps winning as the turn progresses", async () => {
    hook("h8", "running", 1_000);
    const tp = transcript([assistantRec], 2_000);
    expect((await sessionTurnState({ sessionId: "h8", transcriptPath: tp }))?.state).toBe("running");
    // Turn ends: transcript gains a boundary and stays the newest writer.
    writeFileSync(tp, [assistantRec, turnEnd].map((l) => JSON.stringify(l)).join("\n") + "\n");
    utimesSync(tp, new Date(at(3_000)), new Date(at(3_000)));
    __resetTurnStateCache();
    expect((await sessionTurnState({ sessionId: "h8", transcriptPath: tp }))?.state).toBe("idle");
  });
});

/**
 * The stall guard. Every layer here is edge-triggered on a turn boundary, so a
 * turn that dies mid-flight (upstream 403, killed child) leaves BOTH the hook and
 * the transcript stranded at "running" with no closing edge to ever arrive. These
 * pin the level-triggered check that demotes it.
 * See `.claude/diagnosis-stop-close-noop-20260806.md`.
 */
describe("stall guard", () => {
  const OLD = -(STALL_MS + 60_000); // one minute past the threshold

  test("a running transcript verdict that stopped growing is demoted to idle", async () => {
    const tp = transcript([assistantRec], OLD);
    const got = await sessionTurnState({ sessionId: "s1", transcriptPath: tp });
    expect(got).toEqual({ state: "idle", source: "transcript", stalled: true });
  });

  test("a running HOOK verdict that stopped speaking is demoted too", async () => {
    // The exact shape that latched: `UserPromptSubmit` wrote running, the turn
    // died before `Stop` could fire, and the hook had no closing edge either.
    hook("s2", "running", OLD);
    const got = await sessionTurnState({ sessionId: "s2", transcriptPath: join(dir, "gone.jsonl") });
    expect(got).toEqual({ state: "idle", source: "hook", stalled: true });
  });

  test("BOTH layers stale and both saying running → still idle", async () => {
    hook("s3", "running", OLD);
    const tp = transcript([assistantRec], OLD + 1_000);
    expect((await sessionTurnState({ sessionId: "s3", transcriptPath: tp }))?.state).toBe("idle");
  });

  test("a quiet but live turn is NOT stalled — one long tool call must survive", async () => {
    // 14 minutes of silence is a Bash call with a 10-minute timeout, not a stall.
    const tp = transcript([assistantRec], -(14 * 60_000));
    const got = await sessionTurnState({ sessionId: "s4", transcriptPath: tp });
    expect(got).toEqual({ state: "running", source: "transcript" });
  });

  test("idle is never 'demoted' — the guard only ever touches running", async () => {
    const tp = transcript([assistantRec, turnEnd], OLD);
    const got = await sessionTurnState({ sessionId: "s5", transcriptPath: tp });
    expect(got).toEqual({ state: "idle", source: "transcript" });
    expect(got?.stalled).toBeUndefined(); // a finished turn is not a stalled one
  });

  test("the DECIDING layer's clock is used, not the freshest one", async () => {
    // A fresh hook must not vouch for a transcript that stopped growing. Here the
    // transcript is newer than the hook, so the transcript decides — and it is
    // stale, so the verdict is stalled even though `hook.at` is recent.
    hook("s6", "idle", OLD - 5_000);
    const tp = transcript([assistantRec], OLD);
    const got = await sessionTurnState({ sessionId: "s6", transcriptPath: tp });
    expect(got).toEqual({ state: "idle", source: "transcript", stalled: true });
  });

  test("an unstat-able transcript is reported as-is, never demoted on a guess", async () => {
    const tp = transcript([assistantRec], 0);
    rmSync(tp);
    __resetTurnStateCache();
    // Nothing readable at all now → no opinion, not a fabricated idle.
    expect(await sessionTurnState({ sessionId: "s7", transcriptPath: tp })).toBeNull();
  });

  test("the threshold is honoured exactly at the boundary", async () => {
    const tp = transcript([assistantRec], -STALL_MS);
    // now - at === STALL_MS, and the guard is a strict `>`, so this still counts.
    const got = await sessionTurnState({ sessionId: "s8", transcriptPath: tp, now: at(0) });
    expect(got?.state).toBe("running");
  });
});

/**
 * SC3's integration half: a REAL interrupted transcript from the corpus, replayed
 * against a stale `running` hook. Fixtures can encode my assumptions; a file the
 * product actually produced cannot.
 */
describe("SC3 — real interrupted transcript", () => {
  test("resolves idle even with a stale running hook", async () => {
    const real = process.env.LFG_TEST_INTERRUPTED_TRANSCRIPT;
    if (!real) return; // supplied by the live check; unit run stays hermetic
    hook("real", "running", 1);
    const got = await sessionTurnState({ sessionId: "real", transcriptPath: real });
    expect(got?.state).toBe("idle");
  });
});

/**
 * `resolveBusy` is the shared last step of the derivation. It exists because the
 * journal pump and the push watcher each had their own copy and the copies
 * drifted — the watcher's skipped the hook layer and the stall guard, so the Live
 * Activity counter climbed and never came down.
 * See `.claude/diagnosis-live-activity-background-updates.md`.
 */
describe("resolveBusy", () => {
  test("a running verdict is busy, and the pane does not get a vote", () => {
    const verdict = { state: "running", source: "transcript" } as const;
    expect(resolveBusy({ verdict, paneBusy: false })).toBe(true);
  });

  test("an idle verdict is NOT busy even when the pane still shows a spinner", () => {
    // The pane keeps the last frame it painted, so it reads busy long after the
    // turn ends. A layer that actually has an opinion must out-rank it.
    const verdict = { state: "idle", source: "transcript" } as const;
    expect(resolveBusy({ verdict, paneBusy: true })).toBe(false);
  });

  test("only an abstaining verdict falls through to the pane", () => {
    expect(resolveBusy({ verdict: null, paneBusy: true })).toBe(true);
    expect(resolveBusy({ verdict: null, paneBusy: false })).toBe(false);
  });

  test("delegation overrides every layer — the codex child owns the pane", () => {
    const verdict = { state: "idle", source: "hook" } as const;
    expect(resolveBusy({ verdict, paneBusy: false, delegated: true })).toBe(true);
    expect(resolveBusy({ verdict: null, paneBusy: false, delegated: true })).toBe(true);
  });

  test("SC2: a STALLED verdict is not busy — the regression that inflated the card", async () => {
    // End-to-end through the real arbitration: a transcript whose last record is
    // `assistant` (a turn in flight) that stopped growing past the threshold.
    // `transcriptTurnState` alone still calls this "running"; that bare call is
    // what the push watcher used to make, and why finished sessions kept their
    // slot on the Lock Screen counter.
    const tp = transcript([assistantRec], -(STALL_MS + 60_000));
    const verdict = await sessionTurnState({ sessionId: "stalled", transcriptPath: tp });
    expect(verdict).toEqual({ state: "idle", source: "transcript", stalled: true });
    expect(resolveBusy({ verdict, paneBusy: true })).toBe(false);
  });
});

process.on("exit", () => {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {}
});
