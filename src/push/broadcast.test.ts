import { afterEach, describe, expect, test } from "bun:test";
import { generateKeyPairSync } from "node:crypto";
import {
  BROADCAST_EXPIRY_END_S,
  BROADCAST_EXPIRY_UPDATE_S,
  MESSAGE_STORAGE_POLICY,
  broadcastPriority,
  createBroadcastChannel,
  ensureBroadcastChannel,
  deleteBroadcastChannel,
  listBroadcastChannels,
  manageHost,
  managePort,
  sendBroadcastLiveActivity,
} from "./broadcast.ts";
import { buildEnd, buildUpdate } from "./liveactivity.ts";
import { _resetApnsJwtCache, type ApnsConfig, type ApnsHttpRequest, type ApnsResult } from "./apns.ts";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
const cfg: ApnsConfig = { key: pem, keyId: "ABC123", teamId: "TEAM456", topic: "dev.omg.lfg" };

afterEach(() => _resetApnsJwtCache());

function recorder(result: ApnsResult) {
  const seen: ApnsHttpRequest[] = [];
  const fn = async (req: ApnsHttpRequest) => {
    seen.push(req);
    return result;
  };
  return { seen, fn };
}

const contentState = {
  working: 1,
  needsInput: 0,
  rows: [{ sid: "s1", title: "Build", state: "working" as const, since: 1_600 }],
  more: 0,
  updatedAt: 1_701,
};

describe("channel management endpoints", () => {
  // Apple documents DIFFERENT hosts AND different ports per environment. Getting
  // either wrong fails in a way that looks like an auth problem, so both are pinned.
  test("management host and port differ by environment", () => {
    expect(manageHost("sandbox")).toBe("api-manage-broadcast.sandbox.push.apple.com");
    expect(managePort("sandbox")).toBe(2195);
    expect(manageHost("production")).toBe("api-manage-broadcast.push.apple.com");
    expect(managePort("production")).toBe(2196);
  });

  test("createBroadcastChannel posts the documented body and returns the id header", async () => {
    const r = recorder({
      ok: true,
      status: 201,
      headers: { "apns-channel-id": "dHN0LXNyY2gtY2hubA==" },
    });
    const id = await createBroadcastChannel(cfg, "sandbox", r.fn);
    expect(id).toBe("dHN0LXNyY2gtY2hubA==");
    const req = r.seen[0]!;
    expect(req.method).toBe("POST");
    expect(req.path).toBe("/1/apps/dev.omg.lfg/channels");
    expect(req.host).toBe("api-manage-broadcast.sandbox.push.apple.com");
    expect(req.port).toBe(2195);
    expect(JSON.parse(req.body!)).toEqual({
      "message-storage-policy": MESSAGE_STORAGE_POLICY,
      "push-type": "LiveActivity",
    });
  });

  // Success here is 201, not 200 — the generalized transport treats any 2xx as ok,
  // and this test is what pins that so a future tightening can't silently break it.
  test("createBroadcastChannel fails loudly when APNs rejects", async () => {
    const r = recorder({ ok: false, status: 403, reason: "InvalidProviderToken" });
    expect(createBroadcastChannel(cfg, "production", r.fn)).rejects.toThrow(/InvalidProviderToken/);
  });

  // A 201 with no id header is not a usable channel: starting an activity against
  // an empty channel id fails on device, so it must not reach the store.
  test("createBroadcastChannel rejects a success with no channel id", async () => {
    const r = recorder({ ok: true, status: 201, headers: {} });
    expect(createBroadcastChannel(cfg, "sandbox", r.fn)).rejects.toThrow(/channel id/i);
  });

  test("listBroadcastChannels reads the all-channels path", async () => {
    const r = recorder({ ok: true, status: 200, body: JSON.stringify({ channels: ["a", "b"] }) });
    expect(await listBroadcastChannels(cfg, "production", r.fn)).toEqual(["a", "b"]);
    expect(r.seen[0]!.method).toBe("GET");
    expect(r.seen[0]!.path).toBe("/1/apps/dev.omg.lfg/all-channels");
  });

  test("deleteBroadcastChannel sends the id as a header, not in the path", async () => {
    const r = recorder({ ok: true, status: 204 });
    await deleteBroadcastChannel(cfg, "sandbox", "Y2hhbg==", r.fn);
    expect(r.seen[0]!.method).toBe("DELETE");
    expect(r.seen[0]!.path).toBe("/1/apps/dev.omg.lfg/channels");
    expect(r.seen[0]!.headers?.["apns-channel-id"]).toBe("Y2hhbg==");
  });
});

