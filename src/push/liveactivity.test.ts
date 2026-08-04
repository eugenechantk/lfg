import { afterEach, describe, expect, test } from "bun:test";
import { generateKeyPairSync } from "node:crypto";
import {
  DEFAULT_APNS_TOPIC,
  LIVE_ACTIVITY_ATTRIBUTES_TYPE,
  buildEnd,
  buildStart,
  buildUpdate,
  sendLiveActivity,
} from "./liveactivity.ts";
import { _resetApnsJwtCache, type ApnsConfig, type ApnsTransport } from "./apns.ts";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
const cfg: ApnsConfig = { key: pem, keyId: "ABC123", teamId: "TEAM456", topic: "dev.omg.lfg" };

afterEach(() => _resetApnsJwtCache());

describe("Live Activity payload builders", () => {
  const contentState = {
    working: 2,
    needsInput: 1,
    rows: [
      { sid: "s2", title: "Approve deploy", state: "needsInput" as const, since: 1_690 },
      { sid: "s1", title: "Build", state: "working" as const, since: 1_600 },
    ],
    more: 1,
    updatedAt: 1_701,
  };

  test("buildStart produces the pinned liveactivity header/body shape", () => {
    const push = buildStart({ contentState }, LIVE_ACTIVITY_ATTRIBUTES_TYPE);
    expect(push).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_701,
          event: "start",
          "content-state": contentState,
          "attributes-type": "LFGFleetAttributes",
          attributes: { fleetId: "fleet" },
          alert: { title: "lfg", body: "LFG sessions are active." },
        },
      },
    });
  });

  test("content-state is normalised to exactly the wire shape", () => {
    const push = buildUpdate({
      ...contentState,
      rows: [{ sid: "s1", title: "Build", state: "working", since: 1_600, host: "mac" } as never],
      // A stray field from an older caller must not reach the wire.
      hosts: [{ name: "mac", online: true }],
    } as never);

    expect(push.body.aps["content-state"]).toEqual({
      working: 2,
      needsInput: 1,
      rows: [{ sid: "s1", title: "Build", state: "working", since: 1_600 }],
      more: 1,
      updatedAt: 1_701,
    });
  });

  test("buildUpdate produces the pinned update shape", () => {
    expect(buildUpdate(contentState)).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_701,
          event: "update",
          "content-state": contentState,
        },
      },
    });
  });

  test("buildEnd produces the pinned end shape with optional dismissal date", () => {
    const ended = { ...contentState, working: 0, needsInput: 0, rows: [], more: 0, updatedAt: 1_702 };
    expect(buildEnd(ended, 1_800)).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_702,
          event: "end",
          "content-state": ended,
          "dismissal-date": 1_800,
        },
      },
    });
  });
});

describe("sendLiveActivity", () => {
  test("uses the shared APNs transport with liveactivity topic, push type, and priority", async () => {
    const calls: Parameters<ApnsTransport>[0][] = [];
    const transport: ApnsTransport = async (args) => {
      calls.push(args);
      return { ok: true, status: 200 };
    };
    const push = buildUpdate({
      working: 1,
      needsInput: 0,
      rows: [{ sid: "s1", title: "Build", state: "working", since: 1_700 }],
      more: 0,
      updatedAt: 1_700,
    });
    await sendLiveActivity({ token: "tok", env: "sandbox" }, push, cfg, transport);

    expect(calls.length).toBe(1);
    expect(calls[0].host).toBe("api.development.push.apple.com");
    expect(calls[0].topic).toBe("dev.omg.lfg.push-type.liveactivity");
    expect(calls[0].pushType).toBe("liveactivity");
    expect(calls[0].priority).toBe(10);
    expect(JSON.parse(calls[0].body)).toEqual(push.body);
  });
});
