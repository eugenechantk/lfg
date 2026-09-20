import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let dir: string;
let path: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "lfg-lachannel-"));
  path = join(dir, "live-activity-channels.json");
  process.env.LFG_LIVE_ACTIVITY_CHANNEL_STORE = path;
});
afterEach(() => {
  delete process.env.LFG_LIVE_ACTIVITY_CHANNEL_STORE;
  rmSync(dir, { recursive: true, force: true });
});

async function store() {
  return await import("./channel-store.ts");
}

describe("Live Activity channel store", () => {
  test("empty store has no channel for either env", async () => {
    const s = await store();
    expect(await s.listLiveActivityChannels()).toEqual([]);
    expect(await s.getLiveActivityChannel("sandbox")).toBeNull();
    expect(await s.getLiveActivityChannel("production")).toBeNull();
  });

  test("saving a channel round-trips it", async () => {
    const s = await store();
    const saved = await s.saveLiveActivityChannel("production", "dHN0LXNyY2gtY2hubA==");
    expect(saved.env).toBe("production");
    expect(saved.channelId).toBe("dHN0LXNyY2gtY2hubA==");
    expect(await s.getLiveActivityChannel("production")).toEqual(saved);
  });

  // Channels cannot be shared across environments (Apple: "a channel created in
  // the development environment can't be used in the production environment"),
  // so the store is keyed by env and the two never collide.
  test("sandbox and production channels coexist independently", async () => {
    const s = await store();
    await s.saveLiveActivityChannel("sandbox", "c2FuZGJveA==");
    await s.saveLiveActivityChannel("production", "cHJvZHVjdGlvbg==");
    expect((await s.getLiveActivityChannel("sandbox"))?.channelId).toBe("c2FuZGJveA==");
    expect((await s.getLiveActivityChannel("production"))?.channelId).toBe("cHJvZHVjdGlvbg==");
    expect(await s.listLiveActivityChannels()).toHaveLength(2);
  });

  // One channel per env: re-saving replaces rather than appending. A second row
  // for the same env would make "which channel is the card on?" ambiguous, and
  // every card already out there is subscribed to exactly one of them.
  test("re-saving an env replaces its channel instead of appending", async () => {
    const s = await store();
    await s.saveLiveActivityChannel("production", "b2xk");
    await s.saveLiveActivityChannel("production", "bmV3");
    const all = await s.listLiveActivityChannels();
    expect(all).toHaveLength(1);
    expect(all[0]!.channelId).toBe("bmV3");
  });

  test("removing an env leaves the other alone", async () => {
    const s = await store();
    await s.saveLiveActivityChannel("sandbox", "c2FuZGJveA==");
    await s.saveLiveActivityChannel("production", "cHJvZHVjdGlvbg==");
    await s.removeLiveActivityChannel("sandbox");
    expect(await s.getLiveActivityChannel("sandbox")).toBeNull();
    expect((await s.getLiveActivityChannel("production"))?.channelId).toBe("cHJvZHVjdGlvbg==");
  });

  // Same bargain as the token store: a corrupt file is equivalent to no channel,
  // never a throw. A server that cannot parse its channel file must still boot
  // and simply create a new channel.
  test("a corrupt store reads as empty rather than throwing", async () => {
    writeFileSync(path, "{not json");
    const s = await store();
    expect(await s.listLiveActivityChannels()).toEqual([]);
    expect(await s.getLiveActivityChannel("production")).toBeNull();
  });

  // Apple: "don't make assumptions on the channel ID size." A row missing the id
  // is unusable and must not be handed out as if it were a channel.
  test("rows without a usable channel id are ignored", async () => {
    writeFileSync(
      path,
      JSON.stringify([
        { env: "production", channelId: "", createdAt: 1 },
        { env: "sandbox", createdAt: 2 },
      ]),
    );
    const s = await store();
    expect(await s.getLiveActivityChannel("production")).toBeNull();
    expect(await s.getLiveActivityChannel("sandbox")).toBeNull();
  });
});
