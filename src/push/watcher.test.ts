import { test, expect, describe } from "bun:test";
import {
  reduceTransition,
  reduceSessionLiveActivities,
  orderSessionLiveActivityCandidates,
  MAX_CONCURRENT_LIVE_ACTIVITIES,
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

describe("reduceSessionLiveActivities", () => {
  test("starts when a session first becomes active", () => {
    const r = reduceSessionLiveActivities({
      observations: [{ session: { sessionId: "s1", title: "Job", cwd: "/Users/eugene/lfg" }, observed: obs(true, false) }],
      active: new Map(),
      now: 1_700,
      hostName: "mac",
    });
    expect(r.decisions.length).toBe(1);
    expect(r.decisions[0].action?.event).toBe("start");
    expect(r.decisions[0].nextActive?.startedAt).toBe(1_700);
    expect(r.decisions[0].action?.push.body.aps).toMatchObject({
      event: "start",
      "content-state": {
        state: "working",
        title: "Job",
        dir: "lfg",
        host: "mac",
        since: 1_700,
        updatedAt: 1_700,
      },
      attributes: { sessionId: "s1" },
      "attributes-type": "LFGSessionAttributes",
    });
  });

  test("does not start for an idle session with no transition", () => {
    const r = reduceSessionLiveActivities({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }],
      active: new Map(),
      now: 1_700,
      hostName: "mac",
    });
    expect(r.decisions).toEqual([]);
  });

  test("updates a selected active session and preserves since for matching state", () => {
    const active = new Map<string, LiveActivityActive>([
      ["s1", {
        sessionId: "s1",
        startedAt: 1_700,
        contentState: {
          state: "working",
          title: "Old title",
          dir: "lfg",
          host: "mac",
          since: 1_650,
          updatedAt: 1_700,
        },
      }],
    ]);
    const r = reduceSessionLiveActivities({
      observations: [{ session: { sessionId: "s1", title: "New title", cwd: "/tmp/lfg" }, observed: obs(true, true) }],
      active,
      now: 1_710,
      hostName: "mac",
    });
    expect(r.decisions[0].action?.event).toBe("update");
    expect(r.decisions[0].nextActive?.contentState).toEqual({
      state: "working",
      title: "New title",
      dir: "lfg",
      host: "mac",
      since: 1_650,
      updatedAt: 1_710,
    });
  });

  test("ends an active session that transitions to finished with an eight-minute dismissal date", () => {
    const active = new Map<string, LiveActivityActive>([
      ["s1", {
        sessionId: "s1",
        startedAt: 1_700,
        contentState: {
          state: "working",
          title: "Job",
          dir: "lfg",
          host: "mac",
          since: 1_700,
          updatedAt: 1_700,
        },
      }],
    ]);
    const r = reduceSessionLiveActivities({
      observations: [{ session: { sessionId: "s1", title: "Job", cwd: "/tmp/lfg" }, observed: obs(false, false), previous: seed(true, false) }],
      active,
      now: 1_730,
      hostName: "mac",
    });
    expect(r.decisions[0].action?.event).toBe("end");
    expect(r.decisions[0].nextActive).toBeNull();
    expect(r.decisions[0].action?.push.body.aps["content-state"]).toEqual({
      state: "finished",
      title: "Job",
      dir: "lfg",
      host: "mac",
      since: 1_730,
      updatedAt: 1_730,
    });
    expect(r.decisions[0].action?.push.body.aps["dismissal-date"]).toBe(2_210);
  });

  test("orders blocked first, then working, then finished, and caps at the ActivityKit maximum", () => {
    expect(
      orderSessionLiveActivityCandidates([
        { sessionId: "w2", contentState: { state: "working", title: "Work 2", dir: "lfg", host: "mac", since: 20, updatedAt: 30 } },
        { sessionId: "f1", contentState: { state: "finished", title: "Done", dir: "lfg", host: "mac", since: 1, updatedAt: 30 } },
        { sessionId: "b2", contentState: { state: "blocked", title: "Block 2", dir: "lfg", host: "mac", since: 12, updatedAt: 30 } },
        { sessionId: "b1", contentState: { state: "blocked", title: "Block 1", dir: "lfg", host: "mac", since: 10, updatedAt: 30 } },
        { sessionId: "w1", contentState: { state: "working", title: "Work 1", dir: "lfg", host: "mac", since: 5, updatedAt: 30 } },
      ]).map((c) => c.sessionId),
    ).toEqual(["b1", "b2", "w1", "w2", "f1"]);

    // Six candidates against a ceiling of five: the lowest-priority one (the
    // finished session) is the one that must be dropped.
    expect(MAX_CONCURRENT_LIVE_ACTIVITIES).toBe(5);
    const r = reduceSessionLiveActivities({
      observations: [
        { session: { sessionId: "w2", title: "Work 2" }, observed: obs(true, false) },
        { session: { sessionId: "f1", title: "Done" }, observed: obs(false, false), previous: seed(true, false) },
        { session: { sessionId: "b2", title: "Block 2" }, observed: obs(false, true) },
        { session: { sessionId: "b1", title: "Block 1" }, observed: obs(false, true) },
        { session: { sessionId: "w1", title: "Work 1" }, observed: obs(true, false) },
        { session: { sessionId: "b3", title: "Block 3" }, observed: obs(false, true) },
      ],
      active: new Map(),
      now: 30,
      hostName: "mac",
    });
    expect(r.decisions.map((d) => d.sessionId)).toEqual(["b1", "b2", "b3", "w1", "w2"]);
    expect(r.dropped).toEqual(["f1"]);
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
        activityUpdateTokens: async () => [],
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
    expect(active.has("s1")).toBe(true);
  });

  test("Live Activity updates are sent only to the matching session update token", async () => {
    const sent: { token: string; push: LiveActivityPush }[] = [];
    const lookedUp: string[] = [];
    const prior = new Map<string, PriorState>();
    const active = new Map<string, LiveActivityActive>([
      ["s1", {
        sessionId: "s1",
        startedAt: 1_700,
        contentState: {
          state: "working",
          title: "Old",
          dir: "",
          host: "mac",
          since: 1_700,
          updatedAt: 1_700,
        },
      }],
    ]);
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "New", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      hostName: () => "mac",
      liveActivities: {
        active,
        pushToStartTokens: async () => [],
        activityUpdateTokens: async (sessionId) => {
          lookedUp.push(sessionId);
          return [{ token: "u1", env: "sandbox" }];
        },
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_710_000,
    };
    await runPushTick(prior, deps);
    expect(lookedUp).toEqual(["s1"]);
    expect(sent.map((s) => s.token)).toEqual(["u1"]);
    expect(sent[0].push.body.aps.event).toBe("update");
  });

  test("Live Activity cap logs dropped sessions", async () => {
    const logs: string[] = [];
    const prior = new Map<string, PriorState>();
    const active = new Map<string, LiveActivityActive>();
    const deps: TickDeps = {
      sessions: async () => [
        { sessionId: "s1", title: "One", tmuxTarget: "t" },
        { sessionId: "s2", title: "Two", tmuxTarget: "t" },
        { sessionId: "s3", title: "Three", tmuxTarget: "t" },
        { sessionId: "s4", title: "Four", tmuxTarget: "t" },
        { sessionId: "s5", title: "Five", tmuxTarget: "t" },
        { sessionId: "s6", title: "Six", tmuxTarget: "t" },
      ],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      hostName: () => "mac",
      liveActivities: {
        active,
        pushToStartTokens: async () => [{ token: "start", env: "sandbox" }],
        activityUpdateTokens: async () => [],
        send: async () => ({ ok: true, status: 200 }),
      },
      now: () => 1_700_000,
      log: (line) => logs.push(line),
    };
    await runPushTick(prior, deps);
    expect(logs).toContain("[liveactivity] cap dropped s6");
  });
});
