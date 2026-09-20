import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
    const first = await s.upsertLiveActivityToken({ token: "tok1", env: "sandbox" });
    await new Promise((resolve) => setTimeout(resolve, 2));
    const second = await s.upsertLiveActivityToken({ token: "tok1", env: "production" });

    const list = await s.listLiveActivityTokens();
    expect(list.length).toBe(1);
    expect(list[0]).toEqual(second);
    expect(second.updatedAt).toBeGreaterThan(first.updatedAt);
    expect(second.kind).toBe("pushToStart");
    expect(second.env).toBe("production");
  });

  test("lists only push-to-start tokens", async () => {
    const s = await store();
    await s.upsertLiveActivityToken({ token: "start", env: "sandbox" });
    expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["start"]);
  });

  /**
   * `activityUpdate` was the per-card token used to address update/end. It is
   * gone: obtaining it required iOS to wake the app after a push-to-start, which
   * on an idle phone routinely never happened, and a dead Live Activity token
   * answers 200 so the server could not tell. Update/end now go over a broadcast
   * channel.
   *
   * A store written before that change can still hold these rows — the Air's held
   * **35**, untouched since July — and they must not survive the upgrade: they
   * address nothing, and the supersede rule that used to bound them is gone with
   * the kind itself.
   */
  describe("legacy activityUpdate rows", () => {
    test("are pruned on read, not merely on the next write", async () => {
      writeFileSync(
        process.env.LFG_LIVE_ACTIVITY_STORE!,
        JSON.stringify([
          { token: "start", kind: "pushToStart", env: "production", updatedAt: 1 },
          { token: "u1", kind: "activityUpdate", env: "production", updatedAt: 2 },
          { token: "u2", kind: "activityUpdate", env: "sandbox", updatedAt: 3 },
        ]),
      );
      const s = await store();
      expect((await s.listLiveActivityTokens()).map((t) => t.token)).toEqual(["start"]);
      expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["start"]);
    });

    test("do not consume push-to-start cap slots", async () => {
      // The cap keeps the newest N push-to-start tokens per env. Legacy rows
      // counting toward it would silently evict a real device's token.
      writeFileSync(
        process.env.LFG_LIVE_ACTIVITY_STORE!,
        JSON.stringify(
          Array.from({ length: 30 }, (_, i) => ({
            token: `legacy${i}`,
            kind: "activityUpdate",
            env: "production",
            updatedAt: 1000 + i,
          })),
        ),
      );
      const s = await store();
      await s.upsertLiveActivityToken({ token: "real", env: "production" });
      expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["real"]);
    });
  });


  /**
   * Push-to-start tokens rot: dev/simulator builds each mint one, none ever
   * 410s promptly, and the live store reached 19 — every `start` blasted all of
   * them. Newest-3 per env keeps the real install's token by construction (it
   * re-registers on every app launch) without the stranding risk of age-based
   * pruning. Capped per env so a churn of sandbox dev builds can never evict a
   * production token.
   */
  describe("pushToStart tokens are capped to the newest 3 per env", () => {
    test("registering a 4th sandbox token evicts the oldest sandbox token only", async () => {
      const s = await store();
      for (const tok of ["p1", "p2", "p3", "p4"]) {
        await s.upsertLiveActivityToken({ token: tok, kind: "pushToStart", env: "sandbox" });
        await new Promise((resolve) => setTimeout(resolve, 2));
      }
      expect((await s.listPushToStartTokens()).map((t) => t.token).sort()).toEqual([
        "p2",
        "p3",
        "p4",
      ]);
    });

    test("the two envs have independent caps", async () => {
      const s = await store();
      for (const tok of ["s1", "s2", "s3", "s4"]) {
        await s.upsertLiveActivityToken({ token: tok, kind: "pushToStart", env: "sandbox" });
        await new Promise((resolve) => setTimeout(resolve, 2));
      }
      await s.upsertLiveActivityToken({ token: "prod1", kind: "pushToStart", env: "production" });
      const tokens = await s.listPushToStartTokens();
      expect(tokens.filter((t) => t.env === "production").map((t) => t.token)).toEqual(["prod1"]);
      expect(tokens.filter((t) => t.env === "sandbox").length).toBe(3);
    });

    test("re-registering an existing token refreshes it instead of burning a slot", async () => {
      const s = await store();
      for (const tok of ["p1", "p2", "p3"]) {
        await s.upsertLiveActivityToken({ token: tok, kind: "pushToStart", env: "sandbox" });
        await new Promise((resolve) => setTimeout(resolve, 2));
      }
      await s.upsertLiveActivityToken({ token: "p1", kind: "pushToStart", env: "sandbox" });
      expect((await s.listPushToStartTokens()).map((t) => t.token).sort()).toEqual([
        "p1",
        "p2",
        "p3",
      ]);
    });


    test("an oversized store on disk is capped at read time, before any new registration", async () => {
      // The live store already holds 11+ sandbox corpses; the cap must apply on
      // the next server start, not only after the next app launch re-registers.
      const s = await store();
      const list = [];
      for (let i = 0; i < 6; i++) {
        list.push({ token: `old${i}`, kind: "pushToStart", env: "sandbox", updatedAt: 1000 + i });
      }
      await Bun.write(process.env.LFG_LIVE_ACTIVITY_STORE!, JSON.stringify(list));
      expect((await s.listPushToStartTokens()).map((t) => t.token).sort()).toEqual([
        "old3",
        "old4",
        "old5",
      ]);
    });
  });

  test("lookup and remove operate by token", async () => {
    const s = await store();
    await s.upsertLiveActivityToken({ token: "start", kind: "pushToStart", env: "sandbox" });
    expect((await s.lookupLiveActivityToken("start"))?.kind).toBe("pushToStart");
    await s.removeLiveActivityToken("start");
    expect(await s.lookupLiveActivityToken("start")).toBeNull();
  });
});
