import { test, expect, describe, beforeEach } from "bun:test";
import { mkdtempSync, writeFileSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  classifyTurnLine,
  transcriptTurnState,
  __resetTurnStateCache,
  __turnStateScanCount,
} from "./turn-state.ts";

const dir = mkdtempSync(join(tmpdir(), "turn-state-"));
let n = 0;
const write = (lines: unknown[]): string => {
  const p = join(dir, `t${n++}.jsonl`);
  writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  return p;
};

const assistant = (text: string) => ({
  type: "assistant",
  message: { role: "assistant", content: [{ type: "text", text }] },
  timestamp: "2026-08-04T10:00:00.000Z",
});
const toolUse = () => ({
  type: "assistant",
  message: { role: "assistant", content: [{ type: "tool_use", name: "Bash", input: {} }] },
});
const toolResult = () => ({
  type: "user",
  message: { role: "user", content: [{ type: "tool_result", content: "ok" }] },
});
const prompt = (text: string) => ({
  type: "user",
  promptSource: "typed",
  message: { role: "user", content: text },
});
const interrupted = () => ({
  type: "user",
  message: { role: "user", content: "[Request interrupted by user]" },
});
const turnEnd = () => ({ type: "system", subtype: "turn_duration", durationMs: 1234 });
const awaySummary = () => ({ type: "system", subtype: "away_summary" });
const stopHook = () => ({ type: "system", subtype: "stop_hook_summary", stopReason: "" });

beforeEach(() => __resetTurnStateCache());

describe("classifyTurnLine", () => {
  test("turn_duration ends the turn", () => {
    expect(classifyTurnLine(JSON.stringify(turnEnd()))).toBe("idle");
  });

  test("assistant output means a turn is in flight", () => {
    expect(classifyTurnLine(JSON.stringify(assistant("hi")))).toBe("running");
  });

  test("a typed prompt starts a turn immediately", () => {
    expect(classifyTurnLine(JSON.stringify(prompt("do the thing")))).toBe("running");
  });

  test("bookkeeping records are not decisive", () => {
    for (const r of [awaySummary(), stopHook(), { type: "mode" }, { type: "ai-title" }]) {
      expect(classifyTurnLine(JSON.stringify(r))).toBeNull();
    }
  });

  test("unparseable line is not decisive", () => {
    expect(classifyTurnLine("{ truncated")).toBeNull();
    expect(classifyTurnLine("")).toBeNull();
  });
});

