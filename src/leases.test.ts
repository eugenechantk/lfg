import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  LEASE_FRESH_MS,
  createLeaseManager,
  leasePathForTranscript,
  parseLease,
  sessionIdForTranscript,
} from "./leases.ts";

const SID = "00000000-0000-4000-8000-000000000001";

let root = "";
let projects = "";
let clock = 1_000_000;

async function resetFs() {
  if (root) rmSync(root, { recursive: true, force: true });
  root = await mkdtemp(join(tmpdir(), "lfg-leases-"));
  projects = join(root, "projects", "repo");
  mkdirSync(projects, { recursive: true });
  writeFileSync(transcriptPath(SID), "{}\n");
  clock = 1_000_000;
}

function transcriptPath(sessionId: string): string {
  return join(projects, `${sessionId}.jsonl`);
}

function manager(hostId: string) {
  return createLeaseManager({
    hostId: () => hostId,
    now: () => clock,
    resolveTranscript: async (sessionId) => transcriptPath(sessionId),
  });
}

function leasePath(sessionId = SID): string {
  return leasePathForTranscript(sessionId, transcriptPath(sessionId));
}

beforeEach(async () => {
  await resetFs();
});

afterAll(() => {
  if (root) rmSync(root, { recursive: true, force: true });
});

describe("leases", () => {
  test("round-trips acquire, read, renew, and release for our lease", async () => {
    const leases = manager("host-a");

    expect(await leases.acquireLease(SID, 1234)).toBe(true);
    expect(await leases.readLease(SID)).toEqual({
      hostId: "host-a",
      pid: 1234,
      acquiredAt: 1_000_000,
      heartbeatAt: 1_000_000,
    });

    clock += 30_000;
    expect(await leases.renewLease(SID)).toBe(true);
    expect(await leases.readLease(SID)).toEqual({
      hostId: "host-a",
      pid: 1234,
      acquiredAt: 1_000_000,
      heartbeatAt: 1_030_000,
    });

    expect(await leases.releaseLease(SID)).toBe(true);
    expect(await leases.readLease(SID)).toBeNull();
  });

  test("reports fresh foreign leases only inside the freshness window", async () => {
    const hostA = manager("host-a");
    const hostB = manager("host-b");

    await hostA.acquireLease(SID, 111);
    expect(await hostB.foreignFresh(SID)).toBe("host-a");
    expect(await hostA.foreignFresh(SID)).toBeNull();

    clock += LEASE_FRESH_MS;
    expect(await hostB.foreignFresh(SID)).toBeNull();
  });

  test("treats missing and corrupt lease files as no lease", async () => {
    const leases = manager("host-a");

    expect(await leases.readLease(SID)).toBeNull();
    writeFileSync(leasePath(), "{not json");
    expect(await leases.readLease(SID)).toBeNull();
    expect(await leases.foreignFresh(SID)).toBeNull();
    expect(await leases.renewLease(SID)).toBe(false);
    expect(await leases.releaseLease(SID)).toBe(false);
  });

  test("takes over a stale lease by overwriting it", async () => {
    const hostA = manager("host-a");
    const hostB = manager("host-b");

    await hostA.acquireLease(SID, 111);
    clock += LEASE_FRESH_MS;
    expect(await hostB.acquireLease(SID, 222)).toBe(true);

    expect(await hostB.readLease(SID)).toEqual({
      hostId: "host-b",
      pid: 222,
      acquiredAt: 1_090_000,
      heartbeatAt: 1_090_000,
    });
  });

  test("uses atomic writes and leaves no tmp file after a successful write", async () => {
    const leases = manager("host-a");

    expect(await leases.acquireLease(SID, 1234)).toBe(true);

    const files = readdirSync(projects);
    expect(files).toContain(`${SID}.lease.json`);
    expect(files.filter((f) => f.endsWith(".tmp"))).toEqual([]);
    expect(parseLease(readFileSync(leasePath(), "utf8"))).toEqual({
      hostId: "host-a",
      pid: 1234,
      acquiredAt: 1_000_000,
      heartbeatAt: 1_000_000,
    });
  });

  test("simulates two hosts sharing one projects dir with stale takeover", async () => {
    const hostA = manager("air");
    const hostB = manager("pro");

    await hostA.acquireLease(SID, 101);
    expect(await hostB.foreignFresh(SID)).toBe("air");

    clock += LEASE_FRESH_MS;
    expect(await hostB.foreignFresh(SID)).toBeNull();
    expect(await hostB.acquireLease(SID, 202)).toBe(true);
    expect(await hostA.foreignFresh(SID)).toBe("pro");
  });
});

