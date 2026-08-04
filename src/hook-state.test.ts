import { test, expect, describe, beforeEach } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  parseHookState,
  hookState,
  forgetHookState,
  __resetHookStateCache,
  __hookStateReadCount,
} from "./hook-state.ts";

const dir = mkdtempSync(join(tmpdir(), "hook-state-"));
process.env.LFG_AGENT_STATE_DIR = dir;

const put = (sid: string, body: unknown): string => {
  const p = join(dir, `${sid}.json`);
  writeFileSync(p, typeof body === "string" ? body : JSON.stringify(body));
  return p;
};

beforeEach(() => __resetHookStateCache());

describe("parseHookState", () => {
  test("accepts each valid state", () => {
    for (const s of ["running", "idle", "ended"]) {
      expect(parseHookState(JSON.stringify({ state: s, at: 1 }))?.state).toBe(s as never);
    }
  });

  test("rejects an unknown state", () => {
    expect(parseHookState(JSON.stringify({ state: "thinking", at: 1 }))).toBeNull();
  });

  // Without a usable `at` the record cannot take part in recency arbitration
  // against the transcript, which is the whole point of the layer.
  test("rejects a record with no usable timestamp", () => {
    expect(parseHookState(JSON.stringify({ state: "running" }))).toBeNull();
    expect(parseHookState(JSON.stringify({ state: "running", at: "soon" }))).toBeNull();
  });

  test("a torn or non-JSON write is no opinion, not a crash", () => {
    expect(parseHookState('{"state":"run')).toBeNull();
    expect(parseHookState("")).toBeNull();
    expect(parseHookState("null")).toBeNull();
  });
});

describe("hookState", () => {
  test("missing file means no opinion", async () => {
    expect(await hookState("never-seen")).toBeNull();
  });

  test("empty session id means no opinion", async () => {
    expect(await hookState("")).toBeNull();
  });

  test("reads the agent's last word", async () => {
    put("s1", { state: "running", at: 1000, event: "UserPromptSubmit" });
    const got = await hookState("s1");
    expect(got?.state).toBe("running");
    expect(got?.at).toBe(1000);
    expect(got?.event).toBe("UserPromptSubmit");
  });

  test("memoizes until the file actually changes", async () => {
    put("s2", { state: "running", at: 1000 });
    await hookState("s2");
    const after = __hookStateReadCount();
    await hookState("s2");
    await hookState("s2");
    expect(__hookStateReadCount()).toBe(after); // stat only, no re-parse

    // A rewrite with a different size must invalidate.
    put("s2", { state: "idle", at: 2000, event: "Stop" });
    forgetHookState("s2");
    expect((await hookState("s2"))?.state).toBe("idle");
  });
});

