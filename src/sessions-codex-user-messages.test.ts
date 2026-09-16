import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  allUserTurns, createCodexNormalizationState, lastUserPromptText,
  messagePage, normalizeLineMessages, recentMessages, recentUserTurns,
} from "./sessions.ts";
import { reconcileQueuedCore, type QueuedMsg } from "./sendq.ts";

const prompt = "Can astra transcribe audio from my videos into different languages?";
const followup = "Does other model do that like 5.6?";
function row(payload: Record<string, unknown>, second: number, type = "response_item") {
  return JSON.stringify({ type, timestamp: new Date(1788690000000 + second * 1000).toISOString(), payload });
}
function user(text: string, second: number, kinds: string[] = ["user.text"]) {
  return row({ type: "message", role: "user", content: [{ type: "input_text", text }],
    internal_chat_message_metadata_passthrough: { turn_id: `turn-${second}`, content_item_kinds: kinds },
  }, second);
}
function assistant(text: string, second: number) {
  return row({ type: "message", role: "assistant", content: [{ type: "output_text", text }] }, second);
}
const lines = [
  user("# AGENTS.md instructions", 1, ["agents_md.instructions"]),
  user("<environment_context>injected</environment_context>", 2, ["environments.environment_context"]),
  user(prompt, 3), assistant("First response", 4),
  user(followup, 5), assistant("Follow-up response", 6),
];
const expected = [prompt, "First response", followup, "Follow-up response"];
async function fixture(run: (path: string) => Promise<void>, records = lines) {
  const dir = mkdtempSync(join(tmpdir(), "lfg-codex-user-"));
  try {
    const path = join(dir, "rollout.jsonl");
    writeFileSync(path, records.join("\n") + "\n");
    await run(path);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

describe("Codex user response items (lfg-37d7c4)", () => {
  test("incremental normalization emits the user immediately before its reply", () => {
    const state = createCodexNormalizationState();
    const messages = lines.flatMap(line => normalizeLineMessages(line, state));
    expect(messages.map(m => m.text)).toEqual(expected);
    expect(messages.map(m => m.role)).toEqual(["user", "assistant", "user", "assistant"]);
    expect(messages[0]?.ts).toBe(1788690003000);
  });

  test("full, bounded, and paginated readers preserve the same order and identities", async () => {
    await fixture(async path => {
      const full = await recentMessages(path, 0, { maxBytes: null });
      expect(full.map(m => m.text)).toEqual(expected);
      expect(await recentMessages(path, 0)).toEqual(full);
      const last = await messagePage(path, { limit: 2 });
      expect(last.nextBefore).not.toBeNull();
      const first = await messagePage(path, { limit: 2, before: last.nextBefore });
      expect([...first.messages, ...last.messages]).toEqual(full);
      expect(lines.flatMap(line => normalizeLineMessages(line))).toEqual(full);
    });
  });

  for (const idleConfirmed of [false, true]) {
    test(`accepted follow-up becomes delivered without resend (idle=${idleConfirmed})`, async () => {
      await fixture(async path => {
        const messages = await recentMessages(path, 40);
        const queued: QueuedMsg = { id: "q", clientId: "c", text: followup, status: "queued",
          attempts: 1, createdAt: 1788690004000, updatedAt: 1788690004000 };
        const result = reconcileQueuedCore([queued], messages.filter(m => m.role === "user").map(m => m.text),
          { idleConfirmed, now: 1788690060000 });
        expect(result).toEqual({ changed: true, kick: false });
        expect(queued.status).toBe("delivered");
        expect(queued.redeliveries).toBeUndefined();
      });
    });
  }

  test("all user-history readers recognize modern prompts", async () => {
    await fixture(async path => {
      expect(await recentUserTurns(path)).toEqual([prompt, followup]);
      expect((await allUserTurns(path)).turns).toEqual([prompt, followup]);
      expect(await lastUserPromptText(path)).toBe(followup);
    });
  });

  test("older response-item/event pairs still emit one legacy user message", () => {
    const response = row({ type: "message", role: "user", content: [{ type: "input_text", text: prompt }],
      internal_chat_message_metadata_passthrough: { turn_id: "old-turn" } }, 1);
    const event = row({ type: "user_message", message: prompt }, 2, "event_msg");
    const state = createCodexNormalizationState();
    expect([response, event].flatMap(line => normalizeLineMessages(line, state)))
      .toEqual(normalizeLineMessages(event));
  });

  test("repeated real prompts stay distinct", () => {
    const state = createCodexNormalizationState();
    const messages = [user(followup, 1), assistant("Answer", 2), user(followup, 3)]
      .flatMap(line => normalizeLineMessages(line, state));
    expect(messages.map(m => m.text)).toEqual([followup, "Answer", followup]);
    expect(messages[0]?.id).not.toBe(messages[2]?.id);
  });

  test("only explicitly marked user text is exposed from mixed content", () => {
    const mixed = row({ type: "message", role: "user", content: [
      { type: "input_text", text: "Injected context" }, { type: "input_text", text: "User: Real prompt" },
    ], internal_chat_message_metadata_passthrough: {
      content_item_kinds: ["agents_md.instructions", "user.text"],
    } }, 1);
    expect(normalizeLineMessages(mixed).map(m => m.text)).toEqual(["Real prompt"]);
    expect(normalizeLineMessages(user("Injected plugin", 1, ["plugins.recommendations"]))).toEqual([]);
    expect(normalizeLineMessages(user("Unknown", 1, []))).toEqual([]);
  });
});