// ---- field ownership: lfg and the hook share one record ----
//
// `renewLease` heartbeats every tick. Before the record was shared it rebuilt a
// bare 4-field lease, which would have erased hook-written turn state within a
// second of it landing — silently, and only in production where both writers run.
describe("shared record field ownership", () => {
  test("parseLease carries hook-owned fields through", () => {
    const raw = JSON.stringify({
      hostId: "host-a", pid: 42, acquiredAt: 1, heartbeatAt: 2,
      state: "running", stateAt: 99, stateEvent: "UserPromptSubmit", endReason: "clear",
    });
    const got = parseLease(raw)!;
    expect(got.state).toBe("running");
    expect(got.stateAt).toBe(99);
    expect(got.stateEvent).toBe("UserPromptSubmit");
    expect(got.endReason).toBe("clear");
  });

  test("a malformed hook field does not invalidate liveness", () => {
    const raw = JSON.stringify({
      hostId: "host-a", pid: 42, acquiredAt: 1, heartbeatAt: 2,
      state: "sideways", stateAt: "soon",
    });
    const got = parseLease(raw);
    expect(got).not.toBeNull();          // liveness survives — it gates resume
    expect(got!.hostId).toBe("host-a");
    expect(got!.state).toBeUndefined();  // but the bad value is dropped
  });

  test("renewLease preserves hook state while updating the heartbeat", async () => {
    const dir = mkdtempSync(join(tmpdir(), "lease-own-"));
    const tp = join(dir, `${SID}.jsonl`);
    writeFileSync(tp, "{}\n");
    const path = leasePathForTranscript(SID, tp);
    const mgr = createLeaseManager({
      hostId: () => "host-a",
      now: () => 1000,
      resolveTranscript: async () => tp,
    });
    await mgr.acquireLease(SID, 42);
    // The hook lands its fields independently, as a separate process would.
    const withState = { ...JSON.parse(readFileSync(path, "utf8")), state: "running", stateAt: 500 };
    writeFileSync(path, JSON.stringify(withState));

    expect(await mgr.renewLease(SID)).toBe(true);
    const after = JSON.parse(readFileSync(path, "utf8"));
    expect(after.state).toBe("running");   // hook's field survived the heartbeat
    expect(after.stateAt).toBe(500);
    expect(after.heartbeatAt).toBe(1000);  // lfg's field was updated
  });
});

// ---- the lease is named for the TRANSCRIPT's id, not lfg's session key ----
//
// For codex these differ: lfg keys the session `3f8dfe1e-…` while the agent (and
// its hook payload, and its rollout filename) says `019f03aa-…`. Keying the lease
// on lfg's id meant the hook wrote one filename and lfg read another — two
// records per session, hook state never found.
describe("lease filename keys off the transcript id", () => {
  test("claude: <uuid>.jsonl", () => {
    const id = "7233624d-85be-4a72-b1c9-a8fa18b9444f";
    expect(sessionIdForTranscript(`/p/${id}.jsonl`)).toBe(id);
  });

  test("codex: rollout-<timestamp>-<uuid>.jsonl, timestamp not mistaken for the id", () => {
    const id = "019fcd8e-dacc-7e71-8ec7-8d9e90ce8157";
    expect(sessionIdForTranscript(`/p/rollout-2026-08-05T00-15-19-${id}.jsonl`)).toBe(id);
  });

  test("unparseable name yields null so the caller can fall back", () => {
    expect(sessionIdForTranscript("/p/notes.jsonl")).toBeNull();
  });

  // The convergence that matters: lfg passes ITS id, the hook passes the agent's,
  // and both land on the same file.
  test("codex writer and reader converge on one path", () => {
    const threadId = "019f03aa-fae0-7c31-9a1e-2b7c4d5e6f70";
    const tp = `/p/rollout-2026-08-01T04-35-39-${threadId}.jsonl`;
    const lfgSideReader = leasePathForTranscript("3f8dfe1e-2ff0-4a1b-9c3d-000000000000", tp);
    const hookSideWriter = `/p/${threadId}.lease.json`; // what the hook computes
    expect(lfgSideReader).toBe(hookSideWriter);
  });

  test("claude is unaffected — the two ids were always the same", () => {
    const id = "7233624d-85be-4a72-b1c9-a8fa18b9444f";
    expect(leasePathForTranscript(id, `/p/${id}.jsonl`)).toBe(`/p/${id}.lease.json`);
  });

  test("falls back to the session id when the transcript name is opaque", () => {
    expect(leasePathForTranscript("sid-x", "/p/weird.jsonl")).toBe("/p/sid-x.lease.json");
  });
});

