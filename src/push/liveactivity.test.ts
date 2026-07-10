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
  test("buildStart produces the pinned liveactivity header/body shape", () => {
    const push = buildStart(
      { sid: "s1", title: "Build", state: "working", since: 1_700, hostName: "mac" },
      LIVE_ACTIVITY_ATTRIBUTES_TYPE,
    );
    expect(push).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_700,
          event: "start",
          "content-state": { title: "Build", state: "working", sid: "s1", since: 1_700 },
          "attributes-type": "LFGSessionAttributes",
          attributes: { sid: "s1", hostName: "mac" },
          alert: { title: "Build", body: "LFG session is working." },
        },
      },
    });
  });

  test("buildUpdate produces the pinned update shape", () => {
    expect(buildUpdate({ sid: "s1", title: "Build", state: "blocked", since: 1_701 })).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_701,
          event: "update",
          "content-state": { title: "Build", state: "blocked", sid: "s1", since: 1_701 },
        },
      },
    });
  });

  test("buildEnd produces the pinned end shape with optional dismissal date", () => {
    expect(buildEnd({ sid: "s1", title: "Build", state: "idle", since: 1_702 }, 1_800)).toEqual({
      headers: {
        "apns-push-type": "liveactivity",
        "apns-topic": `${DEFAULT_APNS_TOPIC}.push-type.liveactivity`,
        "apns-priority": 10,
      },
      body: {
        aps: {
          timestamp: 1_702,
          event: "end",
          "content-state": { title: "Build", state: "idle", sid: "s1", since: 1_702 },
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
    const push = buildUpdate({ sid: "s1", title: "Build", state: "working", since: 1_700 });
    await sendLiveActivity({ token: "tok", env: "sandbox" }, push, cfg, transport);

    expect(calls.length).toBe(1);
    expect(calls[0].host).toBe("api.development.push.apple.com");
    expect(calls[0].topic).toBe("dev.omg.lfg.push-type.liveactivity");
    expect(calls[0].pushType).toBe("liveactivity");
    expect(calls[0].priority).toBe(10);
    expect(JSON.parse(calls[0].body)).toEqual(push.body);
  });
});
