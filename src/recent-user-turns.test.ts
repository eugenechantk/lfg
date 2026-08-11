import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { recentUserTurns } from "./sessions.ts";

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
