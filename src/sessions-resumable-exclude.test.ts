import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = join(tmpdir(), `lfg-exclude-${Date.now()}-${Math.random().toString(16).slice(2)}`);
const projects = join(home, ".claude", "projects");
const data = join(home, "data");
const prevHome = process.env.HOME;
process.env.HOME = home;
process.env.LFG_CLAUDE_PROJECTS_DIR = projects;
process.env.LFG_DATA = data;
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "host-a\n");

const { listResumable, searchResumable, resetSearchIndexCacheForTests } = await import(
  "./sessions.ts"
);

beforeEach(() => {
  rmSync(projects, { recursive: true, force: true });
  mkdirSync(projects, { recursive: true });
  resetSearchIndexCacheForTests();
});

afterAll(() => {
  if (prevHome === undefined) delete process.env.HOME;
  else process.env.HOME = prevHome;
  delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  delete process.env.LFG_DATA;
  rmSync(home, { recursive: true, force: true });
});

let seq = 0;
function uuid(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

function writeTranscript(id: string, mtime: number, cwd: string, text = "hello world") {
  const dir = join(projects, "p");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  writeFileSync(
    path,
    `${JSON.stringify({ cwd })}\n${JSON.stringify({
      type: "user",
      message: { role: "user", content: text },
      cwd,
    })}\n`,
  );
  const when = new Date(mtime);
  utimesSync(path, when, when);
}

// The starvation this exists to prevent: a churny population (gbrain autopilot
// temp cwds) owns the entire newest-mtime window, so filtering the page
// client-side leaves a near-empty list while thousands of real sessions sit
// behind the cursor. `exclude` filters BEFORE pagination, so a page of N is N
// visible rows.
describe("listResumable exclude", () => {
  test("a page fills with visible rows even when the newest window is all excluded", async () => {
    // 20 excluded sessions newer than every real one.
    for (let i = 0; i < 20; i++)
      writeTranscript(uuid(++seq), 100_000 + i, `/tmp/gbrain-claude-cli-cwd-${1000 + i}`);
    const realIds: string[] = [];
    for (let i = 0; i < 5; i++) {
      const id = uuid(++seq);
      realIds.push(id);
      writeTranscript(id, 50_000 + i, "/Users/e/dev/personal/lfg");
    }

    const page = await listResumable({ limit: 5, exclude: ["*/gbrain-claude-cli-cwd-*"] });
    expect(page.sessions.map((s) => s.sessionId).sort()).toEqual([...realIds].sort());
    expect(page.sessions.every((s) => s.cwd === "/Users/e/dev/personal/lfg")).toBe(true);
    expect(page.nextBefore).toBeNull();
  });

  test("cursor pages through visible rows, skipping excluded ones in between", async () => {
    writeTranscript(uuid(++seq), 9_000, "/tmp/gbrain-claude-cli-cwd-1");
    const a = uuid(++seq);
    writeTranscript(a, 8_000, "/Users/e/dev/a");
    writeTranscript(uuid(++seq), 7_000, "/tmp/gbrain-claude-cli-cwd-2");
    const b = uuid(++seq);
    writeTranscript(b, 6_000, "/Users/e/dev/b");
    const c = uuid(++seq);
    writeTranscript(c, 5_000, "/Users/e/dev/c");

    const exclude = ["*/gbrain-claude-cli-cwd-*"];
    const page1 = await listResumable({ limit: 2, exclude });
    expect(page1.sessions.map((s) => s.sessionId)).toEqual([a, b]);
    expect(page1.nextBefore).toBe(6_000);
    const page2 = await listResumable({ limit: 2, before: page1.nextBefore, exclude });
    expect(page2.sessions.map((s) => s.sessionId)).toEqual([c]);
    expect(page2.nextBefore).toBeNull();
  });

  test("literal exclude hides the dir and its children on segment boundaries", async () => {
    const under = uuid(++seq);
    const sibling = uuid(++seq);
    writeTranscript(under, 4_000, "/Users/e/.gbrain/run");
    writeTranscript(sibling, 3_000, "/Users/e/.gbrainstorm");
    const page = await listResumable({ limit: 10, exclude: ["/Users/e/.gbrain"] });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([sibling]);
  });

  test("empty or unusable exclude entries leave the plain path untouched", async () => {
    const id = uuid(++seq);
    writeTranscript(id, 2_000, "/tmp/gbrain-claude-cli-cwd-9");
    for (const exclude of [[], ["~"], ["*"], [""]]) {
      const page = await listResumable({ limit: 10, exclude });
      expect(page.sessions.map((s) => s.sessionId)).toEqual([id]);
    }
  });
});

describe("searchResumable exclude", () => {
  test("search matches are filtered by exclude before paging", async () => {
    const hidden = uuid(++seq);
    const real = uuid(++seq);
    writeTranscript(hidden, 2_000, "/tmp/gbrain-claude-cli-cwd-3", "needle in the noise");
    writeTranscript(real, 1_000, "/Users/e/dev/lfg", "needle in the work");
    const page = await searchResumable({
      q: "needle",
      limit: 10,
      exclude: ["*/gbrain-claude-cli-cwd-*"],
    });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([real]);
  });
});
