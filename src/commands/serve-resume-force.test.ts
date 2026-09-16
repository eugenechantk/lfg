import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { leasePathForTranscript } from "../leases.ts";
import { foreignLeaseVeto } from "./serve.ts";

// Transfer from an OFFLINE host: the source's lease is still fresh in the synced
// tree (nothing there could release it), so the target's resume must let the
// client override the peer veto with `force` — and must still veto without it.

const prevData = process.env.LFG_DATA;
const prevProjects = process.env.LFG_CLAUDE_PROJECTS_DIR;
const root = mkdtempSync(join(tmpdir(), "lfg-serve-resume-force-test-"));
const dataDir = join(root, "data");
const projectsDir = join(root, "projects");
const projectDir = join(projectsDir, "p");

const sid = "00000000-0000-4000-8000-0000000000c1";

beforeEach(() => {
  process.env.LFG_DATA = dataDir;
  process.env.LFG_CLAUDE_PROJECTS_DIR = projectsDir;
  rmSync(root, { recursive: true, force: true });
  mkdirSync(projectDir, { recursive: true });
  const transcript = join(projectDir, `${sid}.jsonl`);
  writeFileSync(transcript, JSON.stringify({ type: "user", uuid: "u1", message: { role: "user", content: "hi" } }) + "\n");
  // A peer host's lease, heartbeat just now: exactly what a host that went to
  // sleep mid-session leaves behind for the next ~90s.
  writeFileSync(
    leasePathForTranscript(sid, transcript),
    JSON.stringify({ hostId: "peer-host-that-is-asleep", pid: 4242, acquiredAt: Date.now() - 60_000, heartbeatAt: Date.now() }),
  );
});

afterAll(() => {
  if (prevData === undefined) delete process.env.LFG_DATA;
  else process.env.LFG_DATA = prevData;
  if (prevProjects === undefined) delete process.env.LFG_CLAUDE_PROJECTS_DIR;
  else process.env.LFG_CLAUDE_PROJECTS_DIR = prevProjects;
  rmSync(root, { recursive: true, force: true });
});

describe("resume foreign-lease veto", () => {
  test("a fresh peer lease vetoes a plain resume with 409 + liveOn", async () => {
    const veto = await foreignLeaseVeto(sid);
    expect(veto).not.toBeNull();
    expect(veto!.ok).toBe(false);
    if (veto && !veto.ok) {
      expect(veto.status).toBe(409);
      expect(veto.liveOn).toBe("peer-host-that-is-asleep");
    }
  });

  test("force skips the veto so an offline host's session can be taken over", async () => {
    expect(await foreignLeaseVeto(sid, true)).toBeNull();
  });

  test("no lease → no veto either way", async () => {
    const other = "00000000-0000-4000-8000-0000000000c2";
    writeFileSync(join(projectDir, `${other}.jsonl`), "{}\n");
    expect(await foreignLeaseVeto(other)).toBeNull();
    expect(await foreignLeaseVeto(other, true)).toBeNull();
  });
});