describe("broadcast publishing", () => {
  test("an update publishes to /4/broadcasts with the channel header and no apns-topic", async () => {
    const r = recorder({ ok: true, status: 200 });
    await sendBroadcastLiveActivity(
      { env: "production", channelId: "Y2hhbg==" },
      buildUpdate(contentState),
      cfg,
      r.fn,
    );
    const req = r.seen[0]!;
    expect(req.method).toBe("POST");
    expect(req.path).toBe("/4/broadcasts/apps/dev.omg.lfg");
    expect(req.headers?.["apns-channel-id"]).toBe("Y2hhbg==");
    expect(req.headers?.["apns-push-type"]).toBe("liveactivity");
    // The bundle id lives in the PATH on this endpoint; apns-topic is not part of it.
    expect(req.headers?.["apns-topic"]).toBeUndefined();
    expect(JSON.parse(req.body!).aps.event).toBe("update");
  });

  // apns-expiration is REQUIRED on this endpoint, and a nonzero value is only
  // legal against a stored-message channel — which is the policy we create.
  test("every broadcast carries a nonzero apns-expiration", async () => {
    const r = recorder({ ok: true, status: 200 });
    const now = 1_000_000;
    await sendBroadcastLiveActivity(
      { env: "production", channelId: "c" },
      buildUpdate(contentState),
      cfg,
      r.fn,
      now,
    );
    expect(r.seen[0]!.headers?.["apns-expiration"]).toBe(now + BROADCAST_EXPIRY_UPDATE_S);
    expect(MESSAGE_STORAGE_POLICY).toBe(1);
  });

  // An `end` that arrives late is still useful — it dismisses a card that would
  // otherwise lie — so it is stored for the full window, unlike an update.
  test("an end is given the long expiry so a returning phone still dismisses", async () => {
    const r = recorder({ ok: true, status: 200 });
    const now = 1_000_000;
    await sendBroadcastLiveActivity(
      { env: "production", channelId: "c" },
      buildEnd(contentState, now),
      cfg,
      r.fn,
      now,
    );
    expect(r.seen[0]!.headers?.["apns-expiration"]).toBe(now + BROADCAST_EXPIRY_END_S);
    expect(BROADCAST_EXPIRY_END_S).toBeGreaterThan(BROADCAST_EXPIRY_UPDATE_S);
  });

  // Priority 10 counts against the system push budget; priority 5 does not.
  // Apple recommends a mix, so routine "still working" updates go at 5 and only
  // something a human has to act on — or a dismissal — spends budget at 10.
  test("priority spends budget only when it matters", () => {
    expect(broadcastPriority("update", { ...contentState, needsInput: 0 })).toBe(5);
    expect(broadcastPriority("update", { ...contentState, needsInput: 2 })).toBe(10);
    expect(broadcastPriority("end", { ...contentState, needsInput: 0 })).toBe(10);
  });

  test("a rejected broadcast reports the APNs reason", async () => {
    const r = recorder({ ok: false, status: 400, reason: "BadChannelId" });
    const res = await sendBroadcastLiveActivity(
      { env: "production", channelId: "c" },
      buildUpdate(contentState),
      cfg,
      r.fn,
    );
    expect(res.ok).toBe(false);
    expect(res.reason).toBe("BadChannelId");
  });
});

describe("ensureBroadcastChannel", () => {
  test("reuses a stored channel without calling APNs", async () => {
    let created = 0;
    const id = await ensureBroadcastChannel(cfg, "production", {
      get: async () => ({ channelId: "stored" }),
      save: async () => {},
      create: async () => {
        created++;
        return "fresh";
      },
    });
    expect(id).toBe("stored");
    expect(created).toBe(0);
  });

  test("creates and persists on first use", async () => {
    const saved: Array<[string, string]> = [];
    const id = await ensureBroadcastChannel(cfg, "sandbox", {
      get: async () => null,
      save: async (e, c) => {
        saved.push([e, c]);
      },
      create: async () => "fresh",
    });
    expect(id).toBe("fresh");
    expect(saved).toEqual([["sandbox", "fresh"]]);
  });

  // Broadcast capability is a developer-portal toggle, so until it is enabled
  // every create fails. That must degrade to "no channel yet", never to a throw
  // that takes the whole push tick down with it.
  test("a failing create returns null rather than throwing", async () => {
    const lines: string[] = [];
    const id = await ensureBroadcastChannel(cfg, "production", {
      get: async () => null,
      save: async () => {},
      create: async () => {
        throw new Error("channel create failed: status 403 InvalidProviderToken");
      },
      log: (l) => lines.push(l),
    });
    expect(id).toBeNull();
    expect(lines[0]).toContain("403");
  });
});
