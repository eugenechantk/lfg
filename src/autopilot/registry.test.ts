import { describe, expect, test } from "bun:test";
import { parseAutopilotState, recordRun } from "./registry.ts";

describe("parseAutopilotState", () => {
  test("round-trips a full record", () => {
    const raw = { retitle: { lastRunAt: 123, lastOk: true, lastNote: "3 renamed", lastChanged: 3 } };
    expect(parseAutopilotState(raw)).toEqual(raw);
  });

  test("drops rows without a usable lastRunAt", () => {
    const parsed = parseAutopilotState({
      good: { lastRunAt: 1 },
      noTs: { lastOk: true },
      nan: { lastRunAt: NaN },
      notObj: 5,
    });
    expect(Object.keys(parsed)).toEqual(["good"]);
  });

  test("a non-object file yields empty state", () => {
    for (const v of [null, undefined, "x", 1, []]) expect(parseAutopilotState(v)).toEqual({});
  });

  test("state is history, not scheduling — a corrupt file cannot stop a run", () => {
    // Every step runs on every tick regardless of this file; it exists so the
    // CLI and log can report how the last run went.
    expect(parseAutopilotState("{{{ truncated")).toEqual({});
  });
});

describe("recordRun", () => {
  test("stamps the run and preserves other steps", () => {
    const next = recordRun({ b: { lastRunAt: 5 } }, "a", 100, {
      ok: true,
      note: "2 renamed",
      changed: 2,
    });
    expect(next).toEqual({
      b: { lastRunAt: 5 },
      a: { lastRunAt: 100, lastOk: true, lastNote: "2 renamed", lastChanged: 2 },
    });
  });

  test("records a failure without losing the timestamp", () => {
    const next = recordRun({}, "a", 100, { ok: false, note: "LLM call failed" });
    expect(next.a).toEqual({ lastRunAt: 100, lastOk: false, lastNote: "LLM call failed" });
  });

  test("a long note is truncated", () => {
    expect(recordRun({}, "a", 1, { ok: true, note: "x".repeat(500) }).a.lastNote).toHaveLength(200);
  });

  test("omits changed when the step did not report it", () => {
    expect(recordRun({}, "a", 1, { ok: true }).a.lastChanged).toBeUndefined();
  });
});
