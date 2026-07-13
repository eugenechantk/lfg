import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { addManaged } from "../managed.ts";
import {
  attachPendingForkTranscripts,
  liveStreamInitialState,
  messagesResponseForSession,
  type LiveStreamPane,
} from "./serve.ts";
import type { Session } from "../sessions.ts";

const prevData = process.env.LFG_DATA;
const prevProjects = process.env.LFG_CLAUDE_PROJECTS_DIR;
const root = mkdtempSync(join(tmpdir(), "lfg-serve-fork-test-"));
const dataDir = join(root, "data");
const projectsDir = join(root, "projects");
const projectDir = join(projectsDir, "p");

const sourceSid = "00000000-0000-4000-8000-0000000000a1";
const forkSid = "00000000-0000-4000-8000-0000000000f1";
const missingSourceSid = "00000000-0000-4000-8000-0000000000a2";
const missingForkSid = "00000000-0000-4000-8000-0000000000f2";
const unknownSid = "00000000-0000-4000-8000-000000000099";

beforeEach(() => {
  process.env.LFG_DATA = dataDir;
  process.env.LFG_CLAUDE_PROJECTS_DIR = projectsDir;
  rmSync(root, { recursive: true, force: true });
  mkdirSync(projectDir, { recursive: true });
});

afterAll(() => {
  if (prevData === undefined) delete process.env.LFG_DATA;
  else process.env.LFG_DATA = prevData;
  if (prevProjects === undefined) delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  else process.env.LFG_CLAUDE_PROJECTS_DIR = prevProjects;
  rmSync(root, { recursive: true, force: true });
});

function transcriptPath(sid: string): string {
  return join(projectDir, `${sid}.jsonl`);
}

function line(id: string, text: string): string {
  return JSON.stringify({
    type: "user",
    uuid: id,
    timestamp: "2026-07-13T00:00:00.000Z",
    message: { role: "user", content: text },
  }) + "\n";
}

function addForkRecord(sessionId = forkSid, forkedFrom = sourceSid, forkSourceBytes = 0) {
  addManaged({
    tmuxName: `lfg-${sessionId.slice(-2)}`,
    cwd: "/repo",
    createdAt: 1,
    agent: "claude",
    sessionId,
    forkedFrom,
    forkSourceBytes,
  });
}

describe("fork /messages fallback", () => {
  test("serves source snapshot messages with forkPending when fork transcript is missing", async () => {
    const first = line("m1", "first");
    const second = line("m2", "second");
    writeFileSync(transcriptPath(sourceSid), first + second + line("m3", "after fork"));
    addForkRecord(forkSid, sourceSid, first.length + second.length);

    const res = await messagesResponseForSession(
      forkSid,
      new URL(`http://lfg.test/api/sessions/${forkSid}/messages?full=1`),
    );
    const body = await res.json() as { forkPending?: boolean; messages: Array<{ text: string }> };

    expect(res.status).toBe(200);
    expect(body.forkPending).toBe(true);
    expect(body.messages.map((m) => m.text)).toEqual(["first", "second"]);
  });

  test("unknown missing transcript still 404s", async () => {
    const res = await messagesResponseForSession(
      unknownSid,
      new URL(`http://lfg.test/api/sessions/${unknownSid}/messages`),
    );

    expect(res.status).toBe(404);
  });

  test("fork whose source transcript is missing still 404s", async () => {
    addForkRecord(missingForkSid, missingSourceSid, 100);

    const res = await messagesResponseForSession(
      missingForkSid,
      new URL(`http://lfg.test/api/sessions/${missingForkSid}/messages`),
    );

    expect(res.status).toBe(404);
  });
});

describe("fork live stream pending attach", () => {
  test("only lineage-backed unresolved ids enter pending and attach with one reset at EOF", async () => {
    addForkRecord(forkSid, sourceSid, 100);
    const sessions = [
      { sessionId: forkSid, tmuxTarget: null },
    ] as Session[];

    const initial = await liveStreamInitialState([forkSid, unknownSid], {
      listSessions: async () => sessions,
    });

    expect(initial.panes).toEqual([]);
    expect([...initial.pending]).toEqual([forkSid]);

    const forkTranscript = line("m1", "already in fork") + line("m2", "first fork turn");
    writeFileSync(transcriptPath(forkSid), forkTranscript);
    const sent: string[] = [];
    const offsets = new Map<string, number>();
    const panes: LiveStreamPane[] = [];

    const attached = await attachPendingForkTranscripts({
      pending: initial.pending,
      panes,
      sessions: initial.sessions,
      offsets,
      send: (s) => sent.push(s),
      listSessions: async () => sessions,
    });
    const secondPass = await attachPendingForkTranscripts({
      pending: initial.pending,
      panes,
      sessions: initial.sessions,
      offsets,
      send: (s) => sent.push(s),
      listSessions: async () => sessions,
    });

    expect(attached).toBe(1);
    expect(secondPass).toBe(0);
    expect(panes.map((p) => p.sid)).toEqual([forkSid]);
    expect(offsets.get(forkSid)).toBe(forkTranscript.length);
    expect(sent).toEqual([`event: reset\ndata: ${JSON.stringify({ sid: forkSid })}\n\n`]);
    expect([...initial.pending]).toEqual([]);
  });
});
