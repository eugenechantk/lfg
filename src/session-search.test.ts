import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = join(tmpdir(), `lfg-search-${Date.now()}-${Math.random().toString(16).slice(2)}`);
const projects = join(home, ".claude", "projects");
const codexSessions = join(home, ".codex", "sessions");
const data = join(home, "data");
const prevHome = process.env.HOME;
process.env.HOME = home;
process.env.LFG_CLAUDE_PROJECTS_DIR = projects;
process.env.LFG_DATA = data;
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "host-a\n");

const {
  searchResumable,
  listResumable,
  resetSearchIndexCacheForTests,
  setSearchIndexTtlForTests,
  setSessionTitle,
  mayRefreshLiveLease,
  SEARCH_INDEX_PATH: indexPath,
} = await import("./sessions.ts");
// Both paths come from the modules under test, not recomputed from `data`:
// `PATHS` is resolved when `config.ts` is FIRST imported, so under the full
// suite another test file's `LFG_DATA` may already have won. Reading the live
// value keeps this file correct regardless of load order.
const { PATHS } = await import("./config.ts");
const { SEARCH_INDEX_VERSION } = await import("./session-index.ts");
const sessionTitlesPath = PATHS.sessionTitles;

describe("closed-session lease refresh guard", () => {
  test("a cached live row cannot recreate a lease after its pid is tombstoned", () => {
    expect(mayRefreshLiveLease("session-id", 42, (pid) => pid === 42)).toBe(false);
    expect(mayRefreshLiveLease("session-id", 42, () => false)).toBe(true);
    expect(mayRefreshLiveLease(null, 42, () => false)).toBe(false);
  });
});

beforeEach(() => {
  rmSync(projects, { recursive: true, force: true });
  mkdirSync(projects, { recursive: true });
  rmSync(codexSessions, { recursive: true, force: true });
  mkdirSync(codexSessions, { recursive: true });
  rmSync(indexPath, { force: true });
  rmSync(sessionTitlesPath, { force: true });
  setSearchIndexTtlForTests(0);
  resetSearchIndexCacheForTests();
});

afterAll(() => {
  if (prevHome === undefined) delete process.env.HOME;
  else process.env.HOME = prevHome;
  delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  delete process.env.LFG_DATA;
  rmSync(home, { recursive: true, force: true });
});

