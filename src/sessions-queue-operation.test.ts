import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { normalizeLineMessages, recentMessages } from "./sessions.ts";

// Claude Code ≥ 2.1.2xx records its native message queue in the transcript as
// `queue-operation` lines. A message sent mid-turn is `enqueue`d and then —
// instead of running as its own turn — absorbed into the running turn and
// `remove`d with `reason: "absorbed_mid_turn"`. The text is persisted nowhere
// else, so the normaliser must synthesise the user turn from that line or the
// message vanishes from every client and the send queue re-drives it.
// See .claude/diagnosis-queued-messages-absorbed-mid-turn-20260907.md.

const TS = "2026-09-07T07:29:35.656Z";
const TEXT = "s5-5 and s5-6 radar chart is different from the web version make it identical";

const op = (operation: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({
    type: "queue-operation",
    operation,
    timestamp: TS,
    sessionId: "038215e0-c074-4a4d-aafc-91e672d6e5b4",
    ...extra,
  });

describe("normalizeLineMessages: queue-operation", () => {
  test("an absorbed removal becomes a user text turn with the line's timestamp", () => {
    const msgs = normalizeLineMessages(op("remove", { content: TEXT, reason: "absorbed_mid_turn" }));
    expect(msgs).toHaveLength(1);
    expect(msgs[0]).toMatchObject({ role: "user", kind: "text", text: TEXT, ts: Date.parse(TS) });
  });

  test("the synthetic id is stable across re-reads and distinct per message", () => {
    const line = op("remove", { content: TEXT, reason: "absorbed_mid_turn" });
    const [a] = normalizeLineMessages(line);
    const [b] = normalizeLineMessages(line);
    const [c] = normalizeLineMessages(op("remove", { content: TEXT + " please", reason: "absorbed_mid_turn" }));
    expect(a.id).toBeTruthy();
    expect(a.id).toBe(b.id);
    expect(a.id).not.toBe(c.id);
  });

  test("every consumption reason Claude Code writes is treated as delivered", () => {
    for (const reason of ["absorbed_mid_turn", "delivered_to_agent", "delivered_as_tool_result"]) {
      expect(normalizeLineMessages(op("remove", { content: TEXT, reason }))).toHaveLength(1);
    }
  });

  test("enqueue and dequeue yield nothing (the real user turn follows a dequeue)", () => {
    expect(normalizeLineMessages(op("enqueue", { content: TEXT }))).toEqual([]);
    expect(normalizeLineMessages(op("dequeue"))).toEqual([]);
  });

  test("a removal for any other reason is not a delivery", () => {
    expect(normalizeLineMessages(op("remove", { content: TEXT, reason: "aborted" }))).toEqual([]);
    expect(normalizeLineMessages(op("remove", { content: TEXT }))).toEqual([]);
  });

  test("Claude Code's own poll events routed through the queue are not conversation", () => {
    const notif = "<task-notification>\n<task-id>b72i5v6qn</task-id>\n</task-notification>";
    expect(normalizeLineMessages(op("remove", { content: notif, reason: "absorbed_mid_turn" }))).toEqual([]);
    expect(normalizeLineMessages(op("remove", { content: "   ", reason: "absorbed_mid_turn" }))).toEqual([]);
  });
});

describe("recentMessages sees absorbed turns in file order", () => {
  const dir = mkdtempSync(join(tmpdir(), "lfg-queue-op-"));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  test("an absorbed message surfaces as a user turn between the tool calls it rode with", async () => {
    const p = join(dir, "t.jsonl");
    const lines = [
      JSON.stringify({ type: "user", timestamp: TS, uuid: "u1", message: { role: "user", content: "kick off" } }),
      JSON.stringify({
        type: "assistant",
        timestamp: TS,
        uuid: "a1",
        message: { role: "assistant", content: [{ type: "tool_use", name: "Bash", input: { command: "ls" } }] },
      }),
      op("enqueue", { content: TEXT }),
      op("remove", { content: TEXT, reason: "absorbed_mid_turn" }),
      JSON.stringify({
        type: "user",
        timestamp: TS,
        uuid: "r1",
        toolUseResult: {},
        message: { role: "user", content: [{ type: "tool_result", content: "ok" }] },
      }),
    ];
    writeFileSync(p, lines.join("\n") + "\n");
    const msgs = await recentMessages(p, 40);
    const userTexts = msgs.filter((m) => m.role === "user" && m.kind === "text").map((m) => m.text);
    expect(userTexts).toEqual(["kick off", TEXT]);
    // Positioned where it was absorbed: after the tool_use, before its result.
    const idx = msgs.findIndex((m) => m.text === TEXT);
    expect(msgs[idx - 1]?.kind).toBe("tool_use");
    expect(msgs[idx + 1]?.kind).toBe("tool_result");
  });
});
