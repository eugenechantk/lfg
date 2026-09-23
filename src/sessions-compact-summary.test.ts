import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  allUserTurns,
  lastUserPromptText,
  lastUserTextForTest,
  normalizeLineMessages,
  recentMessages,
  recentUserTurns,
} from "./sessions.ts";

const continuation =
  "This session is being continued from a previous conversation that ran out of context. " +
  "The summary below covers the earlier portion of the conversation.";
const summaryBody = `${continuation}\n\nSummary:\nprivate compacted context`;

function user(text: string, fields: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    type: "user",
    message: { role: "user", content: text },
    uuid: "user-row",
    timestamp: "2026-09-23T02:24:01.108Z",
    ...fields,
  };
}

const compactSummary = user(summaryBody, {
  isVisibleInTranscriptOnly: true,
  isCompactSummary: true,
  uuid: "compact-row",
});

const dir = mkdtempSync(join(tmpdir(), "lfg-compact-summary-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

function transcript(lines: Record<string, unknown>[]): string {
  const path = join(dir, `${crypto.randomUUID()}.jsonl`);
  writeFileSync(path, lines.map((line) => JSON.stringify(line)).join("\n") + "\n");
  return path;
}

describe("Claude compact-summary transcript rows", () => {
  test("renders the flagged summary as one concise thinking item", () => {
    expect(normalizeLineMessages(JSON.stringify(compactSummary))).toEqual([
      {
        id: "compact-row",
        role: "user",
        kind: "thinking",
        text: "Compacting conversation",
        ts: Date.parse("2026-09-23T02:24:01.108Z"),
      },
    ]);
  });

  test("does not infer compaction from user prose alone", () => {
    expect(normalizeLineMessages(JSON.stringify(user(summaryBody)))[0]).toMatchObject({
      role: "user",
      kind: "text",
      text: summaryBody,
    });
  });

  test("keeps the marker in the transcript but excludes it from every user-turn reader", async () => {
    const genuinePrompt = "Commit that fix and cut a new TestFlight build";
    const path = transcript([user(genuinePrompt, { uuid: "real-row" }), compactSummary]);

    expect((await recentMessages(path, 20, { maxBytes: null })).map(({ kind, text }) => ({ kind, text })))
      .toEqual([
        { kind: "text", text: genuinePrompt },
        { kind: "thinking", text: "Compacting conversation" },
      ]);
    expect(await recentUserTurns(path, 6)).toEqual([genuinePrompt]);
    expect((await allUserTurns(path)).turns).toEqual([genuinePrompt]);
    expect(await lastUserPromptText(path)).toBe(genuinePrompt);
    expect(await lastUserTextForTest(path)).toBe(genuinePrompt);
  });
});
