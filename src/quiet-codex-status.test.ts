import { afterEach, describe, expect, test } from "bun:test";
import { appendFileSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bareSessionBusy } from "./journal-pump.ts";
import { observeSession } from "./push/watcher.ts";

const roots: string[] = [];
const event = (type: string) => JSON.stringify({ type: "event_msg", payload: { type } }) + "\n";

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

function rollout(content = event("task_started")): string {
  const root = mkdtempSync(join(tmpdir(), "quiet-codex-"));
  roots.push(root);
  const path = join(root, "rollout.jsonl");
  writeFileSync(path, content);
  const old = new Date(Date.now() - 2 * 60 * 60_000);
  utimesSync(path, old, old);
  return path;
}

describe("Codex without a terminal pane", () => {
  test("fresh forks stay idle in journal and push observations until their first turn", async () => {
    const transcriptPath = rollout(JSON.stringify({
      type: "session_meta", payload: { id: "fork", forked_from_id: "source" },
    }) + "\n");
    appendFileSync(transcriptPath, event("thread_settings_applied"));
    const session = { agent: "codex", sessionId: "fresh-fork", transcriptPath, tmuxTarget: null };
    for (let read = 0; read < 3; read++) {
      expect(await bareSessionBusy(session)).toBe(false);
      expect((await observeSession(session)).busy).toBe(false);
    }
    appendFileSync(transcriptPath, event("task_started"));
    expect(await bareSessionBusy(session)).toBe(true);
    expect((await observeSession(session)).busy).toBe(true);
    appendFileSync(transcriptPath, event("task_complete"));
    expect(await bareSessionBusy(session)).toBe(false);
    expect((await observeSession(session)).busy).toBe(false);
  });

  test("the journal keeps an unchanged open turn running", async () => {
    const transcriptPath = rollout();
    for (let read = 0; read < 3; read++) {
      expect(await bareSessionBusy({ agent: "codex", sessionId: "bare-codex", transcriptPath })).toBe(true);
    }
  });

  for (const end of ["task_complete", "turn_aborted"]) {
    test(`journal observes ${end} promptly even when the file is fresh`, async () => {
      const transcriptPath = rollout();
      expect(await bareSessionBusy({ agent: "codex", transcriptPath })).toBe(true);
      appendFileSync(transcriptPath, event(end));
      expect(await bareSessionBusy({ agent: "codex", transcriptPath })).toBe(false);
    });
  }

  test("unrecognized transcripts retain the existing freshness fallback", async () => {
    const transcriptPath = rollout(JSON.stringify({ type: "session_meta" }) + "\n");
    expect(await bareSessionBusy({ agent: "codex", transcriptPath })).toBe(false);
    appendFileSync(transcriptPath, JSON.stringify({ type: "session_meta" }) + "\n");
    expect(await bareSessionBusy({ agent: "codex", transcriptPath })).toBe(true);
  });

  test("bare Claude keeps its existing freshness rule", async () => {
    const transcriptPath = rollout(JSON.stringify({ type: "assistant", message: { content: [] } }) + "\n");
    expect(await bareSessionBusy({ agent: "claude", transcriptPath })).toBe(false);
    appendFileSync(transcriptPath, JSON.stringify({ type: "assistant" }) + "\n");
    expect(await bareSessionBusy({ agent: "claude", transcriptPath })).toBe(true);
  });

  test("delegation keeps a bare session busy even when its own turn has ended", async () => {
    expect(await bareSessionBusy({ agent: "codex", transcriptPath: rollout(event("task_complete")), delegated: true })).toBe(true);
  });

  test("push observations keep a quiet external Codex turn running and detect its end", async () => {
    const transcriptPath = rollout();
    const session = { agent: "codex", sessionId: "external-codex", transcriptPath, tmuxTarget: null };
    expect(await observeSession(session)).toEqual({ busy: true, promptPresent: false, promptQuestion: null });
    appendFileSync(transcriptPath, event("task_complete"));
    expect(await observeSession(session)).toEqual({ busy: false, promptPresent: false, promptQuestion: null });
  });

  test("phone sign-in prompts remain visible during a quiet external turn", async () => {
    const session = { agent: "codex", sessionId: "external-sign-in", transcriptPath: rollout(), tmuxTarget: null };
    expect(await observeSession(session, () => ({ question: "Sign in" })))
      .toEqual({ busy: true, promptPresent: true, promptQuestion: "Sign in" });
  });
});
