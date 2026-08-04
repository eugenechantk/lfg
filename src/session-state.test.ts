import { test, expect, describe, beforeEach } from "bun:test";
import { mkdtempSync, writeFileSync, utimesSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sessionTurnState } from "./session-state.ts";
import { __resetHookStateCache } from "./hook-state.ts";
import { __resetTurnStateCache } from "./turn-state.ts";

const dir = mkdtempSync(join(tmpdir(), "session-state-"));
const stateDir = join(dir, "agent-state");
process.env.LFG_AGENT_STATE_DIR = stateDir;
require("node:fs").mkdirSync(stateDir, { recursive: true });

let n = 0;

/** Write hook-owned fields into the LEASE, where the hook now writes them.
 *  Every fixture transcript lives in `dir`, so the lease path for any of them is
 *  `dir/<sid>.lease.json`. lfg's liveness fields are included to prove the
 *  arbitration reads the shared record without disturbing them. */
const hook = (sid: string, state: string, at: number) =>
  writeFileSync(
    join(dir, `${sid}.lease.json`),
    JSON.stringify({ hostId: "host-a", pid: 1, acquiredAt: 1, heartbeatAt: 1, state, stateAt: at }),
  );

/** Write a transcript whose mtime is pinned to `mtimeMs`. */
const transcript = (lines: unknown[], mtimeMs: number): string => {
  const p = join(dir, `t${n++}.jsonl`);
  writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  utimesSync(p, new Date(mtimeMs), new Date(mtimeMs));
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
    utimesSync(tp, new Date(3_000), new Date(3_000));
    __resetTurnStateCache();
    expect((await sessionTurnState({ sessionId: "h8", transcriptPath: tp }))?.state).toBe("idle");
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

process.on("exit", () => {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {}
});
