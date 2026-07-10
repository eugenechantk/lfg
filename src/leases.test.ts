import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  LEASE_FRESH_MS,
  createLeaseManager,
  leasePathForTranscript,
  parseLease,
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
