import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "lfg-ranked-search-"));
const projects = join(root, "projects");
const data = join(root, "data");
mkdirSync(projects, { recursive: true });
mkdirSync(join(projects, "p"), { recursive: true });
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "ranked-test\n");
const old = {
  home: process.env.HOME,
  projects: process.env.LFG_CLAUDE_PROJECTS_DIR,
  data: process.env.LFG_DATA,
};
process.env.HOME = root;
process.env.LFG_CLAUDE_PROJECTS_DIR = projects;
process.env.LFG_DATA = data;
const { rankedSearchResumable, resetContentIndexForTests,
  startTranscriptSearchSync, transcriptSearchSyncing } = await import("./sessions");

afterAll(() => {
  resetContentIndexForTests();
  if (old.home == null) delete process.env.HOME; else process.env.HOME = old.home;
  if (old.projects == null) delete process.env.LFG_CLAUDE_PROJECTS_DIR; else process.env.LFG_CLAUDE_PROJECTS_DIR = old.projects;
  if (old.data == null) delete process.env.LFG_DATA; else process.env.LFG_DATA = old.data;
  rmSync(root, { recursive: true, force: true });
});

function write(id: number, title: string, assistant: string, cwd = "/tmp/noto", mtime?: number) {
  const sid = `00000000-0000-4000-8000-${String(id).padStart(12, "0")}`;
  writeFileSync(join(projects, "p", `${sid}.jsonl`), [
    { type: "user", cwd, message: { role: "user", content: title } },
    { type: "assistant", cwd, message: { role: "assistant", content: assistant } },
  ].map((row) => JSON.stringify(row)).join("\n") + "\n");
  if (mtime != null) utimesSync(join(projects, "p", `${sid}.jsonl`), mtime / 1000, mtime / 1000);
  return sid;
}

test("ranked API searches assistant prose across the corpus and pages a stable snapshot", async () => {
  const exact = write(1, "ultramarine plan", "ordinary answer");
  const prose = write(2, "unrelated title", "Here is the ultramarine analysis");
  const prose2 = write(3, "another title", "An ultramarine design note");
  const first = await rankedSearchResumable({ q: "ultramarine", limit: 1 });
  expect(first?.sessions.map((row) => row.sessionId)).toEqual([exact]);
  expect(first?.nextCursor).not.toBeNull();
  const second = await rankedSearchResumable({ q: "ultramarine", limit: 1, cursor: first!.nextCursor });
  const third = await rankedSearchResumable({ q: "ultramarine", limit: 1, cursor: second!.nextCursor });
  expect(new Set([first!.sessions[0].sessionId, second!.sessions[0].sessionId, third!.sessions[0].sessionId]))
    .toEqual(new Set([exact, prose, prose2]));
  expect(second!.sessions[0].lastUserText).toContain("Assistant:");
  expect(third!.nextCursor).toBeNull();
  const directory = await rankedSearchResumable({ q: "/tmp/noto", limit: 5 });
  expect(directory?.sessions).toHaveLength(3);
  const hidden = await rankedSearchResumable({ q: "ultramarine", limit: 5, exclude: ["/tmp/noto"] });
  expect(hidden?.sessions).toEqual([]);
}, 30_000);

test("directory-first recency ordering is applied before pagination", async () => {
  const now = Date.now();
  const old = now - 10 * 7 * 86400_000;
  const directoryOld = write(10, "ochre", "ochre repeated prose", "/tmp/ochre", old);
  const directoryNew = write(11, "New unrelated title", "ordinary", "/tmp/ochre", now - 1000);
  const titleOld = write(12, "ochre", "ochre repeated prose", "/tmp/other", old);
  const titleNew = write(13, "Discuss ochre", "ordinary", "/tmp/other", now);
  const proseNew = write(14, "Unrelated title", "ochre", "/tmp/other", now + 1000);
  const first = (await rankedSearchResumable({ q: "ochre", limit: 2 }))!;
  const second = (await rankedSearchResumable({ q: "ochre", limit: 2, cursor: first.nextCursor }))!;
  const third = (await rankedSearchResumable({ q: "ochre", limit: 2, cursor: second.nextCursor }))!;
  expect([...first.sessions, ...second.sessions, ...third.sessions].map(row => row.sessionId))
    .toEqual([directoryNew, directoryOld, titleNew, titleOld, proseNew]);
  expect(third.nextCursor).toBeNull();
}, 30_000);

test("startup reconciliation exposes a warming state until it completes", async () => {
  const stop = startTranscriptSearchSync();
  expect(transcriptSearchSyncing()).toBe(true);
  for (let i = 0; i < 30 && transcriptSearchSyncing(); i++) await Bun.sleep(100);
  expect(transcriptSearchSyncing()).toBe(false);
  stop();
}, 30_000);
