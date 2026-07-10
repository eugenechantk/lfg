import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = join(tmpdir(), `lfg-resumable-${Date.now()}-${Math.random().toString(16).slice(2)}`);
const projects = join(home, ".claude", "projects");
const data = join(home, "data");
process.env.LFG_CLAUDE_PROJECTS_DIR = projects;
process.env.LFG_DATA = data;
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "host-a\n");

const { listResumable } = await import("./sessions.ts");

beforeEach(() => {
  rmSync(projects, { recursive: true, force: true });
  mkdirSync(projects, { recursive: true });
});

afterAll(() => {
  delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  delete process.env.LFG_DATA;
  rmSync(home, { recursive: true, force: true });
});

function writeTranscript(project: string, id: string, mtime: number, cwd = `/tmp/${project}`) {
  const dir = join(projects, project);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  writeFileSync(path, `${JSON.stringify({ cwd })}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
}

describe("listResumable pagination", () => {
  test("pages newest-first with before cursor and excludes live ids before paging", async () => {
    const ids = [
      "00000000-0000-4000-8000-000000000001",
      "00000000-0000-4000-8000-000000000002",
      "00000000-0000-4000-8000-000000000003",
      "00000000-0000-4000-8000-000000000004",
      "00000000-0000-4000-8000-000000000005",
    ];
    writeTranscript("p", ids[0], 5_000);
    writeTranscript("p", ids[1], 4_000);
    writeTranscript("p", ids[2], 3_000);
    writeTranscript("p", ids[3], 2_000);
    writeTranscript("p", ids[4], 1_000);
    writeTranscript("p-copy", ids[0], 1_500);

    const first = await listResumable({ limit: 2, excludeIds: new Set([ids[1]]) });
    expect(first.sessions.map((s) => s.sessionId)).toEqual([ids[0], ids[2]]);
    expect(first.nextBefore).toBe(first.sessions[1].lastActivityAt);

    const second = await listResumable({ limit: 2, before: first.nextBefore });
    expect(second.sessions.map((s) => s.sessionId)).toEqual([ids[3], ids[4]]);
    expect(second.nextBefore).toBeNull();
  });

  test("keeps default limit and reports no cursor when exhausted", async () => {
    writeTranscript("p", "00000000-0000-4000-8000-000000000101", 1_000);

    const page = await listResumable();
    expect(page.sessions).toHaveLength(1);
    expect(page.nextBefore).toBeNull();
  });

  test("excludes sessions with a fresh foreign lease", async () => {
    const leased = "00000000-0000-4000-8000-000000000201";
    const resumable = "00000000-0000-4000-8000-000000000202";
    writeTranscript("p", leased, 2_000);
    writeTranscript("p", resumable, 1_000);
    writeFileSync(
      join(projects, "p", `${leased}.lease.json`),
      JSON.stringify({
        hostId: "host-b",
        pid: 99,
        acquiredAt: Date.now(),
        heartbeatAt: Date.now(),
      }),
    );

    const page = await listResumable({ limit: 10 });
    expect(page.sessions.map((s) => s.sessionId)).toEqual([resumable]);
    expect(page.nextBefore).toBeNull();
  });
});