// The hook is a separate executable that other programs invoke. Testing the
// TypeScript reader against hand-written fixtures would prove nothing about it,
// so drive the real script with real payloads.
describe("scripts/lfg-agent-hook.py (executed, not simulated)", () => {
  const script = join(import.meta.dir, "..", "scripts", "lfg-agent-hook.py");
  const runDir = mkdtempSync(join(tmpdir(), "hook-run-"));

  const fire = async (payload: unknown): Promise<number> => {
    const p = Bun.spawn(["python3", script], {
      stdin: new TextEncoder().encode(JSON.stringify(payload)),
      env: { ...process.env, LFG_AGENT_STATE_DIR: runDir },
      stdout: "pipe",
      stderr: "pipe",
    });
    return await p.exited;
  };

  const readState = (sid: string): Record<string, unknown> | null => {
    const p = join(runDir, `${sid}.json`);
    return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : null;
  };

  // No `transcript_path` in these payloads on purpose: that routes to the
  // host-local fallback store. The lease path (the normal case) is covered by
  // "hook writes the lease, preserving lfg's fields" below.
  test("a Claude Code turn writes running then idle", async () => {
    expect(await fire({ session_id: "abc", hook_event_name: "UserPromptSubmit" })).toBe(0);
    expect(readState("abc")?.state).toBe("running");

    expect(await fire({ session_id: "abc", hook_event_name: "Stop" })).toBe(0);
    expect(readState("abc")?.state).toBe("idle");
  });

  test("a codex payload works through the same path, carrying turn_id", async () => {
    await fire({ session_id: "cdx", hook_event_name: "UserPromptSubmit", turn_id: "t-1" });
    expect(readState("cdx")?.state).toBe("running");
    expect(readState("cdx")?.turnId).toBe("t-1");
  });

  test("SessionEnd records the lifecycle fact and WHY", async () => {
    await fire({ session_id: "gone", hook_event_name: "SessionEnd", reason: "prompt_input_exit" });
    expect(readState("gone")?.state).toBe("ended");
    // `reason` is what separates a session that actually went away from one
    // whose id rolled over inside a live process (`clear`/`resume`). lfg's
    // `closed` is otherwise inferred from absence, which cannot tell them apart.
    expect(readState("gone")?.reason).toBe("prompt_input_exit");
  });

  test("an id rolling over inside a live process is distinguishable", async () => {
    await fire({ session_id: "rolled", hook_event_name: "SessionEnd", reason: "clear" });
    expect(readState("rolled")?.reason).toBe("clear");
  });

  test("non-turn events write nothing", async () => {
    await fire({ session_id: "quiet", hook_event_name: "PreToolUse" });
    expect(readState("quiet")).toBeNull();
  });

  // Claude Code treats exit 2 on UserPromptSubmit as "block the prompt and erase
  // it". A state-tracking hook must never be able to cost the user their message,
  // so every malformed input still has to exit 0.
  test("garbage input exits 0 and writes nothing", async () => {
    const p = Bun.spawn(["python3", script], {
      stdin: new TextEncoder().encode("not json at all"),
      env: { ...process.env, LFG_AGENT_STATE_DIR: runDir },
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(await p.exited).toBe(0);
    await fire({ hook_event_name: "Stop" }); // no session_id
    await fire({ session_id: "x" }); // no event
    expect(readState("undefined")).toBeNull();
  });

  test("a session id that could escape the directory is refused", async () => {
    await fire({ session_id: "../escaped", hook_event_name: "Stop" });
    expect(existsSync(join(runDir, "..", "escaped.json"))).toBe(false);
    expect(readdirSync(runDir).some((f) => f.includes("escaped"))).toBe(false);
  });

  test("writes are atomic — no .tmp files survive", async () => {
    await fire({ session_id: "atomic", hook_event_name: "Stop" });
    expect(readdirSync(runDir).filter((f) => f.startsWith(".tmp-"))).toHaveLength(0);
  });

  test("the reader agrees with what the real hook wrote", async () => {
    process.env.LFG_AGENT_STATE_DIR = runDir;
    __resetHookStateCache();
    await fire({ session_id: "roundtrip", hook_event_name: "UserPromptSubmit" });
    const got = await hookState("roundtrip");
    expect(got?.state).toBe("running");
    expect(typeof got?.at).toBe("number");
    process.env.LFG_AGENT_STATE_DIR = dir;
  });
});

// ---- the hook writes into the LEASE (shared record) ----
//
// The whole point of the shared record: the hook reaches it with no server and
// no lookup (its payload carries `transcript_path`), and because the lease sits
// in the synced tree, hook-written state crosses hosts. These tests drive the
// real script, so they prove the merge rather than a TypeScript model of it.
describe("hook writes the lease, preserving lfg's fields", () => {
  const script = join(import.meta.dir, "..", "scripts", "lfg-agent-hook.py");
  const d = mkdtempSync(join(tmpdir(), "hook-lease-"));
  const sid = "11111111-1111-4111-8111-111111111111";
  const transcript = join(d, `${sid}.jsonl`);
  const leasePath = join(d, `${sid}.lease.json`);

  const fire = async (payload: unknown) => {
    const p = Bun.spawn(["python3", script], {
      stdin: new TextEncoder().encode(JSON.stringify(payload)),
      stdout: "pipe", stderr: "pipe",
    });
    return await p.exited;
  };
  const lease = () => JSON.parse(readFileSync(leasePath, "utf8"));

  test("writes state next to the transcript without touching liveness fields", async () => {
    writeFileSync(transcript, "{}\n");
    // lfg got there first, as it would in production.
    writeFileSync(leasePath, JSON.stringify({
      hostId: "host-a", pid: 4242, acquiredAt: 10, heartbeatAt: 20,
    }));

    expect(await fire({
      session_id: sid, hook_event_name: "UserPromptSubmit", transcript_path: transcript,
    })).toBe(0);

    const l = lease();
    expect(l.state).toBe("running");
    expect(typeof l.stateAt).toBe("number");
    expect(l.stateEvent).toBe("UserPromptSubmit");
    // lfg's fields survived — the other half of field ownership.
    expect(l.hostId).toBe("host-a");
    expect(l.pid).toBe(4242);
    expect(l.acquiredAt).toBe(10);
    expect(l.heartbeatAt).toBe(20);
  });

  test("Stop flips state and still preserves liveness", async () => {
    await fire({ session_id: sid, hook_event_name: "Stop", transcript_path: transcript });
    const l = lease();
    expect(l.state).toBe("idle");
    expect(l.hostId).toBe("host-a");
  });

  // `clear` rolls the id over inside a LIVE process, so the lease must survive —
  // releasing it would report a running agent as closed.
  test("SessionEnd/clear annotates but does NOT release the lease", async () => {
    await fire({
      session_id: sid, hook_event_name: "SessionEnd",
      transcript_path: transcript, reason: "clear",
    });
    expect(existsSync(leasePath)).toBe(true);
    const l = lease();
    expect(l.state).toBe("ended");
    expect(l.endReason).toBe("clear");
    expect(l.pid).toBe(4242);
  });

  // A real end releases, so `closed ≡ no fresh lease` resolves immediately
  // instead of waiting out the 90s heartbeat window — one rule, no second check.
  test("SessionEnd with a terminal reason RELEASES the lease", async () => {
    expect(existsSync(leasePath)).toBe(true);
    await fire({
      session_id: sid, hook_event_name: "SessionEnd",
      transcript_path: transcript, reason: "prompt_input_exit",
    });
    expect(existsSync(leasePath)).toBe(false);
  });

  test("a reasonless SessionEnd also releases — absence of a rollover marker is not a rollover", async () => {
    writeFileSync(leasePath, JSON.stringify({ hostId: "h", pid: 1, acquiredAt: 1, heartbeatAt: 2 }));
    await fire({ session_id: sid, hook_event_name: "SessionEnd", transcript_path: transcript });
    expect(existsSync(leasePath)).toBe(false);
  });

  test("no lease yet: the hook creates one carrying only its own fields", async () => {
    const sid2 = "22222222-2222-4222-8222-222222222222";
    const t2 = join(d, `${sid2}.jsonl`);
    writeFileSync(t2, "{}\n");
    await fire({ session_id: sid2, hook_event_name: "UserPromptSubmit", transcript_path: t2 });
    const l = JSON.parse(readFileSync(join(d, `${sid2}.lease.json`), "utf8"));
    expect(l.state).toBe("running");
    expect(l.hostId).toBeUndefined(); // liveness is lfg's to assert, not ours
  });

  test("no transcript in the payload falls back rather than dropping the update", async () => {
    const runDir = mkdtempSync(join(tmpdir(), "hook-fallback-"));
    const p = Bun.spawn(["python3", script], {
      stdin: new TextEncoder().encode(JSON.stringify({ session_id: "nopath", hook_event_name: "Stop" })),
      env: { ...process.env, LFG_AGENT_STATE_DIR: runDir },
      stdout: "pipe", stderr: "pipe",
    });
    expect(await p.exited).toBe(0);
    expect(JSON.parse(readFileSync(join(runDir, "nopath.json"), "utf8")).state).toBe("idle");
  });

  test("no .tmp files survive in the synced directory", () => {
    expect(readdirSync(d).filter((f) => f.startsWith(".tmp-"))).toHaveLength(0);
  });
});
