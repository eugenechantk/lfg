import { test, expect, describe } from "bun:test";
import {
  reduceTransition,
  reduceFleetLiveActivity,
  orderFleetRows,
  liveActivitiesEnabled,
  buildPayload,
  runPushTick,
  type LiveActivityActive,
  type PriorState,
  type SessionState,
  type TickDeps,
} from "./watcher.ts";
import { apnsBody, type ApnsConfig, type ApnsPayload } from "./apns.ts";
import type { LiveActivityPush } from "./liveactivity.ts";

const seed = (
  busy: boolean,
  prompt: boolean,
  lastNotifiedAt = Number.NEGATIVE_INFINITY,
): PriorState => ({
  busy,
  promptPresent: prompt,
  lastNotifiedAt,
});
const obs = (busy: boolean, prompt: boolean, q?: string): SessionState => ({
  busy,
  promptPresent: prompt,
  promptQuestion: q ?? null,
});

describe("reduceTransition (SC3)", () => {
  test("busy → idle with no prompt emits 'finished'", () => {
    const r = reduceTransition(seed(true, false), obs(false, false), 1000);
    expect(r.event).toBe("finished");
  });

  test("busy → idle with a pending prompt emits 'needs-input'", () => {
    const r = reduceTransition(seed(true, false), obs(false, true, "Pick one"), 1000);
    expect(r.event).toBe("needs-input");
  });

  test("still working emits nothing", () => {
    expect(reduceTransition(seed(true, false), obs(true, false), 1000).event).toBeNull();
  });

  test("staying idle (no new prompt) emits nothing on the next tick", () => {
    const next = reduceTransition(seed(true, false), obs(false, false), 1000);
    expect(next.event).toBe("finished");
    // Same session, still idle, no change → silent.
    const again = reduceTransition(next.state, obs(false, false), 5000);
    expect(again.event).toBeNull();
  });

  test("a prompt appearing while already idle emits 'needs-input'", () => {
    const r = reduceTransition(seed(false, false, 0), obs(false, true, "Allow?"), 20_000);
    expect(r.event).toBe("needs-input");
  });

  test("'finished' then a late prompt within the dedupe window does NOT double-fire", () => {
    const a = reduceTransition(seed(true, false), obs(false, false), 1000);
    expect(a.event).toBe("finished");
    const b = reduceTransition(a.state, obs(false, true, "Allow?"), 1000 + 2000); // 2s later
    expect(b.event).toBeNull();
  });

  test("a prompt appearing well after the dedupe window does fire", () => {
    const a = reduceTransition(seed(true, false), obs(false, false), 1000);
    const b = reduceTransition(a.state, obs(false, true, "Allow?"), 1000 + 11_000); // 11s later
    expect(b.event).toBe("needs-input");
  });
});

describe("buildPayload", () => {
  test("needs-input uses the question text", () => {
    const p = buildPayload({ sessionId: "abc", title: "Fix the bug" }, "needs-input", "Which file?");
    expect(p.title).toContain("🙋");
    expect(p.body).toBe("Which file?");
    expect(p.kind).toBe("needs-input");
    expect(p.sid).toBe("abc");
  });

  test("finished has a generic body", () => {
    const p = buildPayload({ sessionId: "abc", title: "Fix the bug" }, "finished");
    expect(p.title).toContain("✅");
    expect(p.kind).toBe("finished");
  });

  test("falls back to a session-id stub when there's no title", () => {
    const p = buildPayload({ sessionId: "0123456789ab" }, "finished");
    expect(p.title).toContain("01234567");
  });
});

