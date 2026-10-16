import { describe, expect, test } from "bun:test";
import { countClosed, createTotalCache } from "./resumable-total.ts";

describe("closed-session total (B12)", () => {
  test("counts only the candidates no host holds a fresh lease on", async () => {
    const fresh = new Set(["live-a", "live-b"]);
    const candidates = ["live-a", "closed-1", "live-b", "closed-2", "closed-3"].map((id) => ({
      id,
      path: `/p/${id}.jsonl`,
    }));
    const total = await countClosed(candidates, async (id) => (fresh.has(id) ? "host" : null));
    expect(total).toBe(3);
  });

  test("the first read is null, later reads serve the count, and it recounts only after the TTL", async () => {
    let clock = 0;
    let runs = 0;
    let next = 10;
    const cache = createTotalCache(
      async () => {
        runs++;
        return next;
      },
      { ttlMs: 60_000, now: () => clock },
    );
    expect(cache.get("[]")).toBeNull();
    await cache.settle("[]");
    expect(cache.get("[]")).toBe(10);
    expect(runs).toBe(1);

    next = 12;
    clock = 59_999;
    expect(cache.get("[]")).toBe(10);
    expect(runs).toBe(1);

    clock = 60_000;
    expect(cache.get("[]")).toBe(10); // stale value served while the recount runs
    await cache.settle("[]");
    expect(cache.get("[]")).toBe(12);
    expect(runs).toBe(2);
  });

  test("each hidden-folder set has its own count, and a failed count keeps the last number", async () => {
    let clock = 0;
    let fail = false;
    const cache = createTotalCache(
      async (key) => {
        if (fail) throw new Error("disk");
        return key === "[]" ? 100 : 40;
      },
      { ttlMs: 1000, now: () => clock },
    );
    cache.get("[]");
    cache.get('["/tmp"]');
    await cache.settle("[]");
    await cache.settle('["/tmp"]');
    expect(cache.get("[]")).toBe(100);
    expect(cache.get('["/tmp"]')).toBe(40);

    fail = true;
    clock = 1000;
    cache.get("[]");
    await cache.settle("[]");
    expect(cache.get("[]")).toBe(100);
  });
});
