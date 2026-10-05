import { test, expect, describe, beforeEach } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, rmSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sessionTurnState } from "./session-state.ts";
import { __resetHookStateCache } from "./hook-state.ts";
import { __resetTurnStateCache } from "./turn-state.ts";
import {
  interruptBaseline,
  noteConfirmedInterrupt as noteMark,
  __resetInterruptMarks,
} from "./interrupt-marks.ts";

/** Baseline and confirm at once — the common case for these fixtures. */
const noteConfirmedInterrupt = (sid: string, tp: string, at: number) =>
  noteMark(sid, interruptBaseline(tp, at));

const dir = mkdtempSync(join(tmpdir(), "interrupt-marks-"));
process.env.LFG_AGENT_STATE_DIR = join(dir, "agent-state");
mkdirSync(process.env.LFG_AGENT_STATE_DIR, { recursive: true });

let n = 0;
const now = Date.now();

// The shape `lfg-e4d53c` left on 2026-10-04: a prompt, its context attachments,
// then nothing — Escape landed before the first assistant row, so Claude Code put
// the prompt back in the composer and wrote no `[Request interrupted` marker.
const prompt = { type: "user", message: { role: "user", content: "cut a new build" } };
const attachment = { type: "attachment", attachment: { type: "environment" } };
const assistantRec = { type: "assistant", message: { role: "assistant", content: [] } };
const aiTitle = { type: "ai-title", aiTitle: "Cut a build" };
const lastPrompt = { type: "last-prompt", lastPrompt: "cut a new build" };

const transcript = (lines: unknown[]): { sid: string; tp: string } => {
  const sid = `sid-${n++}`;
  const tp = join(dir, `${sid}.jsonl`);
  writeFileSync(tp, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  return { sid, tp };
};
const append = (tp: string, ...lines: unknown[]) =>
  appendFileSync(tp, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");

/** The hook writes turn state into the lease beside the transcript. */
const hook = (sid: string, state: string, stateAt: number) =>
  writeFileSync(
    join(dir, `${sid}.lease.json`),
    JSON.stringify({ hostId: "h", pid: 1, acquiredAt: 1, heartbeatAt: 1, state, stateAt }),
  );

const verdict = (sid: string, tp: string) =>
  sessionTurnState({ sessionId: sid, transcriptPath: tp, now });

beforeEach(() => {
  __resetHookStateCache();
  __resetTurnStateCache();
  __resetInterruptMarks();
});

describe("a confirmed stop closes a turn the transcript cannot close", () => {
  test("no mark, no change: the rewind shape alone reads running", async () => {
    const { sid, tp } = transcript([prompt, attachment]);
    expect(await verdict(sid, tp)).toEqual({ state: "running", source: "transcript" });
  });

  test("rewind case: stop confirmed before the first reply → idle", async () => {
    const { sid, tp } = transcript([prompt, attachment]);
    noteConfirmedInterrupt(sid, tp, now);
    expect(await verdict(sid, tp)).toEqual({ state: "idle", source: "interrupt" });
  });

  test("metadata after stop does not re-open the turn", async () => {
    const { sid, tp } = transcript([prompt, attachment]);
    noteConfirmedInterrupt(sid, tp, now);
    append(tp, aiTitle, lastPrompt);
    expect((await verdict(sid, tp))?.state).toBe("idle");
    // …and stays closed on the next tick, once those bytes are already checked.
    __resetTurnStateCache();
    expect((await verdict(sid, tp))?.state).toBe("idle");
  });

  test("concurrent readers in one tick do not double-count checked bytes", async () => {
    // The pump, push watcher and REST list share the marks and poll together.
    const { sid, tp } = transcript([prompt, attachment]);
    noteConfirmedInterrupt(sid, tp, now);
    append(tp, aiTitle, lastPrompt);
    const both = await Promise.all([verdict(sid, tp), verdict(sid, tp)]);
    expect(both.map((v) => v?.state)).toEqual(["idle", "idle"]);
    // Double-counting would leave the mark past EOF, and a quiet tick drops it.
    expect(await verdict(sid, tp)).toEqual({ state: "idle", source: "interrupt" });
    append(tp, prompt);
    expect((await verdict(sid, tp))?.state).toBe("running");
  });

  test("a queued message that starts before the stop is confirmed → running", async () => {
    // Steer: Eugene's message sat in Claude's own queue; the Escape releases it.
    const { sid, tp } = transcript([prompt, attachment]);
    const baseline = interruptBaseline(tp, now - 1_000); // before the Escape
    append(tp, prompt); // the queued turn's user row lands mid-confirm
    noteMark(sid, baseline); // stop confirmed afterwards
    expect(await verdict(sid, tp)).toEqual({ state: "running", source: "transcript" });
  });

  test("new prompt after stop → running again", async () => {
    const { sid, tp } = transcript([prompt, attachment]);
    noteConfirmedInterrupt(sid, tp, now);
    expect((await verdict(sid, tp))?.state).toBe("idle");
    append(tp, lastPrompt, prompt);
    expect(await verdict(sid, tp)).toEqual({ state: "running", source: "transcript" });
  });

  test("assistant output after stop (the stop did not take) → running again", async () => {
    const { sid, tp } = transcript([prompt]);
    noteConfirmedInterrupt(sid, tp, now);
    append(tp, assistantRec);
    expect((await verdict(sid, tp))?.state).toBe("running");
    // A superseded mark is gone for good — later metadata cannot revive it.
    append(tp, aiTitle);
    expect((await verdict(sid, tp))?.state).toBe("running");
  });

  test("hook announcing a new turn after the stop → running again", async () => {
    const { sid, tp } = transcript([prompt]);
    // Transcript written before the hook spoke, so the hook decides arbitration.
    utimesSync(tp, new Date(now - 8_000), new Date(now - 8_000));
    hook(sid, "running", now - 5_000);
    noteConfirmedInterrupt(sid, tp, now - 3_000);
    expect((await verdict(sid, tp))?.state).toBe("idle");
    __resetHookStateCache();
    hook(sid, "running", now - 1_000); // UserPromptSubmit for the next prompt
    expect(await verdict(sid, tp)).toEqual({ state: "running", source: "hook" });
  });

  test("an idle verdict is left alone", async () => {
    const turnEnd = { type: "system", subtype: "turn_duration" };
    const { sid, tp } = transcript([prompt, assistantRec, turnEnd]);
    noteConfirmedInterrupt(sid, tp, now);
    expect(await verdict(sid, tp)).toEqual({ state: "idle", source: "transcript" });
  });

  test("a mark is per session", async () => {
    const a = transcript([prompt]);
    const b = transcript([prompt]);
    noteConfirmedInterrupt(a.sid, a.tp, now);
    expect((await verdict(a.sid, a.tp))?.state).toBe("idle");
    expect((await verdict(b.sid, b.tp))?.state).toBe("running");
  });

  test("a transcript that vanished after the stop → no opinion", async () => {
    const { sid, tp } = transcript([prompt]);
    noteConfirmedInterrupt(sid, tp, now);
    rmSync(tp);
    // No transcript and no hook → no opinion, the caller's pane fallback decides.
    expect(await verdict(sid, tp)).toBeNull();
  });
});
