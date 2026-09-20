import { describe, expect, test } from "bun:test";
import { FleetSlicePublisher, SLICE_HEARTBEAT_MS, aggregatorConfig, type SliceRow } from "./fleet-slice";
import { collectFleetRows, runPushTick, type PriorState, type SessionState, type TickDeps } from "./watcher";

const cfg = { url: "https://agg.example", secret: "s3cret" };
const host = { id: () => "host-air", name: () => "Air" };
const row = (sid: string, state: SliceRow["state"] = "working", since = 100): SliceRow => ({ sid, title: sid, state, since });
const obs = (busy: boolean, promptPresent: boolean): SessionState => ({ busy, promptPresent });

function recorder(status = 200) {
  const calls: Array<{ url: string; method: string; auth: string; body: unknown }> = [];
  const state = { status };
  const fetchImpl = async (url: string, init: { method: string; headers: Record<string, string>; body?: string }) => {
    calls.push({ url, method: init.method, auth: init.headers.authorization ?? "", body: init.body ? JSON.parse(init.body) : undefined });
    return { ok: state.status >= 200 && state.status < 300, status: state.status, json: async () => ({ ok: true }) };
  };
  return { calls, state, fetchImpl };
}

describe("aggregatorConfig", () => {
  test("needs both url and secret; trims a trailing slash", () => {
    expect(aggregatorConfig({})).toBeNull();
    expect(aggregatorConfig({ LFG_FLEET_AGGREGATOR_URL: "https://x" })).toBeNull();
    expect(aggregatorConfig({ LFG_FLEET_AGGREGATOR_URL: "https://x/ ", LFG_FLEET_AGGREGATOR_SECRET: " k " })).toEqual({ url: "https://x", secret: "k" });
  });
});

describe("FleetSlicePublisher", () => {
  test("publishes this host's rows, authenticated, to its own slice", async () => {
    const r = recorder();
    const p = new FleetSlicePublisher(cfg, host, r.fetchImpl);
    expect(await p.publish([row("a")], 1_000)).toBe("sent");
    expect(r.calls).toEqual([{
      url: "https://agg.example/v1/hosts/host-air/slice",
      method: "PUT",
      auth: "Bearer s3cret",
      body: { hostName: "Air", rows: [row("a")] },
    }]);
  });

  test("an unchanged slice is not resent until the heartbeat is due", async () => {
    const r = recorder();
    const p = new FleetSlicePublisher(cfg, host, r.fetchImpl);
    await p.publish([row("a")], 1_000);
    expect(await p.publish([row("a")], 1_000 + SLICE_HEARTBEAT_MS - 1)).toBe("skipped");
    expect(await p.publish([row("a")], 1_000 + SLICE_HEARTBEAT_MS)).toBe("sent");
    expect(r.calls.length).toBe(2);
  });

  test("an EMPTY slice is published too — that is how a host says 'nothing here'", async () => {
    const r = recorder();
    const p = new FleetSlicePublisher(cfg, host, r.fetchImpl);
    await p.publish([row("a")], 1_000);
    expect(await p.publish([], 3_000)).toBe("sent");
    expect((r.calls[1]!.body as { rows: unknown[] }).rows).toEqual([]);
  });

  test("any visible change republishes at once; row order alone does not", async () => {
    const r = recorder();
    const p = new FleetSlicePublisher(cfg, host, r.fetchImpl);
    await p.publish([row("a"), row("b")], 1_000);
    expect(await p.publish([row("b"), row("a")], 3_000)).toBe("skipped");
    expect(await p.publish([row("a", "needsInput"), row("b")], 5_000)).toBe("sent");
  });

  test("a failed publish is retried on the next tick, not after a heartbeat", async () => {
    const r = recorder(503);
    const p = new FleetSlicePublisher(cfg, host, r.fetchImpl);
    expect(await p.publish([row("a")], 1_000)).toBe("failed");
    r.state.status = 200;
    expect(await p.publish([row("a")], 3_000)).toBe("sent");
  });
});

describe("collectFleetRows", () => {
  const session = (sid: string) => ({ session: { sessionId: sid, title: sid }, observed: obs(true, false) });

  test("returns EVERY active row (no three-row cap) and keeps each clock across calls", () => {
    const first = collectFleetRows([session("a"), session("b"), session("c"), session("d")], {}, 1_000);
    expect(first.rows.length).toBe(4);
    const again = collectFleetRows([session("a")], first.since, 2_000);
    expect(again.rows[0]!.since).toBe(1_000);
  });

  test("a state change restarts that row's clock", () => {
    const first = collectFleetRows([session("a")], {}, 1_000);
    const asks = collectFleetRows([{ session: { sessionId: "a", title: "a" }, observed: obs(true, true) }], first.since, 2_000);
    expect(asks.rows[0]).toMatchObject({ state: "needsInput", since: 2_000 });
  });
});

describe("runPushTick in aggregator mode", () => {
  test("publishes the slice and makes NO local Live Activity decision or send", async () => {
    const r = recorder();
    const localSends: string[] = [];
    const prior = new Map<string, PriorState>();
    const deps: TickDeps = {
      sessions: async () => [{ sessionId: "s1", title: "Job", tmuxTarget: "t" }],
      observe: async () => obs(true, false),
      devices: async () => [],
      cfg: { keyId: "k", teamId: "t", key: "x", topic: "com.example" } as never,
      send: async () => ({ ok: true, status: 200 }),
      now: () => 50_000,
      slice: new FleetSlicePublisher(cfg, host, r.fetchImpl),
      // Present but must be ignored: an aggregator-mode host owns no card.
      liveActivities: {
        active: { current: null },
        pushToStartTokens: async () => [{ token: "aa", env: "production" }],
        channels: async () => [{ env: "production", channelId: "c" }],
        send: async () => { localSends.push("token"); return { ok: true, status: 200 }; },
        sendBroadcast: async () => { localSends.push("broadcast"); return { ok: true, status: 200 }; },
      } as never,
    };
    await runPushTick(prior, deps);
    expect(localSends).toEqual([]);
    expect(r.calls.length).toBe(1);
    expect(r.calls[0]!.body).toMatchObject({ rows: [{ sid: "s1", state: "working", since: 50 }] });
  });
});
