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

  test("lists push-to-start and per-session update tokens separately", async () => {
    const s = await store();
    await s.upsertLiveActivityToken({ token: "start", kind: "pushToStart", env: "sandbox" });
    await s.upsertLiveActivityToken({
      token: "u1",
      kind: "activityUpdate",
      sessionId: "s1",
      env: "sandbox",
    });
    await s.upsertLiveActivityToken({
      token: "u2",
      kind: "activityUpdate",
      sessionId: "s2",
      env: "production",
    });

    expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["start"]);
    // Update tokens are device-level now — there is one fleet activity per
    // device, so every registered update token is a target.
    expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["u1", "u2"]);
  });

  /**
   * The store used to APPEND: every rotation or re-created card left its old
   * token behind, and the live store reached 8 `activityUpdate` tokens for one
   * device. That is not merely untidy — a dead Live Activity token still answers
   * **200** from APNs, so the watcher counted a push to a corpse as delivered and
   * never re-established an addressable card.
   * See `.claude/diagnosis-live-activity-background-updates.md`.
   */
  describe("activityUpdate tokens supersede per env (SC3)", () => {
    test("a newer update token replaces the previous one for that env", async () => {
      const s = await store();
      await s.upsertLiveActivityToken({ token: "old", kind: "activityUpdate", env: "production" });
      await s.upsertLiveActivityToken({ token: "new", kind: "activityUpdate", env: "production" });

      expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["new"]);
    });

    test("the two APNs environments do not evict each other", async () => {
      // A debug build (sandbox) and a TestFlight build (production) are different
      // installs with different cards; one must not knock the other out.
      const s = await store();
      await s.upsertLiveActivityToken({ token: "sand", kind: "activityUpdate", env: "sandbox" });
      await s.upsertLiveActivityToken({ token: "prod", kind: "activityUpdate", env: "production" });

      expect((await s.listActivityUpdateTokens()).map((t) => t.token).sort()).toEqual([
        "prod",
        "sand",
      ]);
    });

    test("push-to-start tokens are untouched by an update-token registration", async () => {
      // Push-to-start is a capability of the INSTALL, not of any one card, so it
      // outlives every activity and must not be swept up by the supersede.
      const s = await store();
      await s.upsertLiveActivityToken({ token: "start", kind: "pushToStart", env: "production" });
      await s.upsertLiveActivityToken({ token: "u1", kind: "activityUpdate", env: "production" });
      await s.upsertLiveActivityToken({ token: "u2", kind: "activityUpdate", env: "production" });

      expect((await s.listPushToStartTokens()).map((t) => t.token)).toEqual(["start"]);
      expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["u2"]);
    });

    test("re-registering the SAME token is a refresh, not a churn", async () => {
      const s = await store();
      const first = await s.upsertLiveActivityToken({
        token: "same",
        kind: "activityUpdate",
        env: "production",
      });
      await new Promise((resolve) => setTimeout(resolve, 2));
      const again = await s.upsertLiveActivityToken({
        token: "same",
        kind: "activityUpdate",
        env: "production",
      });

      expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["same"]);
      expect(again.updatedAt).toBeGreaterThan(first.updatedAt);
    });

    test("promoting a pushToStart token to activityUpdate does not evict itself", async () => {
      // The same hex can legitimately arrive under both kinds; the supersede must
      // not delete the record it is in the middle of writing.
      const s = await store();
      await s.upsertLiveActivityToken({ token: "dual", kind: "pushToStart", env: "sandbox" });
      await s.upsertLiveActivityToken({ token: "dual", kind: "activityUpdate", env: "sandbox" });

      expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["dual"]);
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

    test("activityUpdate tokens are untouched by the cap", async () => {
      const s = await store();
      for (const tok of ["p1", "p2", "p3", "p4"]) {
        await s.upsertLiveActivityToken({ token: tok, kind: "pushToStart", env: "sandbox" });
        await new Promise((resolve) => setTimeout(resolve, 2));
      }
      await s.upsertLiveActivityToken({ token: "u1", kind: "activityUpdate", env: "sandbox" });
      expect((await s.listActivityUpdateTokens()).map((t) => t.token)).toEqual(["u1"]);
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
