import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { claudePlan, fileUsageStore, normalizeClaudeUsage, normalizeCodexUsage, retryAt, UsageCache, usageIdentity, UsageReadError } from "./account-usage.ts";

const identity = { accountId: "account-a", accountLabel: "a@example.test", plan: "Max 20×" };
const now = "2026-10-20T08:00:00.000Z";

describe("provider quota normalization", () => {
  test("Claude retains genuine zero and independently missing windows", () => {
    const result = normalizeClaudeUsage({ five_hour: { utilization: 0, resets_at: "2026-10-20T09:00:00Z" } }, identity, now);
    expect(result.windows.map(w => [w.durationMinutes, w.usedPercent])).toEqual([[300, 0], [10080, null]]);
  });
  test("invalid percentages and reset dates never become invented values", () => {
    const result = normalizeClaudeUsage({ five_hour: { utilization: "50", resets_at: "invalid" }, seven_day: { utilization: -1 } }, identity, now);
    expect(result.windows.every(w => w.usedPercent === null && w.resetsAt === null)).toBe(true);
  });
  test("Codex primary can be weekly, with no fabricated session quota", () => {
    const result = normalizeCodexUsage({ rateLimits: { primary: { usedPercent: 1, windowDurationMins: 10080, resetsAt: 1793072434 } } }, identity, now);
    expect(result.windows.map(w => [w.durationMinutes, w.usedPercent])).toEqual([[300, null], [10080, 1]]);
  });
  test("Codex supports additional buckets and arbitrary durations", () => {
    const result = normalizeCodexUsage({ rateLimitsByLimitId: {
      codex: { primary: { usedPercent: 25, windowDurationMins: 300 }, secondary: { usedPercent: 90, windowDurationMins: 10080 } },
      other: { limitName: "Other model", primary: { usedPercent: 40, windowDurationMins: 60 } },
    } }, identity, now);
    expect(result.windows.map(w => w.durationMinutes)).toEqual([60, 300, 10080]);
    expect(result.windows.find(w => w.durationMinutes === 60)?.name).toBe("Other model");
  });
  test("empty response is unavailable, not zero usage", () => {
    const result = normalizeCodexUsage({}, identity, now);
    expect(result.status).toBe("unavailable");
    expect(result.windows).toEqual([]);
  });
  test("identity requires provider account proof and is stable across hosts", () => {
    expect(usageIdentity("claude", null)).toBeNull();
    expect(usageIdentity("claude", "account:org")).toBe(usageIdentity("claude", "account:org"));
    expect(usageIdentity("claude", "account:org")).not.toBe(usageIdentity("codex", "account:org"));
  });
  test("out-of-range dates and quota durations do not escape normalization", () => {
    const value = normalizeCodexUsage({ rateLimits: { primary: { usedPercent: 5, windowDurationMins: 1e100, resetsAt: 1e100 } } }, identity, now);
    expect(value.windows).toEqual([]);
    const claude = normalizeClaudeUsage({ five_hour: { utilization: 5, resets_at: 1e100 } }, identity, now);
    expect(claude.windows[0]?.resetsAt).toBeNull();
  });
});

describe("account-scoped cache", () => {
  test("coalesces parallel reads and serves a short cache", async () => {
    let calls = 0;
    const cache = new UsageCache(() => 1000);
    const load = async () => { calls++; await Bun.sleep(2); return normalizeClaudeUsage({ five_hour: { utilization: 25 } }, identity, now); };
    await Promise.all([cache.read("a", load), cache.read("a", load)]);
    await cache.read("a", load);
    expect(calls).toBe(1);
  });
  test("a changed credential context never inherits cached usage", async () => {
    const cache = new UsageCache(() => 1000);
    await cache.read("a", async () => normalizeClaudeUsage({ five_hour: { utilization: 25 } }, identity, now));
    await expect(cache.read("b", async () => { throw new Error("unavailable"); })).rejects.toThrow("unavailable");
  });
  test("a failed refresh preserves the last reading with its original timestamp", async () => {
    let time = 1000;
    const cache = new UsageCache(() => time);
    await cache.read("a", async () => normalizeClaudeUsage({ five_hour: { utilization: 25 } }, identity, now));
    time += 61_000;
    const result = await cache.read("a", async () => { throw new Error("upstream failed"); });
    expect(result.status).toBe("error");
    expect(result.fetchedAt).toBe(now);
    expect(result.windows[0]?.usedPercent).toBe(25);
    expect(JSON.stringify(result)).not.toContain("upstream failed");
  });
});

