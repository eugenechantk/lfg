import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "lfg-liveactivity-"));
  process.env.LFG_LIVE_ACTIVITY_STORE = join(dir, "live-activity-tokens.json");
});
afterEach(() => {
  delete process.env.LFG_LIVE_ACTIVITY_STORE;
  rmSync(dir, { recursive: true, force: true });
});

async function store() {
  return await import("./liveactivity-store.ts");
}

describe("Live Activity token store", () => {
  test("empty store lists nothing", async () => {
    const s = await store();
    expect(await s.listLiveActivityTokens()).toEqual([]);
  });

  test("upsert persists by token and refreshes the record", async () => {
    const s = await store();
    const first = await s.upsertLiveActivityToken({
      token: "tok1",
      kind: "pushToStart",
      env: "sandbox",
    });
    await new Promise((resolve) => setTimeout(resolve, 2));
    const second = await s.upsertLiveActivityToken({
      token: "tok1",
      kind: "activityUpdate",
      env: "production",
    });

    const list = await s.listLiveActivityTokens();
    expect(list.length).toBe(1);
    expect(list[0]).toEqual(second);
    expect(second.updatedAt).toBeGreaterThan(first.updatedAt);
    expect(second.kind).toBe("activityUpdate");
    expect(second.sessionId).toBeUndefined();
    expect(second.env).toBe("production");
  });

  test("lists push-to-start and fleet update tokens separately", async () => {
    const s = await store();
    await s.upsertLiveActivityToken({ token: "start", kind: "pushToStart", env: "sandbox" });
    await s.upsertLiveActivityToken({
      token: "u1",
      kind: "activityUpdate",
      env: "sandbox",
    });
    await s.upsertLiveActivityToken({
      token: "u2",
      kind: "activityUpdate",
      env: "production",
    });

    expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["start"]);
    expect((await s.listFleetUpdateTokens()).map((t) => t.token)).toEqual(["u1", "u2"]);
  });

  test("lookup and remove operate by token", async () => {
    const s = await store();
    await s.upsertLiveActivityToken({ token: "start", kind: "pushToStart", env: "sandbox" });
    expect((await s.lookupLiveActivityToken("start"))?.kind).toBe("pushToStart");
    await s.removeLiveActivityToken("start");
    expect(await s.lookupLiveActivityToken("start")).toBeNull();
  });
});