/** A transcript whose first user turn is `prompt` (which becomes its title). */
function writeTranscript(
  project: string,
  id: string,
  mtime: number,
  prompt: string,
  opts: { cwd?: string; lastUserText?: string } = {},
) {
  const cwd = opts.cwd ?? `/tmp/${project}`;
  const dir = join(projects, project);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  const lines = [
    JSON.stringify({ cwd, type: "user", message: { content: prompt } }),
    JSON.stringify({ cwd, type: "assistant", message: { content: "ok" } }),
  ];
  if (opts.lastUserText) {
    lines.push(JSON.stringify({ cwd, type: "user", message: { content: opts.lastUserText } }));
  }
  writeFileSync(path, `${lines.join("\n")}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
  return path;
}

/** A claude transcript from explicit JSONL rows, for shapes `writeTranscript` can't express. */
function writeRows(project: string, id: string, mtime: number, rows: unknown[]) {
  const dir = join(projects, project);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  writeFileSync(path, `${rows.map((r) => JSON.stringify(r)).join("\n")}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
  return path;
}

const user = (text: string) => ({ cwd: "/tmp/p", type: "user", message: { content: text } });
const assistant = (text: string) => ({ cwd: "/tmp/p", type: "assistant", message: { content: text } });

/** A codex rollout whose user turns are `messages`, in order. */
function writeCodexRollout(id: string, mtime: number, messages: string[]) {
  const dir = join(codexSessions, "2026", "09", "20");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `rollout-2026-09-20T00-00-00-${id}.jsonl`);
  const rows: unknown[] = [
    { type: "session_meta", payload: { id, cwd: "/tmp/codex", timestamp: "2026-09-20T00:00:00Z" } },
  ];
  for (const m of messages) {
    rows.push({ type: "event_msg", payload: { type: "user_message", message: m } });
    rows.push({ type: "event_msg", payload: { type: "agent_message", message: "ok" } });
  }
  writeFileSync(path, `${rows.map((r) => JSON.stringify(r)).join("\n")}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
  return path;
}

function id(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

describe("searchResumable", () => {
  test("finds a match far outside the newest page — the whole point of the feature", async () => {
    // 11 recent sessions that do not match, and the ONE that does is the oldest
    // conversation in the corpus. A client paging 3 at a time would never see it.
    for (let i = 0; i < 11; i++) {
      writeTranscript("noise", id(100 + i), 10_000 + i * 1_000, `unrelated work ${i}`);
    }
    writeTranscript("old", id(1), 1_000, "investigate the question preamble");

    const unsearched = await listResumable({ limit: 3 });
    expect(unsearched.sessions.map((s) => s.sessionId)).not.toContain(id(1));

    const hits = await searchResumable({ q: "preamble", limit: 3 });
    expect(hits.sessions.map((s) => s.sessionId)).toEqual([id(1)]);
    expect(hits.nextBefore).toBeNull();
  });

  test("pages its own results with the before cursor, no overlap and no gaps", async () => {
    const ids = [id(11), id(12), id(13), id(14), id(15)];
    ids.forEach((sid, i) => writeTranscript("p", sid, 5_000 - i * 1_000, `preamble item ${i}`));
    writeTranscript("p", id(19), 9_000, "something else entirely");

    const page1 = await searchResumable({ q: "preamble", limit: 2 });
    expect(page1.sessions.map((s) => s.sessionId)).toEqual([ids[0], ids[1]]);
    expect(page1.nextBefore).toBe(page1.sessions[1].lastActivityAt);

    const page2 = await searchResumable({ q: "preamble", limit: 2, before: page1.nextBefore });
    expect(page2.sessions.map((s) => s.sessionId)).toEqual([ids[2], ids[3]]);

    const page3 = await searchResumable({ q: "preamble", limit: 2, before: page2.nextBefore });
    expect(page3.sessions.map((s) => s.sessionId)).toEqual([ids[4]]);
    expect(page3.nextBefore).toBeNull();

    const walked = [...page1.sessions, ...page2.sessions, ...page3.sessions].map((s) => s.sessionId);
    expect(walked).toEqual(ids);
    expect(new Set(walked).size).toBe(ids.length);
  });

  test("matches on project, cwd and the last user turn, not just the title", async () => {
    writeTranscript("alpha", id(21), 3_000, "first prompt", {
      cwd: "/Users/eugene/dev/alpha",
      lastUserText: "please restart the pump",
    });
    writeTranscript("beta", id(22), 2_000, "unrelated", { cwd: "/Users/eugene/dev/beta" });

    expect((await searchResumable({ q: "alpha" })).sessions.map((s) => s.sessionId)).toEqual([id(21)]);
    expect((await searchResumable({ q: "pump" })).sessions.map((s) => s.sessionId)).toEqual([id(21)]);
    expect((await searchResumable({ q: "dev/beta" })).sessions.map((s) => s.sessionId)).toEqual([id(22)]);
  });

  test("multiple terms AND together", async () => {
    writeTranscript("lfg", id(31), 3_000, "fix the preamble");
    writeTranscript("other", id(32), 2_000, "fix the pane");

    expect((await searchResumable({ q: "fix preamble" })).sessions.map((s) => s.sessionId)).toEqual([
      id(31),
    ]);
    expect((await searchResumable({ q: "preamble pane" })).sessions).toEqual([]);
  });

  test("an empty query falls back to the plain resumable page", async () => {
    writeTranscript("p", id(41), 2_000, "one");
    writeTranscript("p", id(42), 1_000, "two");

    const page = await searchResumable({ q: "   ", limit: 10 });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(41), id(42)]);
  });

  test("excludes a session holding a fresh lease, exactly like the unsearched list", async () => {
    writeTranscript("p", id(51), 3_000, "preamble live");
    writeTranscript("p", id(52), 2_000, "preamble closed");
    writeFileSync(
      join(projects, "p", `${id(51)}.lease.json`),
      JSON.stringify({
        hostId: "host-b",
        pid: 4242,
        acquiredAt: Date.now(),
        heartbeatAt: Date.now(),
      }),
    );

    const page = await searchResumable({ q: "preamble", limit: 10 });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(52)]);
  });

  test("finds a session by a title the user set, not only its first prompt", async () => {
    writeTranscript("p", id(61), 2_000, "some forgettable opening line");
    await setSessionTitle(id(61), "Preamble investigation");

    const page = await searchResumable({ q: "preamble", limit: 10 });
    expect(page.sessions.map((s) => s.title)).toEqual(["Preamble investigation"]);
  });

  test("picks up a transcript created after the index was first built", async () => {
    writeTranscript("p", id(71), 2_000, "preamble first");
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(1);

    writeTranscript("p", id(72), 3_000, "preamble second");
    const page = await searchResumable({ q: "preamble" });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(72), id(71)]);
  });

  test("re-reads a transcript whose content changed under the same id", async () => {
    writeTranscript("p", id(81), 2_000, "before the rename");
    expect((await searchResumable({ q: "rename" })).sessions).toHaveLength(1);

    writeTranscript("p", id(81), 4_000, "after the edit mentions marmalade");
    expect((await searchResumable({ q: "marmalade" })).sessions.map((s) => s.sessionId)).toEqual([
      id(81),
    ]);
    expect((await searchResumable({ q: "rename" })).sessions).toHaveLength(0);
  });

  test("forgets a transcript that was deleted from disk", async () => {
    const path = writeTranscript("p", id(91), 2_000, "preamble doomed");
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(1);

    rmSync(path);
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(0);
  });

  test("persists the index so a fresh process does not rebuild from scratch", async () => {
    writeTranscript("p", id(95), 2_000, "preamble persisted");
    await searchResumable({ q: "preamble" });

    const raw = (await Bun.file(indexPath).json()) as { version: number; entries: unknown[] };
    expect(raw.version).toBe(SEARCH_INDEX_VERSION);
    expect(raw.entries).toHaveLength(1);

    // Simulate a restart: in-process cache gone, index file still on disk.
    resetSearchIndexCacheForTests();
    const page = await searchResumable({ q: "preamble" });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(95)]);
  });

  test("within the coalescing window, a burst of searches does not re-walk the corpus", async () => {
    // Search is typed, so one query is several requests. The window is what
    // keeps that from costing an enumeration per keystroke.
    writeTranscript("p", id(210), 5_000, "preamble first");
    setSearchIndexTtlForTests(60_000);
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(1);

    // A transcript written inside the window is deliberately not picked up yet.
    writeTranscript("p", id(211), 6_000, "preamble second");
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(1);

    // Once the window lapses, the very next search sees it.
    setSearchIndexTtlForTests(0);
    expect((await searchResumable({ q: "preamble" })).sessions).toHaveLength(2);
  });

  test("a repeat search does not re-read a transcript whose mtime is unchanged", async () => {
    const path = writeTranscript("p", id(200), 5_000, "preamble original");
    expect((await searchResumable({ q: "original" })).sessions).toHaveLength(1);

    // Rewrite the content but restore the mtime — what an incremental index is
    // allowed to miss, and the only observable difference between "reused the
    // cached entry" and "read the file again".
    writeFileSync(path, `${JSON.stringify({ cwd: "/tmp/p", type: "user", message: { content: "preamble rewritten" } })}\n`);
    const when = new Date(5_000);
    utimesSync(path, when, when);

    expect((await searchResumable({ q: "rewritten" })).sessions).toHaveLength(0);
    expect((await searchResumable({ q: "original" })).sessions).toHaveLength(1);
  });

  // ---- user-turn matching (2026-09-20: "I can't search for my dictate keyboard session") ----

  test("matches a term that appears only in a middle user turn", async () => {
    // The real shape of the miss: the title is the first prompt, the preview
    // is the last prompt, and the word the user remembers is in neither.
    writeRows("inbox", id(300), 3_000, [
      user("Is there a way to use the action button on iPhone 17 pro to transcribe what I said"),
      assistant("yes"),
      user("I want to use the action button to kickstart the dictation, without me switch keyboards"),
      assistant("sure"),
      user("And let's use openrouter's models to test it"),
    ]);
    writeTranscript("noise", id(301), 4_000, "unrelated newer work");

    const page = await searchResumable({ q: "dictation" });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(300)]);
    expect(page.sessions[0].title).toContain("action button");
    // Terms are substrings, so the stem finds it too.
    expect((await searchResumable({ q: "dictat keyboard" })).sessions.map((s) => s.sessionId)).toEqual([
      id(300),
    ]);
  });

  test("a user-turn match is previewed by the turn that matched, so shipped clients keep the row", async () => {
    // iOS and desktop re-filter every server row on title/project/cwd/
    // lastUserText/sessionId. A row matched only through its turns must carry
    // the hit in one of those fields or those builds drop it as noise.
    writeRows("inbox", id(310), 3_000, [
      user("first prompt about the keyboard"),
      user("I want to kickstart the dictation without switching keyboards"),
      user("final message about openrouter"),
    ]);

    const [row] = (await searchResumable({ q: "dictation" })).sessions;
    expect(row.lastUserText).toContain("kickstart the dictation");
    expect(row.lastUserText).not.toContain("openrouter");
  });

  test("a title or last-message match keeps the real last user text", async () => {
    writeRows("inbox", id(320), 3_000, [
      user("first prompt about the keyboard"),
      user("middle turn mentioning dictation"),
      user("final message about openrouter"),
    ]);

    expect((await searchResumable({ q: "keyboard" })).sessions[0].lastUserText).toBe(
      "final message about openrouter",
    );
    expect((await searchResumable({ q: "openrouter" })).sessions[0].lastUserText).toBe(
      "final message about openrouter",
    );
  });

  test("matches a middle user turn of a codex rollout", async () => {
    writeCodexRollout(id(330), 3_000, [
      "start the web app",
      "now add the marmalade importer",
      "ship it",
    ]);

    const page = await searchResumable({ q: "marmalade" });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(330)]);
    expect(page.sessions[0].agent).toBe("codex");
    expect(page.sessions[0].lastUserText).toContain("marmalade importer");
  });

  test("matches a message that was absorbed mid-turn (queue-operation), which exists nowhere else", async () => {
    writeRows("lfg", id(340), 3_000, [
      user("start the refactor"),
      {
        type: "queue-operation",
        operation: "enqueue",
        content: "also rename the marmalade module",
        timestamp: "2026-09-20T00:00:01Z",
      },
      {
        type: "queue-operation",
        operation: "remove",
        reason: "absorbed_mid_turn",
        content: "also rename the marmalade module",
        timestamp: "2026-09-20T00:00:02Z",
      },
      assistant("done"),
    ]);

    const page = await searchResumable({ q: "marmalade" });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([id(340)]);
    expect(page.sessions[0].lastUserText).toContain("marmalade module");
  });

  test("does not index meta, wrapper or tool-result user lines", async () => {
    // Genuine prompts bracket the noise so the title (first prompt) and the
    // preview (last prompt) — read by the existing head/tail scanners, not
    // under test here — are both genuine, and "marmalade" can only come from
    // the index.
    writeRows("lfg", id(350), 3_000, [
      user("a genuine opening prompt"),
      { ...user("the whole SKILL.md body mentions marmalade"), isMeta: true },
      user("<command-name>/marmalade</command-name>"),
      user("<local-command-stdout>marmalade</local-command-stdout>"),
      {
        cwd: "/tmp/p",
        type: "user",
        toolUseResult: { stdout: "marmalade" },
        message: { content: [{ type: "tool_result", content: "marmalade" }, { type: "text", text: "marmalade" }] },
      },
      user("a genuine closing prompt"),
    ]);

    expect((await searchResumable({ q: "marmalade" })).sessions).toEqual([]);
    expect((await searchResumable({ q: "genuine" })).sessions.map((s) => s.sessionId)).toEqual([id(350)]);
  });

  test("an interrupt marker is not a user turn and does not match", async () => {
    writeRows("lfg", id(355), 3_000, [
      user("start the refactor"),
      user("[Request interrupted by user]"),
      user("carry on"),
    ]);
    expect((await searchResumable({ q: "interrupted" })).sessions).toEqual([]);
  });

  test("indexed user text is capped, so a very long conversation is bounded", async () => {
    // 60 turns of 200 chars is 12 KB of user text; the cap keeps the head.
    const filler = Array.from({ length: 60 }, (_, i) => user(`turn ${i} ${"lorem ipsum ".repeat(16)}`));
    writeRows("lfg", id(360), 3_000, [user("opening marmalade request"), ...filler, user("closing quince remark")]);

    expect((await searchResumable({ q: "marmalade" })).sessions.map((s) => s.sessionId)).toEqual([id(360)]);
    // The last turn is the preview (classic field), so it still matches by that route…
    expect((await searchResumable({ q: "quince" })).sessions).toHaveLength(1);
    // …but a term buried past the cap in the middle does not.
    expect((await searchResumable({ q: "turn 59" })).sessions).toEqual([]);
  });
});