describe("provider rate limits", () => {
  const reading = (pct: number, accountId = "account-a") => normalizeClaudeUsage({ five_hour: { utilization: pct } }, { ...identity, accountId }, now);
  const limited = (at: number) => async () => { throw new UsageReadError("rate_limited", at); };

  test("retry-after accepts seconds and dates, and is clamped", () => {
    expect(retryAt("120", 1_000)).toBe(121_000);
    expect(retryAt(new Date(1_000 + 600_000).toUTCString(), 1_000)).toBe(Math.floor((1_000 + 600_000) / 1000) * 1000);
    expect(retryAt(null, 1_000)).toBe(1_000 + 300_000);
    expect(retryAt("5", 1_000)).toBe(1_000 + 30_000);
    expect(retryAt("999999", 1_000)).toBe(1_000 + 7_200_000);
  });

  test("a 429 holds further reads until retry-after, without calling the provider", async () => {
    let time = 1_000, calls = 0;
    const cache = new UsageCache(() => time);
    await expect(cache.read("token-1", async () => { calls++; throw new UsageReadError("rate_limited", 3_601_000); }, "account-a"))
      .rejects.toMatchObject({ code: "rate_limited", retryAt: 3_601_000 });
    time += 61_000;
    await expect(cache.read("token-1", async () => { calls++; return reading(10); }, "account-a")).rejects.toMatchObject({ code: "rate_limited" });
    // A rotated token for the same account is still held.
    await expect(cache.read("token-2", async () => { calls++; return reading(10); }, "account-a")).rejects.toMatchObject({ code: "rate_limited" });
    expect(calls).toBe(1);
    time = 3_601_001;
    expect((await cache.read("token-2", async () => { calls++; return reading(10); }, "account-a")).windows[0]?.usedPercent).toBe(10);
    expect(calls).toBe(2);
  });

  test("the last reading survives a token rotation and is returned during a hold", async () => {
    let time = 1_000;
    const cache = new UsageCache(() => time);
    await cache.read("token-1", async () => reading(25), "account-a");
    time += 61_000;
    const result = await cache.read("token-2", limited(time + 600_000), "account-a");
    expect(result).toMatchObject({ status: "error", error: "rate_limited", fetchedAt: now, retryAt: new Date(time + 600_000).toISOString() });
    expect(result.windows[0]?.usedPercent).toBe(25);
  });

  test("the last reading survives a restart through the file store", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "lfg-usage-")), "account-usage.json");
    const first = new UsageCache(() => 1_000, fileUsageStore(path));
    await first.read("token-1", async () => reading(40), "account-a");
    await first.flush();
    const second = new UsageCache(() => 2_000, fileUsageStore(path));
    const result = await second.read("token-1", limited(900_000), "account-a");
    expect(result).toMatchObject({ status: "error", error: "rate_limited", fetchedAt: now });
    expect(result.windows[0]?.usedPercent).toBe(40);
  });

  test("another account never inherits a stored reading", async () => {
    const cache = new UsageCache(() => 1_000);
    await cache.read("token-a", async () => reading(25), "account-a");
    await expect(cache.read("token-b", limited(900_000), "account-b")).rejects.toMatchObject({ code: "rate_limited" });
  });

  test("an unproven reading is never stored", async () => {
    let time = 1_000;
    const cache = new UsageCache(() => time);
    await cache.read("token-1", async () => reading(25, null as unknown as string), "account-a");
    time += 61_000;
    await expect(cache.read("token-2", limited(time + 600_000), "account-a")).rejects.toMatchObject({ code: "rate_limited" });
  });

  test("readings older than eight days are not served", async () => {
    let time = Date.parse(now);
    const cache = new UsageCache(() => time);
    await cache.read("token-1", async () => reading(25), "account-a");
    time += 9 * 86_400_000;
    await expect(cache.read("token-2", limited(time + 600_000), "account-a")).rejects.toMatchObject({ code: "rate_limited" });
  });
});

describe("Claude plan label", () => {
  test("the account tier in ~/.claude.json wins over a stale credentials tier", () => {
    expect(claudePlan("default_claude_max_20x", { rateLimitTier: "default_claude_max_5x", subscriptionType: "max" })).toBe("Max 20×");
    expect(claudePlan(null, { rateLimitTier: "default_claude_max_5x" })).toBe("Max 5×");
    expect(claudePlan(null, { subscriptionType: "pro" })).toBe("Pro");
    expect(claudePlan(null, {})).toBeNull();
  });
});
