import { describe, expect, test } from "bun:test";
import { normalizeClaudeUsage, normalizeCodexUsage, UsageCache, usageIdentity } from "./account-usage.ts";

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
