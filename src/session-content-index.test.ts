import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync, appendFileSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionContentIndex, completeLines, watchTranscriptRoots } from "./session-content-index";
import { createCodexNormalizationState, searchProse } from "./sessions";

const root = mkdtempSync(join(tmpdir(), "lfg-prose-index-"));
afterAll(() => rmSync(root, { recursive: true, force: true }));

const normalize = searchProse;

function candidate(id: string, path: string, mtime = Date.now()) {
  return { sessionId: id, path, mtime };
}

describe("message FTS and filesystem sync", () => {
  test("indexes visible Claude and Codex prose; excludes tool and thinking rows", async () => {
    const dir = mkdtempSync(join(root, "roles-"));
    const claude = join(dir, "claude.jsonl");
    const codex = join(dir, "codex.jsonl");
    writeFileSync(claude, [
      { type: "user", message: { role: "user", content: "Find the amber notebook" } },
      { type: "assistant", message: { role: "assistant", content: [{ type: "thinking", thinking: "private orchid" }, { type: "text", text: "The silver notebook is here" }, { type: "tool_use", name: "Bash", input: { command: "echo copper" } }] } },
      { type: "user", toolUseResult: { stdout: "secret bronze" }, message: { role: "user", content: [{ type: "tool_result", content: "secret bronze" }] } },
      { type: "user", toolUseResult: { stdout: "secret bronze" }, message: { role: "user", content: [{ type: "text", text: "stray magenta output" }] } },
      { type: "user", message: { role: "user", content: "<local-command-stdout>secret ochre</local-command-stdout>" } },
    ].map((row) => JSON.stringify(row)).join("\n") + "\n");
    writeFileSync(codex, [
      { type: "session_meta", payload: { cwd: dir } },
      { type: "event_msg", payload: { type: "user_message", message: "Find the cobalt marker" } },
      { type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "I found the violet marker" }] } },
      { type: "response_item", payload: { type: "reasoning", summary: [{ text: "private crimson" }] } },
    ].map((row) => JSON.stringify(row)).join("\n") + "\n");
    const index = new SessionContentIndex(join(dir, "index.sqlite"));
    await index.reconcile([candidate("claude", claude), candidate("codex", codex)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["amber"]), (hit) => hit.sessionId)).toEqual(["claude"]);
    expect(Array.from(index.hits(["silver"]), (hit) => hit.role)).toEqual(["assistant"]);
    expect(Array.from(index.hits(["violet"]), (hit) => hit.sessionId)).toEqual(["codex"]);
    for (const hidden of ["orchid", "copper", "bronze", "crimson", "magenta", "ochre"])
      expect(Array.from(index.hits([hidden]))).toEqual([]);
    index.close();
    const reopened = new SessionContentIndex(join(dir, "index.sqlite"));
    expect(Array.from(reopened.hits(["violet"]), (hit) => hit.sessionId)).toEqual(["codex"]);
    reopened.close();
  });

  test("appends from the last complete byte, rebuilds rewrites, and removes deletes", async () => {
    const dir = mkdtempSync(join(root, "sync-"));
    const path = join(dir, "one.jsonl");
    const db = join(dir, "index.sqlite");
    const user = (text: string) => JSON.stringify({ type: "user", message: { role: "user", content: text } });
    writeFileSync(path, `${user("alpha opening")}\n${user("unfinished beta")}`.slice(0, -1));
    const index = new SessionContentIndex(db);
    await index.reconcile([candidate("one", path, 100)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["alpha"]))).toHaveLength(1);
    expect(Array.from(index.hits(["beta"]))).toHaveLength(0);
    appendFileSync(path, "}\n" + user("gamma ending") + "\n");
    await index.reconcile([candidate("one", path, 101)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["alpha"]))).toHaveLength(1);
    expect(Array.from(index.hits(["beta"]))).toHaveLength(1);
    expect(Array.from(index.hits(["gamma"]))).toHaveLength(1);
    writeFileSync(path, `${user("delta rewrite")}\n`);
    await index.reconcile([candidate("one", path, 102)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["alpha"]))).toHaveLength(0);
    expect(Array.from(index.hits(["delta"]))).toHaveLength(1);
    await index.reconcile([], normalize, createCodexNormalizationState);
    expect(index.stats()).toEqual({ files: 0, messages: 0 });
    index.close();
    const reopened = new SessionContentIndex(db);
    expect(reopened.stats()).toEqual({ files: 0, messages: 0 });
    reopened.close();
  });

  test("finds a late assistant response beyond the old 4096-character user cap", async () => {
    const dir = mkdtempSync(join(root, "late-"));
    const path = join(dir, "long.jsonl");
    const rows = Array.from({ length: 80 }, (_, i) => JSON.stringify({
      type: "assistant", message: { role: "assistant", content: `ordinary response ${i} ${"filler ".repeat(50)}` },
    }));
    rows.push(JSON.stringify({ type: "assistant", message: { role: "assistant", content: "The rare ultramarine answer" } }));
    writeFileSync(path, rows.join("\n") + "\n");
    const index = new SessionContentIndex(join(dir, "index.sqlite"));
    await index.reconcile([candidate("long", path)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["ultramarine"]), (hit) => hit.sessionId)).toEqual(["long"]);
    expect(index.stats().messages).toBe(81);
    index.close();
  });

  test("skips an oversized tool row and continues indexing later prose", async () => {
    const dir = mkdtempSync(join(root, "large-row-"));
    const path = join(dir, "large.jsonl");
    writeFileSync(path, `${JSON.stringify({ type: "user", toolUseResult: { stdout: "x".repeat(9 * 1024 * 1024) } })}\n` +
      `${JSON.stringify({ type: "assistant", message: { role: "assistant", content: "The aquamarine result" } })}\n`);
    const index = new SessionContentIndex(join(dir, "index.sqlite"));
    await index.reconcile([candidate("large", path)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["aquamarine"]))).toHaveLength(1);
    expect(index.stats().messages).toBe(1);
    index.close();
  });

  test("a watched same-size rewrite refreshes prose even when mtime is restored", async () => {
    const dir = mkdtempSync(join(root, "same-metadata-"));
    const path = join(dir, "one.jsonl");
    const row = (word: string) => JSON.stringify({ type: "assistant", message: { role: "assistant", content: word } }) + "\n";
    writeFileSync(path, row("amber"));
    const when = new Date(10_000);
    utimesSync(path, when, when);
    const index = new SessionContentIndex(join(dir, "index.sqlite"));
    await index.reconcile([candidate("one", path, 10_000)], normalize, createCodexNormalizationState);
    writeFileSync(path, row("cider"));
    utimesSync(path, when, when);
    await index.reconcile([candidate("one", path, 10_000)], normalize, createCodexNormalizationState);
    expect(Array.from(index.hits(["amber"]))).toHaveLength(1);
    await index.reconcile([candidate("one", path, 10_000)], normalize, createCodexNormalizationState,
                          new Set([path]));
    expect(Array.from(index.hits(["amber"]))).toHaveLength(0);
    expect(Array.from(index.hits(["cider"]))).toHaveLength(1);
    index.close();
  });

  test("watcher schedules updates and periodic reconcile repairs missed events", async () => {
    const dir = mkdtempSync(join(root, "watch-"));
    let runs = 0;
    const stop = watchTranscriptRoots([dir], async () => { runs++; }, 80);
    writeFileSync(join(dir, "new.jsonl"), "{}\n");
    await Bun.sleep(650);
    expect(runs).toBeGreaterThanOrEqual(2);
    stop();
  });

  test("a filesystem event schedules a reconcile before the periodic timer", async () => {
    const dir = mkdtempSync(join(root, "event-"));
    let runs = 0;
    const observed = new Set<string>();
    const stop = watchTranscriptRoots([dir], async (paths) => {
      runs++;
      for (const path of paths) observed.add(path);
    }, 10_000);
    await Bun.sleep(450);
    expect(runs).toBe(1);
    writeFileSync(join(dir, "arrived.jsonl"), "{}\n");
    await Bun.sleep(500);
    expect(runs).toBeGreaterThanOrEqual(2);
    expect(observed.has(join(dir, "arrived.jsonl"))).toBe(true);
    stop();
  });
});