// ---- ensureLease: enumeration-driven, never steals ----
//
// The prerequisite for `closed ≡ no fresh lease`. Before this, `renewLease`
// no-opped unless the lease was already ours, so adopted sessions never got one
// — and a leaseless RUNNING session would read as ended, which is the dangerous
// direction (hides a live agent, offers a resume that would double-spawn).
describe("ensureLease", () => {
  const mk = (host: string, t: () => number, tp: string) =>
    createLeaseManager({ hostId: () => host, now: t, resolveTranscript: async () => tp });

  const setup = () => {
    const dir = mkdtempSync(join(tmpdir(), "ensure-"));
    const tp = join(dir, `${SID}.jsonl`);
    writeFileSync(tp, "{}\n");
    return { dir, tp, path: leasePathForTranscript(SID, tp) };
  };

  test("acquires for a session that never had a lease (the adopted-session gap)", async () => {
    const { tp, path } = setup();
    expect(await mk("host-a", () => 1000, tp).ensureLease(SID, 42)).toBe(true);
    const l = parseLease(readFileSync(path, "utf8"))!;
    expect(l.hostId).toBe("host-a");
    expect(l.pid).toBe(42);
  });

  test("renews our own lease rather than re-acquiring", async () => {
    const { tp, path } = setup();
    const a = mk("host-a", () => 1000, tp);
    await a.ensureLease(SID, 42);
    const later = mk("host-a", () => 5000, tp);
    expect(await later.ensureLease(SID, 42)).toBe(true);
    const l = parseLease(readFileSync(path, "utf8"))!;
    expect(l.acquiredAt).toBe(1000); // unchanged — this was a renew
    expect(l.heartbeatAt).toBe(5000);
  });

  test("refuses to steal another host's FRESH lease", async () => {
    const { tp, path } = setup();
    await mk("host-b", () => 1000, tp).ensureLease(SID, 7);
    // host-a tries while b's lease is still fresh
    expect(await mk("host-a", () => 1000 + LEASE_FRESH_MS - 1, tp).ensureLease(SID, 42)).toBe(false);
    expect(parseLease(readFileSync(path, "utf8"))!.hostId).toBe("host-b");
  });

  test("takes over once the other host's lease goes stale", async () => {
    const { tp, path } = setup();
    await mk("host-b", () => 1000, tp).ensureLease(SID, 7);
    expect(await mk("host-a", () => 1000 + LEASE_FRESH_MS + 1, tp).ensureLease(SID, 42)).toBe(true);
    expect(parseLease(readFileSync(path, "utf8"))!.hostId).toBe("host-a");
  });

  test("takeover preserves the hook's fields", async () => {
    const { tp, path } = setup();
    await mk("host-b", () => 1000, tp).ensureLease(SID, 7);
    const withState = { ...JSON.parse(readFileSync(path, "utf8")), state: "running", stateAt: 900 };
    writeFileSync(path, JSON.stringify(withState));
    await mk("host-a", () => 1000 + LEASE_FRESH_MS + 1, tp).ensureLease(SID, 42);
    const l = parseLease(readFileSync(path, "utf8"))!;
    expect(l.hostId).toBe("host-a");
    expect(l.state).toBe("running"); // other writer's field survived
    expect(l.stateAt).toBe(900);
  });
});