describe("reduceFleetLiveActivity", () => {
  test("starts when the fleet first has an active session", () => {
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) }],
      active: null,
      now: 1_700,
      hostName: "mac",
    });
    expect(r.action?.event).toBe("start");
    expect(r.nextActive?.startedAt).toBe(1_700);
    expect(r.action?.push.body.aps).toMatchObject({
      event: "start",
      "content-state": {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", host: "mac", state: "working", since: 1_700 }],
        hosts: [{ name: "mac", online: true }],
        updatedAt: 1_700,
      },
      attributes: { fleetId: "fleet" },
      "attributes-type": "LFGFleetAttributes",
    });
  });

  test("does not start for an all-idle fleet", () => {
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }],
      active: null,
      now: 1_700,
      hostName: "mac",
    });
    expect(r.action).toBeNull();
    expect(r.nextActive).toBeNull();
  });

  test("updates on aggregate count and row changes", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", host: "mac", state: "working", since: 1_700 }],
        hosts: [{ name: "mac", online: true }],
        updatedAt: 1_700,
      },
    };
    const r = reduceFleetLiveActivity({
      observations: [
        { session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) },
        { session: { sessionId: "s2", title: "Approve" }, observed: obs(false, true, "Approve?") },
      ],
      active,
      now: 1_710,
      hostName: "mac",
    });
    expect(r.action?.event).toBe("update");
    expect(r.action?.push.body.aps["content-state"]).toEqual({
      working: 1,
      needsInput: 1,
      rows: [
        { sid: "s2", title: "Approve", host: "mac", state: "blocked", since: 1_710 },
        { sid: "s1", title: "Job", host: "mac", state: "working", since: 1_700 },
      ],
      hosts: [{ name: "mac", online: true }],
      updatedAt: 1_710,
    });
  });

  test("updates when host status changes", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", host: "mac", state: "working", since: 1_700 }],
        hosts: [{ name: "mac", online: false }],
        updatedAt: 1_700,
      },
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) }],
      active,
      now: 1_710,
      hostName: "mac",
    });
    expect(r.action?.event).toBe("update");
    expect(r.action?.push.body.aps["content-state"]?.hosts).toEqual([{ name: "mac", online: true }]);
  });

  test("ends when the fleet becomes all idle", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", host: "mac", state: "working", since: 1_700 }],
        hosts: [{ name: "mac", online: true }],
        updatedAt: 1_700,
      },
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }],
      active,
      now: 1_730,
      hostName: "mac",
    });
    expect(r.action?.event).toBe("end");
    expect(r.nextActive).toBeNull();
    expect(r.action?.push.body.aps["content-state"]).toEqual({
      working: 0,
      needsInput: 0,
      rows: [],
      hosts: [{ name: "mac", online: true }],
      updatedAt: 1_730,
    });
    expect(r.action?.push.body.aps["dismissal-date"]).toBe(1_730);
  });

  test("orders blocked first, oldest since first, and caps at three rows", () => {
    expect(
      orderFleetRows([
        { sid: "w2", title: "Work 2", host: "mac", state: "working", since: 20 },
        { sid: "b2", title: "Block 2", host: "mac", state: "blocked", since: 12 },
        { sid: "i1", title: "Idle", host: "mac", state: "idle", since: 1 },
        { sid: "b1", title: "Block 1", host: "mac", state: "blocked", since: 10 },
        { sid: "w1", title: "Work 1", host: "mac", state: "working", since: 5 },
      ]),
    ).toEqual([
      { sid: "b1", title: "Block 1", host: "mac", state: "blocked", since: 10 },
      { sid: "b2", title: "Block 2", host: "mac", state: "blocked", since: 12 },
      { sid: "w1", title: "Work 1", host: "mac", state: "working", since: 5 },
    ]);
  });

  test("preserves since for matching sid and state, and counts busy plus blocked sessions", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 2,
        needsInput: 1,
        rows: [
          { sid: "s1", title: "Old title", host: "mac", state: "working", since: 1_650 },
          { sid: "s2", title: "Blocked", host: "mac", state: "blocked", since: 1_660 },
        ],
        hosts: [{ name: "mac", online: true }],
        updatedAt: 1_700,
      },
    };
    const r = reduceFleetLiveActivity({
      observations: [
        { session: { sessionId: "s1", title: "New title" }, observed: obs(true, true) },
        { session: { sessionId: "s2", title: "Blocked" }, observed: obs(false, true) },
        { session: { sessionId: "s3", title: "Idle" }, observed: obs(false, false) },
      ],
      active,
      now: 1_710,
      hostName: "mac",
    });
    expect(r.nextActive?.contentState).toEqual({
      working: 1,
      needsInput: 1,
      rows: [
        { sid: "s2", title: "Blocked", host: "mac", state: "blocked", since: 1_660 },
        { sid: "s1", title: "New title", host: "mac", state: "working", since: 1_650 },
      ],
      hosts: [{ name: "mac", online: true }],
      updatedAt: 1_710,
    });
    expect(r.action?.event).toBe("update");
  });
});

describe("liveActivitiesEnabled", () => {
  test("is enabled only by LFG_LIVE_ACTIVITIES=1", () => {
    expect(liveActivitiesEnabled({} as NodeJS.ProcessEnv)).toBe(false);
    expect(liveActivitiesEnabled({ LFG_LIVE_ACTIVITIES: "true" } as NodeJS.ProcessEnv)).toBe(false);
    expect(liveActivitiesEnabled({ LFG_LIVE_ACTIVITIES: "1" } as NodeJS.ProcessEnv)).toBe(true);
  });
});

