import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { claudePaneNotice, observeClaudePaneNotice, mergeClaudeNotices } from "./claude-system-notices.ts";
import { messagePage, recentMessages, statusForTest } from "./sessions.ts";
import { publishClaudeSystemNotice } from "./journal-pump.ts";
import { resolveSessionPrompt } from "./commands/serve.ts";
import { resolveBusy, sessionTurnState } from "./session-state.ts";

const root = mkdtempSync(join(tmpdir(), "lfg-claude-notices-"));
afterAll(() => rmSync(root, { recursive: true, force: true }));
const notice = "Weekly limit reached · Retrying in 5h (Oct 24 at 2am) · attempt 1/300";
const pane = (meter: string, prose = "") => `${prose}\n${meter}\nUpdate available!\n${"─".repeat(65)}\n❯ \n${"─".repeat(65)}\n  ⏵⏵ bypass permissions on · esc to interrupt\n`;
const row = (id: string, role: string, text: string, ts: number) => JSON.stringify({
  type: role, uuid: id, timestamp: new Date(ts).toISOString(), message: { role, content: text },
}) + "\n";

describe("Claude pane-only system notices", () => {
  test("recognizes the real retry meter and preserves reset details", () => {
    expect(claudePaneNotice(pane(`✻ ${notice}`))).toEqual({ text: notice, errorCode: "rate_limit" });
    expect(claudePaneNotice(pane(`✽ ${notice.replace("Weekly", "Session")}`))?.errorCode).toBe("rate_limit");
    expect(claudePaneNotice(pane(`✻ Weekly limit reached · Retrying in 5h\n  (Oct 24 at 2am) · attempt 1/300`))?.text).toBe(notice);
  });

  test("does not promote quoted prose, old scrollback or composer input to errors", () => {
    expect(claudePaneNotice(pane("", `⏺ ${notice}`))).toBeNull();
    expect(claudePaneNotice(pane("", `✻ ${notice}\n${"ordinary prose\n".repeat(10)}`))).toBeNull();
    expect(claudePaneNotice(pane("").replace("❯ ", `❯ ✻ ${notice}`))).toBeNull();
    expect(claudePaneNotice(`✻ ${notice}`)).toBeNull(); // incomplete capture: no composer
    expect(claudePaneNotice(pane("", `⏺ Here is the exact status message:\n\n\x60\x60\x60text\n✻ ${notice}\n\x60\x60\x60`))).toBeNull();
  });

  test("persists once per incident, survives rereads, and clears live health", () => {
    const path = join(root, "persist.jsonl");
    const original = row("u1", "user", "Continue", 1000);
    writeFileSync(path, original);
    const first = observeClaudePaneNotice(path, pane(`✻ ${notice}`), 2000);
    expect(first.added).toMatchObject({ role: "assistant", kind: "text", apiError: true, errorCode: "rate_limit", text: notice, ts: 2000 });
    expect(observeClaudePaneNotice(path, pane(`✻ ${notice.replace("5h", "4h").replace("1/300", "2/300")}`), 3000).added).toBeNull();
    expect(mergeClaudeNotices(path, [])).toEqual([first.added!]);
    expect(statusForTest(first.active, null)).toMatchObject({ status: "blocked", statusReason: "usage_limit", statusDetail: notice });
    expect(observeClaudePaneNotice(path, pane(""), 4000).active).toBeNull();
    expect(statusForTest(null, null).status).toBe("ok");
    expect(readFileSync(path, "utf8")).toBe(original);
    const next = observeClaudePaneNotice(path, pane(`✻ ${notice}`), 5000);
    expect(next.added?.id).not.toBe(first.added?.id);
  });

  test("recent, full, and backward history include the same stable notice", async () => {
    const path = join(root, "history.jsonl");
    writeFileSync(path, row("u1", "user", "Continue", 1000));
    const { added } = observeClaudePaneNotice(path, pane(`✻ ${notice}`), 2000);
    writeFileSync(path, row("u1", "user", "Continue", 1000) + row("a1", "assistant", "Recovered", 3000));
    expect((await recentMessages(path, 1))[0]?.text).toBe("Recovered");
    expect((await recentMessages(path, 0, { maxBytes: null })).map(m => m.text)).toEqual(["Continue", notice, "Recovered"]);
    const newest = await messagePage(path, { limit: 2 });
    expect(newest.messages.map(m => m.id)).toEqual([added!.id, "a1"]);
    expect(newest.total).toBe(3);
    expect((await messagePage(path, { before: newest.nextBefore, limit: 2 })).messages.map(m => m.text)).toEqual(["Continue"]);
    expect((await recentMessages(path, 20)).find(m => m.id === added!.id)).toEqual(added!);
  });

  test("a native API error for the same incident takes precedence", () => {
    const path = join(root, "native.jsonl");
    writeFileSync(path, row("u1", "user", "Continue", 1000));
    observeClaudePaneNotice(path, pane(`✻ ${notice}`), 2000);
    const native = { id: "native", role: "assistant", kind: "text" as const, text: notice, ts: 2001, apiError: true, errorCode: "rate_limit" };
    expect(mergeClaudeNotices(path, [native])).toEqual([native]);
  });

  test("publishes discovered notices once to the journal, including after pump restart", () => {
    const path = join(root, "journal.jsonl");
    writeFileSync(path, row("u1", "user", "Continue", 1000));
    const discovered = observeClaudePaneNotice(path, pane(`✻ ${notice}`), 2000).active!;
    const events: unknown[] = [];
    const journal = { append: (_sid: string, _type: unknown, payload: unknown) => { events.push(payload); return events.length; } };
    expect(publishClaudeSystemNotice(journal, "sid", path, pane(`✻ ${notice}`), null, false)).toBeNull();
    expect(events).toHaveLength(0); // provider tail must catch up first
    const id = publishClaudeSystemNotice(journal, "sid", path, pane(`✻ ${notice}`), null);
    expect(events).toEqual([{ sid: "sid", m: discovered }]);
    expect(publishClaudeSystemNotice(journal, "sid", path, pane(`✻ ${notice}`), id)).toBe(id);
    expect(events).toHaveLength(1);
    expect(publishClaudeSystemNotice(journal, "sid", path, null, id)).toBe(id);
    expect(publishClaudeSystemNotice(journal, "sid", path, pane(`✻ ${notice}`), null)).toBe(id);
    expect(events).toHaveLength(2); // same stable ID across replay, clients deduplicate
    expect(publishClaudeSystemNotice(journal, "sid", path, pane(""), id)).toBeNull();
  });

  test("native retry mode suppresses a stale pending question", async () => {
    const path = join(root, "question.jsonl");
    writeFileSync(path, JSON.stringify({ type: "assistant", uuid: "question", timestamp: new Date().toISOString(),
      message: { role: "assistant", content: [{ type: "tool_use", id: "ask", name: "AskUserQuestion", input: {
        questions: [{ question: "Continue?", options: [{ label: "Yes" }, { label: "No" }] }],
      } }] } }) + "\n");
    expect(await resolveSessionPrompt(path, pane(""))).not.toBeNull();
    expect(await resolveSessionPrompt(path, pane(`✻ ${notice}`))).toBeNull();
  });

  test("partial renders and failed captures do not start a second incident", () => {
    const path = join(root, "partial.jsonl");
    writeFileSync(path, row("u1", "user", "Continue", 1000));
    const first = observeClaudePaneNotice(path, pane(`✻ ${notice}`), 2000).active!;
    expect(observeClaudePaneNotice(path, null, 3000).active).toEqual(first);
    observeClaudePaneNotice(path, `✻ ${notice}`, 4000);
    expect(observeClaudePaneNotice(path, `${"─".repeat(65)}\n${"─".repeat(65)}`, 4500).active).toEqual(first);
    expect(observeClaudePaneNotice(path, pane(`✻ ${notice}`), 5000)).toEqual({ active: first, added: null });
    expect(mergeClaudeNotices(path, [])).toHaveLength(1);
  });

  test("a long native retry remains in flight after the transcript stall timeout", async () => {
    const path = join(root, "stalled.jsonl");
    writeFileSync(path, row("u1", "user", "Continue", 1000));
    const verdict = await sessionTurnState({ transcriptPath: path, now: 3600000 });
    expect(verdict).toMatchObject({ state: "idle", stalled: true });
    expect(resolveBusy({ verdict, paneBusy: true, nativeRetry: claudePaneNotice(pane(`✻ ${notice}`)) != null })).toBe(true);
    expect(resolveBusy({ verdict, paneBusy: false, nativeRetry: false })).toBe(false);
  });
});
