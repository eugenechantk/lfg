import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  reduceTransition,
  reduceFleetLiveActivity,
  orderFleetRows,
  MAX_FLEET_ROWS,
  liveActivitiesEnabled,
  pushWatcherEnabled,
  CANONICAL_SERVE_PORT,
  buildPayload,
  currentFleetActivity,
  noteFleetActivityEnded,
  noteFleetActivityStarted,
  runPushTick,
  type LiveActivityActive,
  type PriorState,
  type SessionState,
  type TickDeps,
} from "./watcher.ts";
import { loadFleetActivityActive, saveFleetActivityActive } from "./fleet-active-store.ts";
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
  test("starts one activity when the first session becomes active", () => {
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) }],
      active: null,
      now: 1_700,
    });
    expect(r.action?.event).toBe("start");
    expect(r.nextActive?.startedAt).toBe(1_700);
    expect(r.action?.push.body.aps).toMatchObject({
      event: "start",
      "content-state": {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", state: "working", since: 1_700 }],
        more: 0,
        updatedAt: 1_700,
      },
      attributes: { fleetId: "fleet" },
      "attributes-type": "LFGFleetAttributes",
    });
  });

  test("does nothing when nothing is active and nothing is live", () => {
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }],
      active: null,
      now: 1_700,
    });
    expect(r.action).toBeNull();
    expect(r.nextActive).toBeNull();
  });

  test("a paused (status=blocked) session is not on the card even while busy", () => {
    const r = reduceFleetLiveActivity({
      observations: [{
        session: { sessionId: "s1", title: "Paused", status: "blocked" },
        observed: obs(true, false),
      }],
      active: null,
      now: 1_700,
    });
    expect(r.action).toBeNull();
    expect(r.nextActive).toBeNull();
  });

  test("a paused session that is asking something still counts as needs-input", () => {
    const r = reduceFleetLiveActivity({
      observations: [{
        session: { sessionId: "s1", title: "Paused, asking", status: "blocked" },
        observed: obs(false, true),
      }],
      active: null,
      now: 1_700,
    });
    expect(r.action?.push.body.aps["content-state"]).toMatchObject({
      working: 0,
      needsInput: 1,
      rows: [{ sid: "s1", state: "needsInput" }],
    });
  });

  test("a pending prompt outranks busy, matching the client's grouping", () => {
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, true) }],
      active: null,
      now: 1_700,
    });
    expect(r.action?.push.body.aps["content-state"]).toMatchObject({
      working: 0,
      needsInput: 1,
      rows: [{ sid: "s1", state: "needsInput" }],
    });
  });

  test("updates and preserves since while a session holds its state", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Old title", state: "working", since: 1_650 }],
        more: 0,
        updatedAt: 1_700,
      },
      since: { s1: { state: "working", at: 1_650 } },
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "New title" }, observed: obs(true, false) }],
      active,
      now: 1_710,
    });
    expect(r.action?.event).toBe("update");
    expect(r.nextActive?.contentState).toEqual({
      working: 1,
      needsInput: 0,
      rows: [{ sid: "s1", title: "New title", state: "working", since: 1_650 }],
      more: 0,
      updatedAt: 1_710,
    });
  });

  test("a state change restarts that session's timer", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      since: { s1: { state: "working", at: 1_650 } },
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, true) }],
      active,
      now: 1_710,
    });
    expect(r.nextActive?.contentState?.rows[0]).toEqual({
      sid: "s1", title: "Job", state: "needsInput", since: 1_710,
    });
  });

  test("sends nothing when only updatedAt would change", () => {
    const contentState = {
      working: 1,
      needsInput: 0,
      rows: [{ sid: "s1", title: "Job", state: "working" as const, since: 1_650 }],
      more: 0,
      updatedAt: 1_700,
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) }],
      active: { startedAt: 1_700, contentState, since: { s1: { state: "working", at: 1_650 } } },
      now: 9_999,
    });
    expect(r.action).toBeNull();
    expect(r.nextActive).not.toBeNull();
  });

  test("ends the activity when the last session goes idle", () => {
    const active: LiveActivityActive = {
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", state: "working", since: 1_700 }],
        more: 0,
        updatedAt: 1_700,
      },
      since: { s1: { state: "working", at: 1_700 } },
    };
    const r = reduceFleetLiveActivity({
      observations: [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }],
      active,
      now: 1_730,
    });
    expect(r.action?.event).toBe("end");
    expect(r.nextActive).toBeNull();
    expect(r.action?.push.body.aps["content-state"]).toMatchObject({
      working: 0, needsInput: 0, rows: [], more: 0,
    });
  });

  test("orders needs-input first, then oldest, and folds the rest into more", () => {
    expect(
      orderFleetRows([
        { sid: "w2", title: "Work 2", state: "working", since: 20 },
        { sid: "b2", title: "Block 2", state: "needsInput", since: 12 },
        { sid: "b1", title: "Block 1", state: "needsInput", since: 10 },
        { sid: "w1", title: "Work 1", state: "working", since: 5 },
      ]).map((r) => r.sid),
    ).toEqual(["b1", "b2", "w1", "w2"]);

    expect(MAX_FLEET_ROWS).toBe(3);
    const r = reduceFleetLiveActivity({
      observations: [
        { session: { sessionId: "w2", title: "Work 2" }, observed: obs(true, false) },
        { session: { sessionId: "b2", title: "Block 2" }, observed: obs(false, true) },
        { session: { sessionId: "b1", title: "Block 1" }, observed: obs(false, true) },
        { session: { sessionId: "w1", title: "Work 1" }, observed: obs(true, false) },
        { session: { sessionId: "b3", title: "Block 3" }, observed: obs(false, true) },
      ],
      active: null,
      now: 30,
    });
    const content = r.action!.push.body.aps["content-state"]!;
    // All five counted; only the three most urgent rendered.
    expect(content.working).toBe(2);
    expect(content.needsInput).toBe(3);
    expect(content.rows.map((row) => row.sid)).toEqual(["b1", "b2", "b3"]);
    expect(content.more).toBe(2);
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
    const active: { current: LiveActivityActive | null } = { current: null };
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
    expect(active.current?.contentState?.rows.map((row) => row.sid)).toEqual(["s1"]);
  });

  test("Live Activity updates go to every registered update token", async () => {
    const sent: { token: string; push: LiveActivityPush }[] = [];
    const prior = new Map<string, PriorState>();
    const active: { current: LiveActivityActive | null } = {
      current: {
        startedAt: 1_700,
        contentState: {
          working: 1,
          needsInput: 0,
          rows: [{ sid: "s1", title: "Old", state: "working", since: 1_700 }],
          more: 0,
          updatedAt: 1_700,
        },
        since: { s1: { state: "working", at: 1_700 } },
      },
    };
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
        activityUpdateTokens: async () => [
          { token: "u1", env: "sandbox" },
          { token: "u2", env: "production" },
        ],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_710_000,
    };
    await runPushTick(prior, deps);
    expect(sent.map((s) => s.token)).toEqual(["u1", "u2"]);
    expect(sent[0].push.body.aps.event).toBe("update");
  });

  test("many active sessions still produce exactly one activity", async () => {
    const sent: LiveActivityPush[] = [];
    const prior = new Map<string, PriorState>();
    const active: { current: LiveActivityActive | null } = { current: null };
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
        send: async (_d, push) => {
          sent.push(push);
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_700_000,
    };
    await runPushTick(prior, deps);
    // The retired per-session design capped at 5 and logged the rest as
    // dropped. One aggregate activity counts all six and renders three.
    expect(sent.length).toBe(1);
    const content = sent[0].body.aps["content-state"]!;
    expect(content.working).toBe(6);
    expect(content.rows.length).toBe(3);
    expect(content.more).toBe(3);
  });

});

