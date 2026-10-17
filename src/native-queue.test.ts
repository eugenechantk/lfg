import { describe, expect, test } from "bun:test";
import { recalledClaudeMessages, retractCodexQueueEntry, clearRecalledDraftKeys, canRecallClaudeQueue } from "./native-queue.ts";

describe("Claude native queue recall receipts", () => {
  test("does not recall history or overwrite a terminal draft after delivery", () => {
    const pane = (text: string) => `──────────\n❯ ${text}\n──────────\n`;
    expect(canRecallClaudeQueue(pane("Press up to edit queued messages"))).toBe(true);
    expect(canRecallClaudeQueue(pane(""))).toBe(false);
    expect(canRecallClaudeQueue(pane("a person's unfinished draft"))).toBe(false);
    expect(canRecallClaudeQueue(null)).toBe(false);
  });
  test("only popAll receipts prove recall; enqueue and consumption do not", () => {
    const lines = [
      { type: "queue-operation", operation: "enqueue", content: "waiting" },
      { type: "queue-operation", operation: "remove", reason: "absorbed_mid_turn", content: "consumed" },
      { type: "queue-operation", operation: "popAll", content: "first\nsecond" },
      { type: "queue-operation", operation: "popAll", content: "keep sibling" },
      { type: "user", operation: "popAll", content: "unrelated" },
    ].map(x => JSON.stringify(x));
    expect(recalledClaudeMessages(lines)).toEqual(["first\nsecond", "keep sibling"]);
  });

  test("preserves duplicate messages, whitespace, and large payloads exactly", () => {
    const text = "  original\n".repeat(8_000);
    const line = JSON.stringify({ type: "queue-operation", operation: "popAll", content: text });
    expect(recalledClaudeMessages(["partial json", line, line])).toEqual([text, text]);
  });

  test("clears every logical line of a recalled draft without Escape", () => {
    const keys = clearRecalledDraftKeys("first\nsecond\nthird");
    expect(keys.filter(x => x === "C-u").length).toBeGreaterThanOrEqual(4);
    expect(keys).not.toContain("Escape");
    expect(keys).not.toContain("Enter");
  });
});

describe("Codex native queue deletion", () => {
  const entry = (id: string, text: string, clientId = id) => ({
    id, clientUserMessageId: clientId, input: [{ type: "text", text }],
  });

  test("deletes the exact client receipt and leaves same-text siblings alone", async () => {
    const calls: unknown[] = [];
    const request = async (method: string, params: unknown) => {
      calls.push([method, params]);
      return method === "thread/queue/list"
        ? { data: [entry("other", "same"), entry("mine", "same", "client-1")], nextCursor: null }
        : { deleted: true };
    };
    expect(await retractCodexQueueEntry(request, "session", "client-1", "same")).toBe(true);
    expect(calls.at(-1)).toEqual(["thread/queue/delete", { threadId: "session", queuedSubmissionId: "mine" }]);
  });

  test("pages the queue and matches a unique full text for legacy TUI receipts", async () => {
    const calls: any[] = [];
    const request = async (method: string, params: any) => {
      calls.push([method, params]);
      if (method === "thread/queue/delete") return { deleted: true };
      return params.cursor ? { data: [entry("mine", "full message")], nextCursor: null }
        : { data: [entry("prefix", "full message with extra words")], nextCursor: "next" };
    };
    expect(await retractCodexQueueEntry(request, "session", "legacy", "full message")).toBe(true);
    expect(calls.at(-1)[1].queuedSubmissionId).toBe("mine");
  });

  test("does not guess between identical legacy entries", async () => {
    const calls: string[] = [];
    const request = async (method: string) => {
      calls.push(method);
      return { data: [entry("a", "same"), entry("b", "same")], nextCursor: null };
    };
    expect(await retractCodexQueueEntry(request, "session", "legacy", "same")).toBe(false);
    expect(calls).toEqual(["thread/queue/list"]);
  });

  test("a lost deletion race or absent entry is not a successful retraction", async () => {
    expect(await retractCodexQueueEntry(async () => ({ data: [], nextCursor: null }), "s", "c", "gone")).toBeNull();
    expect(await retractCodexQueueEntry(async method => method.endsWith("list")
      ? { data: [entry("mine", "text", "c")], nextCursor: null } : { deleted: false }, "s", "c", "text")).toBe(false);
  });
});
