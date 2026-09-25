import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  allUserTurns,
  firstUserTextFromTop,
  lastUserPromptText,
  normalizeLineMessages,
  recentMessages,
} from "./sessions.ts";

const timestamp = "2026-09-24T00:00:00.000Z";
const notification = [
  "<task-notification>",
  "<task-id>agent-audit</task-id>",
  "<status>completed</status>",
  '<summary>Agent "Audit transcript rendering" finished</summary>',
  "<result>PASS: task notification rows use thinking presentation.</result>",
  "</task-notification>",
].join("\n");

function claudeUser(text: string, uuid = "claude-task-notification"): string {
  return JSON.stringify({
    timestamp,
    uuid,
    type: "user",
    message: { role: "user", content: text },
  });
}

function codexUser(text: string): string {
  return JSON.stringify({
    timestamp,
    type: "response_item",
    payload: {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text }],
      internal_chat_message_metadata_passthrough: {
        content_item_kinds: ["user.text"],
      },
    },
  });
}

const dir = mkdtempSync(join(tmpdir(), "lfg-task-notification-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe("task notification transcript rows", () => {
  test("normalizes the observed Claude envelope as thinking activity", () => {
    expect(
      normalizeLineMessages(claudeUser(notification)).map(({ role, kind, text }) => ({
        role,
        kind,
        text,
      })),
    ).toEqual([{ role: "system", kind: "thinking", text: notification }]);
  });

  test("applies the same classification to Codex user message rows", () => {
    expect(
      normalizeLineMessages(codexUser(notification)).map(({ role, kind, text }) => ({
        role,
        kind,
        text,
      })),
    ).toEqual([{ role: "system", kind: "thinking", text: notification }]);
  });

  test("preserves human prose around the notification in source order", () => {
    const messages = normalizeLineMessages(
      codexUser(`Before the task finished.\n\n${notification}\n\nContinue with the result.`),
    );

    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "user", kind: "text", text: "Before the task finished." },
      { role: "system", kind: "thinking", text: notification },
      { role: "user", kind: "text", text: "Continue with the result." },
    ]);
    expect(new Set(messages.map((message) => message.id)).size).toBe(3);
  });

  test("leaves an incomplete wrapper as genuine user text", () => {
    const malformed = "<task-notification>Explain this incomplete example.";
    expect(normalizeLineMessages(claudeUser(malformed))[0]).toMatchObject({
      role: "user",
      kind: "text",
      text: malformed,
    });
  });

  test("human-turn readers ignore task activity and retain surrounding prose", async () => {
    const path = join(dir, "rollout.jsonl");
    const before = "Before the task finished.";
    const after = "Continue with the result.";
    writeFileSync(
      path,
      [codexUser(before), codexUser(notification), codexUser(after)].join("\n") + "\n",
    );

    expect((await recentMessages(path, 0, { maxBytes: null })).map(({ role, kind }) => ({
      role,
      kind,
    }))).toEqual([
      { role: "user", kind: "text" },
      { role: "system", kind: "thinking" },
      { role: "user", kind: "text" },
    ]);
    expect((await allUserTurns(path)).turns).toEqual([before, after]);
    expect(await firstUserTextFromTop(path)).toBe(before);
    expect(await lastUserPromptText(path)).toBe(after);
  });
});
