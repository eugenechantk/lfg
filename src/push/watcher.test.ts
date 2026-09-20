import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  reduceTransition,
  reduceFleetLiveActivity,
  orderFleetRows,
  MAX_FLEET_ROWS,
  FLEET_END_DEBOUNCE_S,
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
import type { LiveActivityContentState, LiveActivityPush } from "./liveactivity.ts";

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

  /**
   * The end is DEBOUNCED, not immediate. The delivery log (08-08 → 08-23)
   * recorded 202 end→start transitions, 82 of them under 30s: every idle blip
   * dismissed the card and bet its resurrection on push-to-start → background
   * app relaunch → update-token re-upload, which is the path that fails. During
   * the hold the card gets one truthful zeroed update instead.
   * See `.claude/feature/live-activity-delivery-reliability.md`.
   */
  describe("ending the activity when the fleet empties (with an explicit hold)", () => {
    const HOLD = 60;
    const active = (): LiveActivityActive => ({
      startedAt: 1_700,
      contentState: {
        working: 1,
        needsInput: 0,
        rows: [{ sid: "s1", title: "Job", state: "working", since: 1_700 }],
        more: 0,
        updatedAt: 1_700,
      },
      since: { s1: { state: "working", at: 1_700 } },
    });
    const idle = [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }];
    const busy = [{ session: { sessionId: "s1", title: "Job" }, observed: obs(true, false) }];

    test("first empty tick sends a zeroed update and starts the hold, not an end", () => {
      const r = reduceFleetLiveActivity({ observations: idle, active: active(), now: 1_730, endHoldS: HOLD });
      expect(r.action?.event).toBe("update");
      expect(r.action?.push.body.aps["content-state"]).toMatchObject({
        working: 0, needsInput: 0, rows: [], more: 0,
      });
      expect(r.nextActive?.zeroSince).toBe(1_730);
    });

    test("staying empty within the hold sends nothing and keeps the hold's start", () => {
      const first = reduceFleetLiveActivity({ observations: idle, active: active(), now: 1_730, endHoldS: HOLD });
      const again = reduceFleetLiveActivity({
        observations: idle,
        active: first.nextActive,
        now: 1_730 + 30, endHoldS: HOLD,
      });
      expect(again.action).toBeNull();
      expect(again.nextActive?.zeroSince).toBe(1_730);
    });

    test("ends once the fleet has been empty for the full debounce window", () => {
      const first = reduceFleetLiveActivity({ observations: idle, active: active(), now: 1_730, endHoldS: HOLD });
      const later = 1_730 + HOLD;
      const r = reduceFleetLiveActivity({ observations: idle, active: first.nextActive, now: later, endHoldS: HOLD });
      expect(r.action?.event).toBe("end");
      expect(r.nextActive).toBeNull();
      expect(r.action?.push.body.aps["dismissal-date"]).toBe(later);
    });

    test("activity reappearing within the hold cancels the end with no start churn", () => {
      const first = reduceFleetLiveActivity({ observations: idle, active: active(), now: 1_730, endHoldS: HOLD });
      const back = reduceFleetLiveActivity({
        observations: busy,
        active: first.nextActive,
        now: 1_730 + 20, endHoldS: HOLD,
      });
      expect(back.action?.event).toBe("update"); // NOT end, NOT start
      expect(back.nextActive?.zeroSince).toBeUndefined();
      // A later genuine empty stretch starts a FRESH hold from its own first tick.
      const emptyAgain = reduceFleetLiveActivity({
        observations: idle,
        active: back.nextActive,
        now: 1_730 + 40, endHoldS: HOLD,
      });
      expect(emptyAgain.action?.event).toBe("update");
      expect(emptyAgain.nextActive?.zeroSince).toBe(1_730 + 40);
    });

    test("an adopted card (no contentState) with an empty fleet is zero-updated then held", () => {
      // `noteFleetActivityStarted` adopts with no contentState. Before the
      // debounce this was the app-vs-server tug of war: the app creates a card,
      // registers a token, and the server ended it within a tick — captured
      // live at 2026-08-23T02:00Z as an end every ~30s, forever.
      const adopted: LiveActivityActive = { startedAt: 1_700 };
      const r = reduceFleetLiveActivity({ observations: idle, active: adopted, now: 1_730, endHoldS: HOLD });
      expect(r.action?.event).toBe("update");
      expect(r.nextActive?.zeroSince).toBe(1_730);
    });
  });

  describe("ending the activity when the fleet empties (default: immediately)", () => {
    const active = (): LiveActivityActive => ({
      startedAt: 1_700,
      contentState: {
        working: 1, needsInput: 0,
        rows: [{ sid: "s1", title: "Job", state: "working", since: 1_700 }],
        more: 0, updatedAt: 1_700,
      },
      since: { s1: { state: "working", at: 1_700 } },
    });
    const idle = [{ session: { sessionId: "s1", title: "Job" }, observed: obs(false, false) }];

    test("the default hold is zero", () => {
      expect(FLEET_END_DEBOUNCE_S).toBe(0);
    });

    test("the first empty tick ends the card at once — no zeroed update, dismissed now", () => {
      const r = reduceFleetLiveActivity({ observations: idle, active: active(), now: 1_730 });
      expect(r.action?.event).toBe("end");
      expect(r.action?.push.body.aps["dismissal-date"]).toBe(1_730);
      expect(r.nextActive).toBeNull();
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

  test("an active child keeps an idle parent busy until the child finishes", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    let runningChildAgentCount = 1;
    const deps: TickDeps = {
      sessions: async () => [{
        sessionId: "s1",
        title: "Parent",
        tmuxTarget: "t",
        runningChildAgentCount,
      }],
      observe: async () => obs(false, false),
      devices: async () => [{ token: "a", env: "sandbox" }],
      cfg,
      send: async (_d, payload) => {
        sent.push(payload);
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };

    await runPushTick(prior, deps);
    expect(prior.get("s1")?.busy).toBe(true);
    await runPushTick(prior, deps);
    expect(sent).toHaveLength(0);

    runningChildAgentCount = 0;
    await runPushTick(prior, deps);
    expect(sent.map((payload) => payload.kind)).toEqual(["finished"]);
  });

  test("a background process never makes an idle parent busy (bug 010)", async () => {
    // A dev server started with run_in_background lives for hours. Folding it
    // into busy pinned idle sessions "Working" and — because reduceTransition
    // returns early while busy — suppressed every later finished/needs-input
    // push. Background work is a badge, not a turn.
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    let runningBackgroundProcessCount = 1;
    const deps: TickDeps = {
      sessions: async () => [{
        sessionId: "s1",
        title: "Parent",
        tmuxTarget: "t",
        runningBackgroundProcessCount,
      }],
      observe: async () => obs(false, false),
      devices: async () => [{ token: "a", env: "sandbox" }],
      cfg,
      send: async (_d, payload) => {
        sent.push(payload);
        return { ok: true, status: 200 };
      },
      now: () => 1000,
    };

    await runPushTick(prior, deps);
    expect(prior.get("s1")?.busy).toBe(false);
    runningBackgroundProcessCount = 0;
    await runPushTick(prior, deps);
    expect(sent).toHaveLength(0);
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
        channels: async () => [{ env: "sandbox" as const, channelId: "chan-sand" }],
        sendBroadcast: async () => ({ ok: true, status: 200 }),
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

  // Updates no longer fan out over per-card tokens: one publish per channel
  // reaches every card subscribed to it, awake or not.
  test("Live Activity updates publish once per broadcast channel", async () => {
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
        channels: async () => [
          { env: "sandbox" as const, channelId: "chan-sand" },
          { env: "production" as const, channelId: "chan-prod" },
        ],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
        sendBroadcast: async (channel, push) => {
          sent.push({ token: channel.channelId, push });
          return { ok: true, status: 200 };
        },
      },
      now: () => 1_710_000,
    };
    await runPushTick(prior, deps);
    expect(sent.map((s) => s.token)).toEqual(["chan-sand", "chan-prod"]);
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
        channels: async () => [{ env: "sandbox" as const, channelId: "chan-sand" }],
        sendBroadcast: async () => ({ ok: true, status: 200 }),
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
 * Partial delivery must not advance state. Update/end fan out to one token per
 * APNs env, and one of the two is routinely a corpse that answers 200 — so
 * "at least one accepted" was routinely "only the corpse accepted", which
 * stranded the real device's card as a zombie (captured live: 2026-08-23
 * 06:06:48Z, end → production status 0, sandbox corpse 200, state advanced).
 * Update and end now require EVERY targeted token to accept; start keeps
 * "any accepted" because re-blasting starts risks duplicate cards.
 */
describe("partial Live Activity delivery does not advance state", () => {
  const liveCard = (): LiveActivityActive => ({
    startedAt: 1_700,
    contentState: {
      working: 1,
      needsInput: 0,
      rows: [{ sid: "s1", title: "Old", state: "working", since: 1_700 }],
      more: 0,
      updatedAt: 1_700,
    },
    since: { s1: { state: "working", at: 1_700 } },
  });

  type SendResult = { ok: boolean; status: number; reason?: string };
  const harness = (args: {
    active: { current: LiveActivityActive | null };
    sessionsBusy: boolean;
    results: Record<string, SendResult[]>; // per-token queue of results
    now: number;
  }) => {
    const sent: { token: string; event: string }[] = [];
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(args.sessionsBusy, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      liveActivities: {
        active: args.active,
        pushToStartTokens: async () => [{ token: "start", env: "sandbox" as const }],
        channels: async () => [
          { env: "production" as const, channelId: "u-prod" },
          { env: "sandbox" as const, channelId: "u-sand" },
        ],
        send: async (d, push) => {
          sent.push({ token: d.token, event: push.body.aps.event });
          const queue = args.results[d.token];
          return queue?.length ? queue.shift()! : { ok: true, status: 200 };
        },
        sendBroadcast: async (channel, push) => {
          sent.push({ token: channel.channelId, event: push.body.aps.event });
          const queue = args.results[channel.channelId];
          return queue?.length ? queue.shift()! : { ok: true, status: 200 };
        },
      },
      now: () => args.now,
    };
    return { sent, deps };
  };
  const fail0: SendResult = {
    ok: false,
    status: 0,
    reason: "Client network socket disconnected before secure TLS connection was established",
  };

  test("an update with one transport failure keeps the old baseline and re-sends next tick", async () => {
    const active = { current: liveCard() };
    const h = harness({ active, sessionsBusy: true, results: { "u-prod": [fail0] }, now: 1_710_000 });
    await runPushTick(new Map(), h.deps);
    expect(h.sent.map((s) => s.event)).toEqual(["update", "update"]);
    // Baseline NOT advanced: the stored contentState still has the old title…
    expect(active.current?.contentState?.rows[0]?.title).toBe("Old");
    // …so the next tick re-sends the same update to both tokens.
    const h2 = harness({ active, sessionsBusy: true, results: {}, now: 1_710_002 });
    await runPushTick(new Map(), h2.deps);
    expect(h2.sent.map((s) => s.event)).toEqual(["update", "update"]);
    expect(active.current?.contentState?.rows[0]?.title).toBe("Job");
  });

  test("an end with one transport failure keeps the card live and retries until all accept", async () => {
    // zeroSince already older than the debounce window → the reducer decides end.
    const expired: LiveActivityActive = { ...liveCard(), zeroSince: 1_000 };
    const active: { current: LiveActivityActive | null } = { current: expired };
    const now = (1_000 + FLEET_END_DEBOUNCE_S + 5) * 1000;
    const h = harness({ active, sessionsBusy: false, results: { "u-prod": [fail0] }, now });
    await runPushTick(new Map(), h.deps);
    expect(h.sent.map((s) => s.event)).toEqual(["end", "end"]);
    expect(active.current).not.toBeNull(); // NOT advanced — the real card would be a zombie

    const h2 = harness({ active, sessionsBusy: false, results: {}, now: now + 2000 });
    await runPushTick(new Map(), h2.deps);
    expect(h2.sent.map((s) => s.event)).toEqual(["end", "end"]);
    expect(active.current).toBeNull(); // all accepted → done
  });

  test("a permanently rejected channel is pruned instead of livelocking", async () => {
    // All-accepted advancement re-sends until every target accepts, so a channel
    // APNs will never honour again would make the watcher re-send the same update
    // every 2s forever. This is the channel-era successor to the dead-token prune:
    // unlike a dead Live Activity TOKEN — which answers 200 and so was invisible —
    // an unknown channel is rejected honestly, so one signal is enough to act on.
    const active = { current: liveCard() };
    const dropped: string[] = [];
    const h = harness({
      active,
      sessionsBusy: true,
      results: { "u-prod": [{ ok: false, status: 400, reason: "BadChannelId" }] },
      now: 1_710_000,
    });
    h.deps.liveActivities!.onInvalidChannel = (env) => {
      dropped.push(env);
    };
    await runPushTick(new Map(), h.deps);
    expect(dropped).toEqual(["production"]);
    // Not advanced this tick; next tick recreates the channel and can go green.
    expect(active.current?.contentState?.rows[0]?.title).toBe("Old");
  });

  test("a start still advances on any acceptance (re-blasting risks duplicate cards)", async () => {
    const active: { current: LiveActivityActive | null } = { current: null };
    const sent: { token: string; event: string }[] = [];
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg,
      send: async () => ({ ok: true, status: 200 }),
      liveActivities: {
        active,
        pushToStartTokens: async () => [
          { token: "p1", env: "production" as const },
          { token: "p2", env: "sandbox" as const },
        ],
        channels: async () => [{ env: "sandbox" as const, channelId: "chan-sand" }],
        sendBroadcast: async () => ({ ok: true, status: 200 }),
        send: async (d, push) => {
          sent.push({ token: d.token, event: push.body.aps.event });
          return d.token === "p1" ? fail0 : { ok: true, status: 200 };
        },
      },
      now: () => 1_700_000,
    };
    await runPushTick(new Map(), deps);
    expect(sent.map((s) => s.event)).toEqual(["start", "start"]);
    expect(active.current).not.toBeNull();
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
        channels: async () => [{ env: "sandbox" as const, channelId: "update" }],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
        sendBroadcast: async (channel, push) => {
          sent.push({ token: channel.channelId, push });
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
        channels: async () => [{ env: "sandbox" as const, channelId: "update" }],
        send: async (d, push) => {
          sent.push({ token: d.token, push });
          return { ok: true, status: 200 };
        },
        sendBroadcast: async (channel, push) => {
          sent.push({ token: channel.channelId, push });
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

// A session appearing TWICE in one tick — two live processes each holding an
// authoritative pidfile for the same sessionId (see sessions-session-owner.test.ts).
// `prior` is keyed by sessionId, so the two rows overwrite each other's memory
// every tick and their differing observations read as a genuine transition. On
// the real host this notified "🙋 reelly" every ~12s for a session that was not
// asking anything: one pane sat on an AskUserQuestion, the other idle at the
// composer.
describe("duplicate sessionId in one tick (phantom-notification storm)", () => {
  const dupDeps = (sent: ApnsPayload[], rows: Array<{ id: string; state: SessionState }>): TickDeps => ({
    sessions: async () => rows.map((r, i) => ({ sessionId: r.id, title: "reelly", tmuxTarget: `pane${i}` })),
    observe: async (s) => rows.find((r, i) => `pane${i}` === (s as { tmuxTarget?: string }).tmuxTarget)!.state,
    devices: async () => [{ token: "tok", env: "sandbox" }],
    cfg,
    send: async (_d, p) => {
      sent.push(p);
      return { ok: true, status: 200 };
    },
    now: () => 1000,
  });

  // The two panes verbatim: pid 36372 on an AskUserQuestion, pid 18071 idle.
  const collidingRows = () => [
    { id: "d1a3496d", state: obs(false, true, "Pick one") },
    { id: "d1a3496d", state: obs(false, false) },
  ];

  test("never sends, however many ticks run", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    const deps = dupDeps(sent, collidingRows());
    for (let i = 0; i < 10; i++) await runPushTick(prior, deps);
    expect(sent).toEqual([]);
  });

  test("the first row wins the tick, so the survivor's own transitions still fire", async () => {
    const sent: ApnsPayload[] = [];
    const prior = new Map<string, PriorState>();
    const rows = [
      { id: "d1a3496d", state: obs(true, false) }, // working
      { id: "d1a3496d", state: obs(false, true, "Pick one") }, // the ignored twin
    ];
    const deps = dupDeps(sent, rows);
    await runPushTick(prior, deps); // seed from row 0
    expect(prior.get("d1a3496d")?.busy).toBe(true);
    rows[0]!.state = obs(false, false); // row 0 genuinely finishes
    await runPushTick(prior, deps);
    expect(sent.map((p) => p.kind)).toEqual(["finished"]);
  });

  test("the fleet card renders one row, not two conflicting ones", () => {
    const d = reduceFleetLiveActivity({
      observations: [
        { session: { sessionId: "d1a3496d", title: "reelly" }, observed: obs(false, true) },
        { session: { sessionId: "d1a3496d", title: "reelly" }, observed: obs(true, false) },
      ],
      active: null,
      now: 100,
    });
    const content = d.action!.push.body.aps["content-state"]!;
    expect(content.rows).toHaveLength(1);
    expect(content.needsInput).toBe(1);
    expect(content.working).toBe(0);
  });
});

// A question that appears while the session is still busy — AskUserQuestion with
// hooks installed (the turn stays in flight until answered) and a phone sign-in
// request (the agent is blocked in its waiting command). Journal evidence: every
// recent question was answered before `busy` dropped, so gating on idle meant no
// needs-input push at all.
describe("reduceTransition — prompt while busy", () => {
  test("a prompt appearing while busy emits 'needs-input' at once", () => {
    const r = reduceTransition(seed(true, false), obs(true, true, "Sign in to portal.example.com on your iPhone"), 1000);
    expect(r.event).toBe("needs-input");
    expect(r.state).toEqual({ busy: true, promptPresent: true, lastNotifiedAt: 1000 });
  });

  test("busy → idle with a prompt that was already announced stays silent", () => {
    const a = reduceTransition(seed(true, false), obs(true, true, "Q?"), 1000);
    expect(a.event).toBe("needs-input");
    const b = reduceTransition(a.state, obs(false, true, "Q?"), 60_000);
    expect(b.event).toBeNull();
  });

  test("a prompt still present while busy does not re-fire on later ticks", () => {
    const a = reduceTransition(seed(true, false), obs(true, true, "Q?"), 1000);
    const b = reduceTransition(a.state, obs(true, true, "Q?"), 60_000);
    expect(b.event).toBeNull();
  });

  test("the prompt retracting while busy (sign-in done / cancelled) emits nothing", () => {
    const a = reduceTransition(seed(true, false), obs(true, true, "Q?"), 1000);
    const b = reduceTransition(a.state, obs(true, false), 60_000);
    expect(b.event).toBeNull();
    expect(b.state.promptPresent).toBe(false);
  });

  test("busy prompt push is deduped against a push moments earlier, then retried", () => {
    const a = reduceTransition(seed(true, false), obs(false, false), 1000);
    expect(a.event).toBe("finished");
    const b = reduceTransition(a.state, obs(true, true, "Q?"), 1000 + 3000);
    expect(b.event).toBeNull();
    // The auditor's edge: the swallowed prompt must not be buried. Still busy,
    // still asking, window elapsed → it fires; a later busy→idle stays silent.
    const c = reduceTransition(b.state, obs(true, true, "Q?"), 1000 + 11_000);
    expect(c.event).toBe("needs-input");
    const d = reduceTransition(c.state, obs(false, true, "Q?"), 1000 + 60_000);
    expect(d.event).toBeNull();
  });
});

describe("runPushTick — phone sign-in request", () => {
  test("a sign-in prompt appearing mid-turn pushes 'needs-input' carrying its question", async () => {
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
    // The agent is still busy (blocked in `browser-sign-in request`) when the
    // request lands.
    state = obs(true, true, "Sign in to portal.example.com on your iPhone");
    await runPushTick(prior, deps);
    expect(sent.length).toBe(1);
    expect(sent[0].kind).toBe("needs-input");
    expect(sent[0].body).toBe("Sign in to portal.example.com on your iPhone");
    // Done on the phone: request leaves `waiting`, prompt retracts, agent resumes.
    state = obs(true, false);
    await runPushTick(prior, deps);
    expect(sent.length).toBe(1);
  });
});
