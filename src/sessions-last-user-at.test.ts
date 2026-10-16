import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { lastUserTurnForTest } from "./sessions.ts";

const dir = mkdtempSync(join(tmpdir(), "lfg-last-user-at-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

function transcript(lines: Record<string, unknown>[]): string {
  const path = join(dir, `${crypto.randomUUID()}.jsonl`);
  writeFileSync(path, lines.map((line) => JSON.stringify(line)).join("\n") + "\n");
  return path;
}

describe("lastUserTurn", () => {
  // Shape from a live Claude Code 2.1.280 session (2026-10-15): a message sent
  // mid-tool is absorbed at the tool boundary and written only as queue
  // operations. The turn started at the prompt, not at the absorbed message.
  test("times the turn from the prompt; absorbed messages don't reset it", async () => {
    const path = transcript([
      { type: "user", uuid: "u1", timestamp: "2026-10-15T20:40:14.000Z",
        message: { role: "user", content: "Run the loop twice, then reply done." } },
      { type: "assistant", uuid: "a1", timestamp: "2026-10-15T20:41:01.000Z",
        message: { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "Bash", input: { command: "python3 loop.py" } }] } },
      { type: "queue-operation", operation: "enqueue", timestamp: "2026-10-15T20:41:41.336Z", content: "Reply with ok too." },
      { type: "queue-operation", operation: "remove", reason: "absorbed_mid_turn", timestamp: "2026-10-15T20:41:41.433Z", content: "Reply with ok too." },
      { type: "user", uuid: "r1", timestamp: "2026-10-15T20:41:41.500Z",
        message: { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "0\n1" }] } },
    ]);
    expect(await lastUserTurnForTest(path)).toEqual({
      text: "Run the loop twice, then reply done.",
      ts: Date.parse("2026-10-15T20:40:14.000Z"),
    });
  });

  test("skips Claude's interrupt marker", async () => {
    const path = transcript([
      { type: "user", uuid: "u1", timestamp: "2026-10-15T20:45:00.000Z",
        message: { role: "user", content: "Run the loop." } },
      { type: "user", uuid: "u2", timestamp: "2026-10-15T20:46:30.000Z",
        message: { role: "user", content: [{ type: "text", text: "[Request interrupted by user for tool use]" }] } },
    ]);
    expect(await lastUserTurnForTest(path)).toEqual({ text: "Run the loop.", ts: Date.parse("2026-10-15T20:45:00.000Z") });
  });

  test("a turn without a timestamp still returns its text", async () => {
    const path = transcript([{ type: "user", uuid: "u1", message: { role: "user", content: "hello" } }]);
    expect(await lastUserTurnForTest(path)).toEqual({ text: "hello", ts: null });
  });
});
