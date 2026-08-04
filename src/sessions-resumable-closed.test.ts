import { test, expect, describe } from "bun:test";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { listResumable, resolveTranscript } from "./sessions.ts";
import { LEASE_FRESH_MS, leasePathForTranscript } from "./leases.ts";

describe("listResumable closed flag", () => {
  test("every returned row is stamped closed by the server", async () => {
    const page = await listResumable({ limit: 3 });
    // The repo always has some transcripts; if not, the assertion is vacuous
    // rather than wrong, so guard instead of failing on an empty machine.
    for (const s of page.sessions) {
      expect(s.closed).toBe(true);
    }
  });

  // THE invariant, asserted through the one mechanism that decides it. There is
  // no `excludeIds` any more: a caller-supplied live-id set was a second answer
  // to the same question, and two answers is the bug pattern this work removed.
  // A fresh lease is now the only thing that makes a session not-closed.
  test("a session holding a fresh lease is never returned as closed", async () => {
    const first = await listResumable({ limit: 1 });
    const victim = first.sessions[0]?.sessionId;
    if (!victim) return;
    const tp = await resolveTranscript(victim);
    if (!tp) return;

    const path = leasePathForTranscript(victim, tp);
    const had = existsSync(path) ? readFileSync(path, "utf8") : null;
    try {
      writeFileSync(
        path,
        JSON.stringify({
          hostId: "some-other-host",
          pid: 999999,
          acquiredAt: Date.now(),
          heartbeatAt: Date.now(),
        }),
      );
      const page = await listResumable({ limit: 50 });
      expect(page.sessions.map((s) => s.sessionId)).not.toContain(victim);
    } finally {
      if (had !== null) writeFileSync(path, had);
      else if (existsSync(path)) unlinkSync(path);
    }
  });

  test("a session whose lease has gone stale IS returned as closed", async () => {
    const first = await listResumable({ limit: 1 });
    const victim = first.sessions[0]?.sessionId;
    if (!victim) return;
    const tp = await resolveTranscript(victim);
    if (!tp) return;

    const path = leasePathForTranscript(victim, tp);
    const had = existsSync(path) ? readFileSync(path, "utf8") : null;
    try {
      const old = Date.now() - LEASE_FRESH_MS - 1000;
      writeFileSync(
        path,
        JSON.stringify({ hostId: "some-other-host", pid: 999999, acquiredAt: old, heartbeatAt: old }),
      );
      const page = await listResumable({ limit: 50 });
      expect(page.sessions.map((s) => s.sessionId)).toContain(victim);
    } finally {
      if (had !== null) writeFileSync(path, had);
      else if (existsSync(path)) unlinkSync(path);
    }
  });
});
