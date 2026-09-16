import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { transcriptStatus } from "./serve.ts";

// Transfer pre-flight: the target reports whether it holds the synced transcript
// and how fresh its copy is, so the client can refuse or warn BEFORE closing the
// source. `found: false` is a body, never a 404 (a 404 means an old server).

const prevData = process.env.LFG_DATA;
const prevProjects = process.env.LFG_CLAUDE_PROJECTS_DIR;
const root = mkdtempSync(join(tmpdir(), "lfg-transcript-status-test-"));
const projectsDir = join(root, "projects");
const projectDir = join(projectsDir, "p");
const cwdDir = join(root, "repo-that-exists");

const sid = "00000000-0000-4000-8000-0000000000d1";
const lastTs = "2026-09-15T08:00:00.000Z";

function line(type: string, id: string, ts: string, cwd: string, text: string): string {
  const content = type === "user" ? text : [{ type: "text", text }];
  return JSON.stringify({ type, uuid: id, timestamp: ts, cwd, message: { role: type, content } }) + "\n";
}

beforeEach(() => {
  process.env.LFG_DATA = join(root, "data");
  process.env.LFG_CLAUDE_PROJECTS_DIR = projectsDir;
  rmSync(root, { recursive: true, force: true });
  mkdirSync(projectDir, { recursive: true });
  mkdirSync(cwdDir, { recursive: true });
});

afterAll(() => {
  if (prevData === undefined) delete process.env.LFG_DATA;
  else process.env.LFG_DATA = prevData;
  if (prevProjects === undefined) delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  else process.env.LFG_CLAUDE_PROJECTS_DIR = prevProjects;
  rmSync(root, { recursive: true, force: true });
});

describe("transcriptStatus", () => {
  test("missing transcript → found:false (a body, not a throw)", async () => {
    expect(await transcriptStatus(sid, async () => null)).toEqual({ found: false });
  });

  test("present transcript → cwd, cwdExists, bytes, and the LAST MESSAGE timestamp", async () => {
    const path = join(projectDir, `${sid}.jsonl`);
    writeFileSync(
      path,
      line("user", "u1", "2026-09-15T07:00:00.000Z", cwdDir, "hi") +
        line("assistant", "a1", lastTs, cwdDir, "hello"),
    );
    const st = await transcriptStatus(sid, async () => path);
    expect(st.found).toBe(true);
    if (st.found) {
      expect(st.agent).toBe("claude");
      expect(st.cwd).toBe(cwdDir);
      expect(st.cwdExists).toBe(true);
      expect(st.bytes).toBeGreaterThan(0);
      expect(st.lastActivityAt).toBe(Date.parse(lastTs));
    }
  });

  test("a cwd that only exists on the other Mac → cwdExists:false", async () => {
    const path = join(projectDir, `${sid}.jsonl`);
    writeFileSync(path, line("user", "u1", lastTs, join(root, "nope"), "hi"));
    const st = await transcriptStatus(sid, async () => path);
    expect(st.found && st.cwdExists).toBe(false);
  });
});
