import { test, expect, describe } from "bun:test";
import { sessionDisplayState, type SessionDisplayState } from "./session-state.ts";

// The precedence table, written once per language. The Swift counterpart is
// `ios/LFGCore/Tests/LFGCoreTests/SessionDisplayStateTests.swift` and asserts the
// SAME rows in the same order, so server and client cannot drift apart without one
// of these two files going red.
//
// Keep the two tables byte-identical in content and order when changing either.
const table: Array<[prompt: boolean, blocked: boolean, busy: boolean, expected: SessionDisplayState]> = [
  // prompt wins over everything — it is the only state that needs a human
  [true, true, true, "needsInput"],
  [true, true, false, "needsInput"],
  [true, false, true, "needsInput"],
  [true, false, false, "needsInput"],
  // blocked outranks busy: an upstream API error is not "working"
  [false, true, true, "blocked"],
  [false, true, false, "blocked"],
  // plain busy
  [false, false, true, "working"],
  // nothing asserted
  [false, false, false, "idle"],
];

describe("sessionDisplayState / SessionDisplayState.resolve parity", () => {
  test("resolves the full precedence table", () => {
    for (const [promptPresent, blocked, busy, expected] of table) {
      expect(
        sessionDisplayState({ promptPresent, blocked, busy }),
        `prompt=${promptPresent} blocked=${blocked} busy=${busy}`,
      ).toBe(expected);
    }
  });

  test("the table covers every input combination", () => {
    expect(table).toHaveLength(8); // 2^3 — no combination left to drift
  });

  // The bug this consolidation exists to prevent: the Live Activity card and the
  // session list disagreeing about the same session.
  test("a blocked session is never reported as working", () => {
    for (const busy of [true, false]) {
      expect(sessionDisplayState({ promptPresent: false, blocked: true, busy })).toBe("blocked");
    }
  });

  // Null/undefined are the shapes the real callers actually pass (optional fields
  // off a decoded Session), not a synthetic edge case.
  test("absent fields are falsy, not a crash", () => {
    expect(sessionDisplayState({})).toBe("idle");
    expect(sessionDisplayState({ promptPresent: null, blocked: null, busy: null })).toBe("idle");
    expect(sessionDisplayState({ busy: true, blocked: null })).toBe("working");
  });
});
