import { describe, expect, test, beforeEach, afterEach } from "bun:test";
import { Journal, PumpDeltas, RETENTION_MS } from "./journal.ts";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let dir: string;
let j: Journal;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "lfg-journal-"));
  j = Journal.open(join(dir, "journal.db"));
});

afterEach(() => {
  j.close();
  rmSync(dir, { recursive: true, force: true });
});

describe("journal core", () => {
  test("append returns monotonically increasing seqs and head tracks them", () => {
    expect(j.head()).toBe(0);
    const a = j.append("s1", "busy", { sid: "s1", busy: true });
    const b = j.append("s1", "msg", { sid: "s1", m: { id: "m1" } });
    expect(b).toBeGreaterThan(a);
    expect(j.head()).toBe(b);
  });

  test("since replays strictly-after, oldest first, with payload intact", () => {
    j.append("s1", "busy", { sid: "s1", busy: true });
    const b = j.append("s1", "msg", { sid: "s1", m: { id: "m1", text: "hi" } });
    const c = j.append("s2", "queue", { sid: "s2", queue: [] });
    const rows = j.since(b - 1);
    expect(rows.map((r) => r.seq)).toEqual([b, c]);
    expect(JSON.parse(rows[0].payload).m.text).toBe("hi");
    expect(j.since(c)).toEqual([]);
  });

  test("since respects limit", () => {
    for (let i = 0; i < 10; i++) j.append("s1", "busy", { sid: "s1", busy: i % 2 === 0 });
    expect(j.since(0, 3).length).toBe(3);
  });

  test("subscribe delivers appended rows live; unsubscribe stops delivery", () => {
    const got: number[] = [];
    const unsub = j.subscribe((r) => got.push(r.seq));
    const a = j.append("s1", "busy", { sid: "s1", busy: true });
    unsub();
    j.append("s1", "busy", { sid: "s1", busy: false });
    expect(got).toEqual([a]);
  });

  test("a throwing subscriber does not break append or other subscribers", () => {
    const got: number[] = [];
    j.subscribe(() => {
      throw new Error("bad listener");
    });
    j.subscribe((r) => got.push(r.seq));
    const a = j.append("s1", "busy", { sid: "s1", busy: true });
    expect(got).toEqual([a]);
  });
});

describe("canServe (resync boundaries)", () => {
  test("empty journal: only cursor 0 is serviceable", () => {
    expect(j.canServe(0)).toBe(true);
    expect(j.canServe(5)).toBe(false); // cursor from a previous journal lifetime
  });

  test("cursor within retained range is serviceable, including exactly head", () => {
    const a = j.append("s1", "busy", { sid: "s1", busy: true });
    const b = j.append("s1", "busy", { sid: "s1", busy: false });
    expect(j.canServe(0)).toBe(true); // full replay from before the oldest
    expect(j.canServe(a)).toBe(true);
    expect(j.canServe(b)).toBe(true); // caught up
  });

  test("cursor beyond head is unserviceable (journal was recreated)", () => {
    j.append("s1", "busy", { sid: "s1", busy: true });
    expect(j.canServe(999)).toBe(false);
  });

  test("cursor predating retention is unserviceable after pruning", () => {
    // Two old events, then one fresh; prune drops the old ones.
    const now = Date.now();
    j.append("s1", "busy", { sid: "s1", busy: true });
    j.append("s1", "busy", { sid: "s1", busy: false });
    const keep = j.append("s1", "msg", { sid: "s1", m: { id: "m" } });
    // Age the first two out by pruning "in the future" relative to them only:
    // simulate by pruning with now + RETENTION_MS - 1ms → nothing dropped yet…
    expect(j.prune(now + RETENTION_MS - 60_000)).toBe(0);
    // …then a prune where the first two fall outside the window. All three
    // share ~the same ts here, so instead verify the boundary logic directly
    // by deleting via prune at a time where all are stale:
    expect(j.prune(now + RETENTION_MS + 60_000)).toBe(3);
    expect(j.canServe(keep - 1)).toBe(false); // pruned past it
    expect(j.canServe(keep)).toBe(true); // exactly head, empty-but-consistent
  });
});

describe("pump offsets", () => {
  test("round-trips and upserts", () => {
    expect(j.getOffset("s1")).toBeNull();
    j.setOffset("s1", 100);
    expect(j.getOffset("s1")).toBe(100);
    j.setOffset("s1", 250);
    expect(j.getOffset("s1")).toBe(250);
  });
});

describe("PumpDeltas", () => {
  test("first sight always emits; unchanged values do not", () => {
    const d = new PumpDeltas();
    expect(d.busyChanged("s1", false)).toBe(true); // baseline stated even for idle
    expect(d.busyChanged("s1", false)).toBe(false);
    expect(d.busyChanged("s1", true)).toBe(true);
    expect(d.busyChanged("s1", true)).toBe(false);
  });

  test("prompt compares structurally; null and absent are the same state only after first sight", () => {
    const d = new PumpDeltas();
    expect(d.promptChanged("s1", null)).toBe(true); // baseline: no prompt
    expect(d.promptChanged("s1", null)).toBe(false);
    expect(d.promptChanged("s1", { question: "q", options: [] })).toBe(true);
    expect(d.promptChanged("s1", { question: "q", options: [] })).toBe(false);
    expect(d.promptChanged("s1", null)).toBe(true); // prompt cleared
  });

  test("queue compares by content", () => {
    const d = new PumpDeltas();
    expect(d.queueChanged("s1", [])).toBe(true); // baseline
    expect(d.queueChanged("s1", [])).toBe(false);
    expect(d.queueChanged("s1", [{ id: "q1", status: "pending" }])).toBe(true);
    expect(d.queueChanged("s1", [{ id: "q1", status: "delivered" }])).toBe(true);
  });

  test("forget clears baselines so a returning session re-states them", () => {
    const d = new PumpDeltas();
    d.busyChanged("s1", true);
    d.forget("s1");
    expect(d.busyChanged("s1", true)).toBe(true);
  });
});