const cfg: ApnsConfig = { key: "x", keyId: "k", teamId: "t", topic: "dev.omg.lfg" };

describe("runPushTick (SC1/SC2 server-side)", () => {
  test("first sighting seeds without sending", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [{ token: "tok", env: "sandbox" }],
      cfg,
      send: async (_d, p) => {
        sent.push(p);
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };
    await runPushTick(prior, deps);
    expect(sent.length).toBe(0);
    expect(prior.get("s1")?.busy).toBe(true);
  });

  test("busy → idle on the second tick pushes 'finished' to each device", async () => {
    const sent: { token: string; p: ApnsPayload }[] = [];
    const prior = new Map<string, PriorState>();
    let state = obs(true, false);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => state,
      devices: async () => [
        { token: "a", env: "sandbox" },
        { token: "b", env: "production" },
      ],
      cfg,
      send: async (d, p) => {
        sent.push({ token: d.token, p });
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };
    await runPushTick(prior, deps); // seed (busy)
    state = obs(false, false); // turn finished
    await runPushTick(prior, deps);
    expect(sent.map((s) => s.token).sort()).toEqual(["a", "b"]);
    expect(sent[0].p.kind).toBe("finished");
  });

  test("busy → idle with a prompt pushes 'needs-input' carrying the question", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    let state = obs(true, false);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => state,
      devices: async () => [{ token: "a", env: "sandbox" }],
      cfg,
      send: async (_d, p) => {
        sent.push(p);
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };
    await runPushTick(prior, deps);
    state = obs(false, true, "Approve the plan?");
    await runPushTick(prior, deps);
    expect(sent.length).toBe(1);
    expect(sent[0].kind).toBe("needs-input");
    expect(sent[0].body).toBe("Approve the plan?");
  });

  test("transition payload carries background wake metadata when deps provide it", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    let state = obs(true, false);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => state,
      devices: async () => [{ token: "a", env: "sandbox" }],
      cfg,
      send: async (_d, p) => {
        sent.push(p);
        return { ok: true, status: 200 };
      },
      head: () => 123,
      hostId: () => "host-1",
      now: () => 1000,
    };
    await runPushTick(prior, deps);
    state = obs(false, false);
    await runPushTick(prior, deps);
    const body = JSON.parse(apnsBody(sent[0]));
    expect(body.aps["content-available"]).toBe(1);
    expect(body.hostId).toBe("host-1");
    expect(body.seq).toBe(123);
  });

  test("transition payload omits journal wake keys when deps do not provide them", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    let state = obs(true, false);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => state,
      devices: async () => [{ token: "a", env: "sandbox" }],
      cfg,
      send: async (_d, p) => {
        sent.push(p);
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };
    await runPushTick(prior, deps);
    state = obs(false, false);
    await runPushTick(prior, deps);
    const body = JSON.parse(apnsBody(sent[0]));
    expect(body.aps["content-available"]).toBe(1);
    expect("hostId" in body).toBe(false);
    expect("seq" in body).toBe(false);
  });

  test("a 410/BadDeviceToken response prunes the device", async () => {
    const pruned: string[] = [];
    const prior = new Map<string, PriorState>();
    let state = obs(true, false);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => state,
      devices: async () => [{ token: "dead", env: "sandbox" }],
      cfg,
      send: async () => ({ ok: false, status: 410, reason: "Unregistered" }),
      onDeadToken: (t) => {
        pruned.push(t);
      },
      now: () => 1000,
    };
    await runPushTick(prior, deps);
    state = obs(false, false);
    await runPushTick(prior, deps);
    expect(pruned).toEqual(["dead"]);
  });

  test("no devices → nothing observed, nothing sent (SC7)", async () => {
    let observed = 0;
    const prior = new Map<string, PriorState>();
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", tmuxTarget: "t" }],
      observe: async () => {
        observed++;
        return obs(false, false);
      },
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
    };
    await runPushTick(prior, deps);
    expect(observed).toBe(0);
  });

  test("Live Activity deps can start even when regular APNs devices are absent", async () => {
    const sent: { token: string; push: LiveActivityPush }[] = [];
    const prior = new Map<string, PriorState>();
    const active = new Map<string, LiveActivityActive>();
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      hostName: () => "mac",
      liveActivities: {
        active,
        pushToStartTokens: async () => [{ token: "start", env: "sandbox" }],
        fleetUpdateTokens: async () => [],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_700_000,
    };
    await runPushTick(prior, deps);
    expect(sent.map((s) => s.token)).toEqual(["start"]);
    expect(sent[0].push.body.aps.event).toBe("start");
    expect(active.has("fleet")).toBe(true);
  });
});
