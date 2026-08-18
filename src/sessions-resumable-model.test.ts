import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Hermetic HOME, same shape as sessions-resumable.test.ts: these assertions are
// about what a transcript's tail says, so they must not read the real corpus.
const home = join(tmpdir(), `lfg-resumable-model-${Date.now()}-${Math.random().toString(16).slice(2)}`);
const projects = join(home, ".claude", "projects");
const codexSessions = join(home, ".codex", "sessions");
const data = join(home, "data");
const prevHome = process.env.HOME;
process.env.HOME = home;
process.env.LFG_CLAUDE_PROJECTS_DIR = projects;
process.env.LFG_DATA = data;
mkdirSync(data, { recursive: true });
writeFileSync(join(data, "host-id"), "host-a\n");

const { listResumable } = await import("./sessions.ts");

beforeEach(() => {
  rmSync(projects, { recursive: true, force: true });
  mkdirSync(projects, { recursive: true });
  rmSync(codexSessions, { recursive: true, force: true });
  mkdirSync(codexSessions, { recursive: true });
});

afterAll(() => {
  if (prevHome === undefined) delete process.env.HOME;
  else process.env.HOME = prevHome;
  delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  delete process.env.LFG_DATA;
  rmSync(home, { recursive: true, force: true });
});

function writeClaudeTranscript(id: string, lines: unknown[], mtime: number, cwd = "/tmp/proj") {
  const dir = join(projects, "p");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${id}.jsonl`);
  writeFileSync(path, `${[{ cwd }, ...lines].map((l) => JSON.stringify(l)).join("\n")}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
}

function writeCodexRollout(id: string, lines: unknown[], mtime: number, cwd = "/tmp/codex") {
  const dir = join(codexSessions, "2026", "08", "18");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `rollout-${id}.jsonl`);
  const head = {
    type: "session_meta",
    payload: { id, cwd, timestamp: new Date(mtime).toISOString() },
  };
  writeFileSync(path, `${[head, ...lines].map((l) => JSON.stringify(l)).join("\n")}\n`);
  const when = new Date(mtime);
  utimesSync(path, when, when);
}

describe("listResumable model", () => {
  test("a closed claude session reports the alias of its newest assistant turn", async () => {
    const id = "00000000-0000-4000-8000-0000000000a1";
    writeClaudeTranscript(
      id,
      [
        { type: "assistant", message: { model: "claude-sonnet-5", content: [] } },
        { type: "user", message: { content: "again" } },
        // Newest assistant turn wins — a mid-session /model switch must not be
        // masked by the launch model.
        { type: "assistant", message: { model: "claude-opus-5", content: [] } },
      ],
      5_000,
    );
    const page = await listResumable({ limit: 10 });
    expect(page.sessions.find((s) => s.sessionId === id)?.model).toBe("opus");
  });

  test("a closed codex session reports its raw model id, not an alias", async () => {
    const id = "00000000-0000-4000-8000-0000000000b1";
    writeCodexRollout(
      id,
      [
        { type: "turn_context", payload: { model: "gpt-5.6-terra" } },
        { type: "turn_context", payload: { model: "gpt-5.6-sol" } },
      ],
      6_000,
    );
    const page = await listResumable({ limit: 10 });
    expect(page.sessions.find((s) => s.sessionId === id)?.model).toBe("gpt-5.6-sol");
  });

  test("a transcript with no assistant turn reports null rather than guessing", async () => {
    const id = "00000000-0000-4000-8000-0000000000c1";
    writeClaudeTranscript(id, [{ type: "user", message: { content: "hi" } }], 7_000);
    const page = await listResumable({ limit: 10 });
    expect(page.sessions.find((s) => s.sessionId === id)?.model).toBe(null);
  });
});