/**
 * SC4 — the client owns the card's existence, the server owns its content.
 *
 * `FleetActivityController` ends the card when the APP's active count hits zero.
 * The watcher's count is derived separately and need not hit zero at the same
 * moment, so the server can be left addressing an activity the device already
 * dismissed. It then sends `update` forever, and because a dead Live Activity
 * token still answers 200, nothing else ever corrects it.
 * See `.claude/diagnosis-live-activity-background-updates.md`.
 */
describe("client-reported card end (SC4)", () => {
  // The stored title differs from the one `sessions()` returns, so there IS a
  // renderable change to push — otherwise `sameFleetContentState` short-circuits
  // the tick and both branches would send nothing for uninteresting reasons.
  const liveCard: LiveActivityActive = {
    startedAt: 1_700,
    contentState: {
      working: 1,
      needsInput: 0,
      rows: [{ sid: "s1", title: "Old", state: "working", since: 1_700 }],
      more: 0,
      updatedAt: 1_700,
    },
    since: { s1: { state: "working", at: 1_700 } },
  };

  const tickWith = async (active: { current: LiveActivityActive | null }) => {
    const sent: { token: string; push: LiveActivityPush }[] = [];
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      liveActivities: {
        active,
        pushToStartTokens: async () => [{ token: "start", env: "sandbox" }],
        activityUpdateTokens: async () => [{ token: "update", env: "sandbox" }],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_700_000,
    };
    await runPushTick(new Map<string, PriorState>(), deps);
    return sent;
  };

  test("while the server still believes a card is live it only ever sends update", async () => {
    // The broken behaviour, pinned: the same session, the same tick — the ONLY
    // difference downstream is whether `active.current` was cleared.
    const sent = await tickWith({ current: { ...liveCard } });
    expect(sent.map((s) => s.push.body.aps.event)).toEqual(["update"]);
    expect(sent.map((s) => s.token)).toEqual(["update"]);
  });

  test("once the card is reported ended the next tick sends push-to-start", async () => {
    // `start` is the only event that can put a card back on a SUSPENDED device;
    // an update into a dismissed activity is silently dropped.
    const sent = await tickWith({ current: null });
    expect(sent.map((s) => s.push.body.aps.event)).toEqual(["start"]);
    expect(sent.map((s) => s.token)).toEqual(["start"]);
  });

  test("noteFleetActivityEnded clears the persisted state", async () => {
    const dir = mkdtempSync(join(tmpdir(), "lfg-fleet-active-"));
    const statePath = join(dir, "fleet-activity-state.json");
    process.env.LFG_FLEET_ACTIVITY_STATE = statePath;
    try {
      await saveFleetActivityActive(liveCard);
      expect(await loadFleetActivityActive()).not.toBeNull();

      await noteFleetActivityEnded();

      // Cleared on disk too, so a server restart cannot resurrect the dead card.
      expect(await loadFleetActivityActive()).toBeNull();
    } finally {
      delete process.env.LFG_FLEET_ACTIVITY_STATE;
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

/**
 * The other half of SC4. Clearing `active.current` on an "ended" report is only
 * safe if something re-adopts the card the app creates for itself — otherwise the
 * next tick push-to-starts a SECOND card next to it.
 */
describe("client-reported card start", () => {
  // `noteFleetActivityEnded` unlinks the state file. Redirect it at a temp dir
  // for the whole block — without this the suite would delete the REAL
  // `~/.lfg/fleet-activity-state.json` out from under a running server.
  let stateDir: string;
  beforeEach(() => {
    stateDir = mkdtempSync(join(tmpdir(), "lfg-fleet-adopt-"));
    process.env.LFG_FLEET_ACTIVITY_STATE = join(stateDir, "fleet-activity-state.json");
  });
  afterEach(() => {
    delete process.env.LFG_FLEET_ACTIVITY_STATE;
    rmSync(stateDir, { recursive: true, force: true });
  });

  test("adopting a card stops the next tick from push-to-starting a duplicate", async () => {
    const sent: { token: string; push: LiveActivityPush }[] = [];
    await noteFleetActivityEnded(); // card gone, server forgot it
    noteFleetActivityStarted(() => 1_700_000); // app made its own, token registered

    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      liveActivities: {
        active: currentFleetActivity(),
        pushToStartTokens: async () => [{ token: "start", env: "sandbox" }],
        activityUpdateTokens: async () => [{ token: "update", env: "sandbox" }],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_700_000,
    };
    await runPushTick(new Map<string, PriorState>(), deps);

    // update, not start — and it goes to the token the client just registered.
    expect(sent.map((s) => s.push.body.aps.event)).toEqual(["update"]);
    expect(sent.map((s) => s.token)).toEqual(["update"]);
  });

  test("an adopted card carries no content, so the first tick pushes the truth", async () => {
    // A freshly created card renders whatever the app seeded it with. Adopting
    // with `contentState: undefined` makes `sameFleetContentState` false, so the
    // server refreshes it immediately instead of waiting for a change.
    await noteFleetActivityEnded();
    noteFleetActivityStarted(() => 1_700_000);
    expect(currentFleetActivity().current?.contentState).toBeUndefined();
    expect(currentFleetActivity().current?.startedAt).toBe(1_700);
  });

  test("adopting twice keeps the first card's baselines", async () => {
    await noteFleetActivityEnded();
    noteFleetActivityStarted(() => 1_700_000);
    noteFleetActivityStarted(() => 9_900_000);
    expect(currentFleetActivity().current?.startedAt).toBe(1_700);
  });
});

/**
 * SC5 — a scratch server must not push to real devices. Agents routinely start a
 * second `lfg serve` on a spare port; it reads the same `~/.lfg` token store, so
 * without this gate it pushes real Live Activity updates to a real phone with its
 * own independent `active.current`. One was caught doing exactly that.
 */
describe("pushWatcherEnabled (SC5)", () => {
  const env = (o: Record<string, string>) => o as unknown as NodeJS.ProcessEnv;

  test("the canonical port pushes; a scratch port does not", () => {
    expect(pushWatcherEnabled(CANONICAL_SERVE_PORT, env({}))).toBe(true);
    expect(pushWatcherEnabled(8767, env({}))).toBe(false);
    expect(pushWatcherEnabled(3000, env({}))).toBe(false);
  });

  test("LFG_PUSH_WATCHER=1 opts a deliberately-relocated primary back in", () => {
    expect(pushWatcherEnabled(9999, env({ LFG_PUSH_WATCHER: "1" }))).toBe(true);
  });

  test("LFG_PUSH_WATCHER=0 silences even the canonical port", () => {
    expect(pushWatcherEnabled(CANONICAL_SERVE_PORT, env({ LFG_PUSH_WATCHER: "0" }))).toBe(false);
  });

  test("only the exact strings count — anything else falls through to the port", () => {
    // Same convention as `liveActivitiesEnabled`: no truthiness guessing.
    expect(pushWatcherEnabled(8767, env({ LFG_PUSH_WATCHER: "true" }))).toBe(false);
    expect(pushWatcherEnabled(CANONICAL_SERVE_PORT, env({ LFG_PUSH_WATCHER: "yes" }))).toBe(true);
  });
});