describe("transcriptTurnState", () => {
  // SC1
  test("finished turn → idle", async () => {
    const p = write([prompt("go"), assistant("done"), stopHook(), turnEnd()]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  // away_summary is appended MINUTES after turn_duration; it must not re-open
  // the turn, and it must not be mistaken for a message either.
  test("away_summary after the turn end → still idle", async () => {
    const p = write([assistant("done"), turnEnd(), awaySummary()]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  // SC3
  test("turn in flight → running", async () => {
    const p = write([turnEnd(), prompt("next"), toolUse(), toolResult()]);
    expect(await transcriptTurnState(p)).toBe("running");
  });

  test("prompt submitted, no assistant record yet → running", async () => {
    const p = write([assistant("prev"), turnEnd(), prompt("next")]);
    expect(await transcriptTurnState(p)).toBe("running");
  });

  // SC2 — the case that makes this whole design viable. An interrupted turn
  // NEVER writes turn_duration (measured: session 82dedc0e, 1 prompt, 0 turn
  // ends, ends on the interrupt marker). Without this the signal would latch
  // busy on every steering send, which is more common than the bug it replaces.
  test("interrupted turn with no turn_duration → idle", async () => {
    const p = write([prompt("go"), toolUse(), toolResult(), interrupted()]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  test("interrupt followed by a new prompt → running again", async () => {
    const p = write([toolUse(), interrupted(), prompt("actually do this instead")]);
    expect(await transcriptTurnState(p)).toBe("running");
  });

  // SC4
  test("codex / unrecognized transcript → null so the caller keeps its fallback", async () => {
    const p = write([
      { record_type: "state", payload: { id: "x" } },
      { record_type: "event_msg", payload: { type: "agent_message" } },
    ]);
    expect(await transcriptTurnState(p)).toBeNull();
  });

  test("missing or empty file → null", async () => {
    expect(await transcriptTurnState(join(dir, "nope.jsonl"))).toBeNull();
    const p = join(dir, "empty.jsonl");
    writeFileSync(p, "");
    expect(await transcriptTurnState(p)).toBeNull();
  });

  // SC5 — the whole point. The old pane scrape matched these strings in agent
  // OUTPUT; here they are message payload and must be inert.
  test("agent prose quoting the pane markers cannot move the signal", async () => {
    const prose =
      'A hung pane still shows esc to interrupt, and the meter reads ' +
      '"✶ Crunching… (5m 50s · ↓ 2.2k tokens)".';
    const p = write([prompt("explain busy detection"), assistant(prose), turnEnd()]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  // The decisive record can sit behind a tool result far larger than the initial
  // scan window; scanBack must grow rather than report a miss.
  test("decisive record buried behind a huge tool result → still found", async () => {
    const huge = {
      type: "system",
      subtype: "noise",
      blob: "x".repeat(200_000),
    };
    const p = write([assistant("working"), huge]);
    expect(await transcriptTurnState(p)).toBe("running");
  });

  // SC7
  test("unchanged file is not rescanned; growth invalidates", async () => {
    const p = write([assistant("working")]);
    expect(await transcriptTurnState(p)).toBe("running");
    const after = __turnStateScanCount();
    expect(await transcriptTurnState(p)).toBe("running");
    expect(await transcriptTurnState(p)).toBe("running");
    expect(__turnStateScanCount()).toBe(after); // served from cache

    appendFileSync(p, JSON.stringify(turnEnd()) + "\n");
    expect(await transcriptTurnState(p)).toBe("idle");
    expect(__turnStateScanCount()).toBe(after + 1);
  });
});

// ---- codex rollouts (Phase 3) ----
//
// codex uses a different envelope but a stronger signal: turn start AND end are
// explicit and paired, and an interrupt has its own record instead of being an
// absence. Fixtures below mirror real rollout lines from ~/.codex/sessions.

const ev = (t: string) => ({ type: "event_msg", payload: { type: t } });
const codexNoise = { type: "response_item", payload: { type: "function_call" } };

describe("codex rollout vocabulary", () => {
  test("task_started with no end yet → running", () => {
    expect(classifyTurnLine(JSON.stringify(ev("task_started")))).toBe("running");
  });

  test("task_complete → idle", () => {
    expect(classifyTurnLine(JSON.stringify(ev("task_complete")))).toBe("idle");
  });

  // The advantage over Claude Code: an interrupted codex turn says so, instead of
  // silently omitting the end marker and leaving the turn to look open forever.
  test("turn_aborted → idle", () => {
    expect(classifyTurnLine(JSON.stringify(ev("turn_aborted")))).toBe("idle");
  });

  test("mid-turn traffic is not decisive", () => {
    for (const t of ["token_count", "agent_message", "exec_command_end", "user_message"]) {
      expect(classifyTurnLine(JSON.stringify(ev(t)))).toBeNull();
    }
    expect(classifyTurnLine(JSON.stringify(codexNoise))).toBeNull();
    expect(classifyTurnLine(JSON.stringify({ type: "session_meta", payload: { id: "x" } }))).toBeNull();
  });

  test("a running codex turn scans back past noise to task_started", async () => {
    const p = write([ev("task_started"), codexNoise, ev("token_count"), codexNoise]);
    expect(await transcriptTurnState(p)).toBe("running");
  });

  test("a finished codex turn resolves idle", async () => {
    const p = write([ev("task_started"), codexNoise, ev("task_complete")]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  test("an aborted codex turn resolves idle, not a latched running", async () => {
    const p = write([ev("task_started"), codexNoise, ev("turn_aborted")]);
    expect(await transcriptTurnState(p)).toBe("idle");
  });

  test("the newest turn wins across several turns", async () => {
    const p = write([
      ev("task_started"), ev("task_complete"),
      ev("task_started"), ev("task_complete"),
      ev("task_started"), codexNoise,
    ]);
    expect(await transcriptTurnState(p)).toBe("running");
  });
});
