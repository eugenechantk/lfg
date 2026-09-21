import { afterAll, describe, expect, test } from "bun:test";
import { appendFileSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { allUserTurns, recentUserTurns } from "./sessions.ts";

const dir = mkdtempSync(join(tmpdir(), "lfg-turns-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

let seq = 0;
function transcript(lines: unknown[]): string {
  const p = join(dir, `t${seq++}.jsonl`);
  writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  return p;
}

const user = (text: string) => ({ type: "user", message: { content: text } });
const assistant = (text: string) => ({
  type: "assistant",
  message: { role: "assistant", content: [{ type: "text", text }] },
});
/** A tool result — recorded as a `user` turn, and vastly more common than real ones. */
const toolResult = (text: string) => ({
  type: "user",
  toolUseResult: { stdout: text },
  message: { content: [{ type: "tool_result", content: text }] },
});

describe("recentUserTurns", () => {
  test("returns human turns oldest-first", () => {
    const p = transcript([user("first"), assistant("ok"), user("second"), user("third")]);
    return expect(recentUserTurns(p, 6)).resolves.toEqual(["first", "second", "third"]);
  });

  test("returns at most n, keeping the NEWEST n", async () => {
    const p = transcript([user("a"), user("b"), user("c"), user("d")]);
    expect(await recentUserTurns(p, 2)).toEqual(["c", "d"]);
  });

  test("excludes tool results even when they carry text", async () => {
    const p = transcript([user("real one"), toolResult("build output"), toolResult("more")]);
    expect(await recentUserTurns(p, 6)).toEqual(["real one"]);
  });

  test("excludes command/caveat wrapper turns", async () => {
    const p = transcript([
      user("<command-name>/clear</command-name>"),
      user("<local-command-stdout>done</local-command-stdout>"),
      user("real one"),
    ]);
    expect(await recentUserTurns(p, 6)).toEqual(["real one"]);
  });

  test("excludes the interrupt marker Claude Code writes as a user turn", async () => {
    const p = transcript([
      user("real one"),
      user("[Request interrupted by user]"),
      user("[Request interrupted by user for tool use]"),
    ]);
    expect(await recentUserTurns(p, 6)).toEqual(["real one"]);
  });

  test("excludes meta turns", async () => {
    const p = transcript([{ ...user("meta noise"), isMeta: true }, user("real one")]);
    expect(await recentUserTurns(p, 6)).toEqual(["real one"]);
  });

  test("truncates long turns", async () => {
    const p = transcript([user("x".repeat(500))]);
    const [t] = await recentUserTurns(p, 6, { maxChars: 50 });
    expect(t).toHaveLength(50);
    expect(t.endsWith("…")).toBe(true);
  });

  test("widens the window until it finds sparse human turns", async () => {
    // The regression this exists for: in a real agentic session the tail is all
    // assistant output and tool results, and the human's turns are megabytes
    // back. A fixed window returned 0 turns for exactly the long, drifted
    // sessions the retitle task is meant to fix.
    const filler = Array.from({ length: 400 }, (_, i) => assistant("y".repeat(500) + i));
    const p = transcript([user("buried deep"), ...filler]);
    expect(await recentUserTurns(p, 6, { startBytes: 4096 })).toEqual(["buried deep"]);
  });

  test("respects the byte budget rather than reading forever", async () => {
    const filler = Array.from({ length: 400 }, (_, i) => assistant("y".repeat(500) + i));
    const p = transcript([user("buried deep"), ...filler]);
    // Budget far smaller than the distance back to the human turn.
    expect(await recentUserTurns(p, 6, { startBytes: 512, maxBytes: 1024 })).toEqual([]);
  });

  test("an empty or missing transcript yields no turns", async () => {
    expect(await recentUserTurns(transcript([]), 6)).toEqual([]);
    expect(await recentUserTurns(join(dir, "nope.jsonl"), 6)).toEqual([]);
  });

  test("collapses whitespace so a multi-line prompt stays one line", async () => {
    const p = transcript([user("line one\n\n  line two")]);
    expect(await recentUserTurns(p, 6)).toEqual(["line one line two"]);
  });
});

describe("allUserTurns", () => {
  test("returns every human turn oldest-first rather than only the newest six", async () => {
    const p = transcript(Array.from({ length: 10 }, (_, i) => user(`message ${i + 1}`)));
    const result = await allUserTurns(p);
    expect(result.turns).toEqual(Array.from({ length: 10 }, (_, i) => `message ${i + 1}`));
    expect(result.nextByte).toBe(statSync(p).size);
  });

  test("extracts Codex user messages and excludes non-user event rows", async () => {
    const p = transcript([
      {
        timestamp: "2026-08-20T00:00:00Z",
        type: "event_msg",
        payload: { type: "user_message", message: "first Codex request" },
      },
      {
        timestamp: "2026-08-20T00:00:01Z",
        type: "event_msg",
        payload: { type: "agent_message", message: "assistant reply" },
      },
      {
        timestamp: "2026-08-20T00:00:02Z",
        type: "event_msg",
        payload: { type: "user_message", message: "related follow-up" },
      },
    ]);
    expect((await allUserTurns(p)).turns).toEqual([
      "first Codex request",
      "related follow-up",
    ]);
  });

  test("supports scanning only bytes appended after a checkpoint", async () => {
    const p = transcript([user("first"), assistant("ok"), user("second")]);
    const first = await allUserTurns(p);
    appendFileSync(p, JSON.stringify(user("third")) + "\n");

    const appended = await allUserTurns(p, { startByte: first.nextByte });
    expect(appended.turns).toEqual(["third"]);
    expect(appended.nextByte).toBe(statSync(p).size);
  });

  test("does not checkpoint an incomplete trailing JSON row", async () => {
    const p = join(dir, `t${seq++}.jsonl`);
    const row = JSON.stringify(user("arrived in two writes"));
    const split = Math.floor(row.length / 2);
    writeFileSync(p, row.slice(0, split));

    const first = await allUserTurns(p);
    expect(first).toEqual({ turns: [], nextByte: 0 });

    appendFileSync(p, row.slice(split) + "\n");
    const completed = await allUserTurns(p, { startByte: first.nextByte });
    expect(completed.turns).toEqual(["arrived in two writes"]);
    expect(completed.nextByte).toBe(statSync(p).size);
  });

  test("applies the same filtering, whitespace cleanup, and truncation as recent turns", async () => {
    const p = transcript([
      user("<command-name>/clear</command-name>"),
      toolResult("tool output"),
      { ...user("meta noise"), isMeta: true },
      user("real\n\n message"),
      user("x".repeat(100)),
    ]);
    expect((await allUserTurns(p, { maxChars: 20 })).turns).toEqual([
      "real message",
      "x".repeat(19) + "…",
    ]);
  });
});

describe("allUserTurns bounds", () => {
  test("maxBytes stops the scan at the byte budget", async () => {
    const p = transcript([user("first"), user("second"), user("third")]);
    const firstRowBytes = Buffer.byteLength(JSON.stringify(user("first"))) + 1;
    const bounded = await allUserTurns(p, { maxBytes: firstRowBytes + 4 });
    // The row cut by the budget is an incomplete JSON line and is skipped.
    expect(bounded.turns).toEqual(["first"]);
    expect(bounded.nextByte).toBe(firstRowBytes);
    expect((await allUserTurns(p)).turns).toEqual(["first", "second", "third"]);
  });

  test("a byte budget short of EOF on a multi-chunk file still terminates", async () => {
    // Bun 1.3.14: a sliced file stream that stops short of EOF delivers its
    // bytes and then never ends. The reader must leave by counting, not wait.
    const rows = Array.from({ length: 2_000 }, (_, i) => user(`row ${i} ${"x".repeat(200)}`));
    const p = transcript(rows);
    const size = statSync(p).size;
    expect(size).toBeGreaterThan(256 * 1024);
    const started = performance.now();
    const { turns, nextByte } = await allUserTurns(p, { maxBytes: Math.floor(size / 2) });
    expect(performance.now() - started).toBeLessThan(5_000);
    expect(turns.length).toBeGreaterThan(500);
    expect(turns.length).toBeLessThan(2_000);
    expect(nextByte).toBeLessThanOrEqual(Math.floor(size / 2));
  }, 10_000);

  test("maxTotalChars stops reading once enough user text is in hand", async () => {
    const p = transcript([user("aaaa"), user("bbbb"), user("cccc"), user("dddd")]);
    const { turns, nextByte } = await allUserTurns(p, { maxTotalChars: 7 });
    expect(turns).toEqual(["aaaa", "bbbb"]);
    expect(nextByte).toBeLessThan(statSync(p).size);
  });
});
