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

const timestamp = "2026-09-15T00:00:00.000Z";
const confirmation = "Set model to `Opus 5.5` and saved as your default for new sessions";
const modelCommand =
  "<command-name>/model</command-name>\n" +
  "            <command-message>model</command-message>\n" +
  "            <command-args>opus</command-args>";

function responseUser(text: string): string {
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

function eventUser(text: string): string {
  return JSON.stringify({
    timestamp,
    type: "event_msg",
    payload: { type: "user_message", message: text },
  });
}

function claudeUser(text: string, uuid = "claude-user-row"): string {
  return JSON.stringify({
    timestamp,
    uuid,
    type: "user",
    message: { role: "user", content: text },
  });
}

const dir = mkdtempSync(join(tmpdir(), "lfg-local-command-output-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe("Codex local command output transcript rows", () => {
  test("splits an embedded model confirmation into a system notice", () => {
    const messages = normalizeLineMessages(
      responseUser(
        `When I switch model, this message shows\n\n` +
          `<local-command-stdout>${confirmation}</local-command-stdout>\n\n` +
          `Can this message render like transcript errors?`,
      ),
    );

    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "user", kind: "text", text: "When I switch model, this message shows" },
      { role: "system", kind: "system_notice", text: confirmation },
      { role: "user", kind: "text", text: "Can this message render like transcript errors?" },
    ]);
    expect(new Set(messages.map((message) => message.id)).size).toBe(3);
  });

  test("renders a standalone confirmation as a system notice without wrapper tags", () => {
    expect(
      normalizeLineMessages(
        responseUser(`<local-command-stdout>${confirmation}</local-command-stdout>`),
      ).map(({ role, kind, text }) => ({ role, kind, text })),
    ).toEqual([{ role: "system", kind: "system_notice", text: confirmation }]);
  });

  test("applies the same split to legacy user-message events", () => {
    const messages = normalizeLineMessages(
      eventUser(
        `<local-command-stdout>${confirmation}</local-command-stdout>\n\nContinue with the task.`,
      ),
    );
    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "system", kind: "system_notice", text: confirmation },
      { role: "user", kind: "text", text: "Continue with the task." },
    ]);
  });

  test("renders a local command and output as ordered system notices", () => {
    const messages = normalizeLineMessages(
      responseUser(`${modelCommand}\n\n<local-command-stdout>${confirmation}</local-command-stdout>`),
    );

    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "system", kind: "system_notice", text: "/model opus" },
      { role: "system", kind: "system_notice", text: confirmation },
    ]);
    expect(new Set(messages.map((message) => message.id)).size).toBe(2);
  });

  test("leaves ordinary and malformed wrapper-like user text unchanged", () => {
    const ordinary = "Explain local command output without changing this message.";
    const malformed = `<local-command-stdout>${confirmation}`;
    const malformedCommand = "<command-name>/model";
    expect(normalizeLineMessages(responseUser(ordinary))[0]).toMatchObject({
      role: "user",
      kind: "text",
      text: ordinary,
    });
    expect(normalizeLineMessages(responseUser(malformed))[0]).toMatchObject({
      role: "user",
      kind: "text",
      text: malformed,
    });
    expect(normalizeLineMessages(responseUser(malformedCommand))[0]).toMatchObject({
      role: "user",
      kind: "text",
      text: malformedCommand,
    });
  });

  test("human-turn readers ignore the command output but retain following prose", async () => {
    const path = join(dir, "rollout.jsonl");
    const human = "Continue with the task.";
    writeFileSync(
      path,
      responseUser(
        `${modelCommand}\n\n` +
          `<local-command-stdout>${confirmation}</local-command-stdout>\n\n${human}`,
      ) + "\n",
    );

    expect((await recentMessages(path, 0, { maxBytes: null })).map((message) => message.text))
      .toEqual(["/model opus", confirmation, human]);
    expect((await allUserTurns(path)).turns).toEqual([human]);
    expect(await firstUserTextFromTop(path)).toBe(human);
    expect(await lastUserPromptText(path)).toBe(human);
  });
});

describe("Claude local command transcript rows", () => {
  test("normalizes the observed model switch command and stdout as system notices", () => {
    const command = normalizeLineMessages(claudeUser(modelCommand, "command-row"));
    const output = normalizeLineMessages(
      claudeUser(`<local-command-stdout>${confirmation}</local-command-stdout>`, "output-row"),
    );

    expect([...command, ...output].map(({ role, kind, text }) => ({ role, kind, text })))
      .toEqual([
        { role: "system", kind: "system_notice", text: "/model opus" },
        { role: "system", kind: "system_notice", text: confirmation },
      ]);
  });

  test("keeps genuine prose around a reserved wrapper in source order", () => {
    const messages = normalizeLineMessages(
      claudeUser(`Before\n\n${modelCommand}\n\nAfter`),
    );

    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "user", kind: "text", text: "Before" },
      { role: "system", kind: "system_notice", text: "/model opus" },
      { role: "user", kind: "text", text: "After" },
    ]);
    expect(new Set(messages.map((message) => message.id)).size).toBe(3);
  });
});
