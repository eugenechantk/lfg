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

/**
 * The OTHER half of the same drift. `sessionDisplayState` consolidated the
 * precedence ladder; these two call sites had also each grown their own copy of
 * the step BEFORE it — turning a verdict plus its fallbacks into `busy`.
 *
 * The copies diverged silently: the journal pump (what the session list renders)
 * asked `sessionTurnState`, while the push watcher (what the Live Activity
 * renders) asked `transcriptTurnState` directly, missing the hook layer and the
 * STALL_MS demotion. Result: the Lock Screen counter kept sessions that the list
 * had already released, and it took a diff of the two live signals to find it.
 *
 * A behavioural test cannot catch this — both implementations agree on the happy
 * path, which is exactly why it survived. So assert the STRUCTURE: both call
 * sites go through the shared pair, and neither reaches past it.
 * See `.claude/diagnosis-live-activity-background-updates.md`.
 */
describe("busy derivation has one implementation", () => {
  const sources = {
    "journal-pump.ts": import.meta.dir + "/journal-pump.ts",
    "push/watcher.ts": import.meta.dir + "/push/watcher.ts",
  };

  /**
   * Comments in these files legitimately NAME `transcriptTurnState` while
   * explaining why they must not call it, so match code and not prose: line
   * comments go, then we look for a call `foo(` or an import of the module.
   * Assertions are on booleans, not on the source string — a failure should read
   * as one line, not dump the whole file into the runner output.
   */
  const code = (src: string): string =>
    src
      .split("\n")
      .map((l) => l.replace(/\/\/.*$/, "").replace(/^\s*\*.*$/, ""))
      .join("\n");

  for (const [label, path] of Object.entries(sources)) {
    test(`${label} derives busy through sessionTurnState + resolveBusy`, async () => {
      const src = code(await Bun.file(path).text());
      expect(src.includes("sessionTurnState("), `${label} must ask the full arbitration`).toBe(
        true,
      );
      expect(src.includes("resolveBusy("), `${label} must use the shared last step`).toBe(true);
      expect(
        src.includes("busyWithRunningWork("),
        `${label} must preserve active child-agent and background-process work`,
      ).toBe(true);
    });

    test(`${label} does not reach past it to the transcript layer`, async () => {
      const src = code(await Bun.file(path).text());
      // Only `session-state.ts` may call the transcript layer directly; going
      // straight to it from here is what dropped the hook layer and the stall
      // guard last time.
      // Scoped to the SYMBOL, not the module: `forgetTurnState` (cache eviction)
      // is a legitimate import from `turn-state.ts` and says nothing about busy.
      expect(src.includes("transcriptTurnState"), `${label} references transcriptTurnState`).toBe(
        false,
      );
    });
  }

  test("REST session baselines use the same structured resolver for Claude and Codex", async () => {
    const src = code(await Bun.file(import.meta.dir + "/sessions.ts").text());
    const turnCalls = src.match(/await sessionTurnState\(\{ sessionId, transcriptPath \}\)/g) ?? [];
    const busyCalls = src.match(/resolveBusy\(\{/g) ?? [];

    // listSessions has two pane-backed CLI branches: Claude and Codex. Both must
    // honor the transcript's explicit open/complete turn markers before the raw
    // pane scrape; otherwise the REST poll can fight the live journal and make
    // the iOS status alternate between Working and Idle.
    expect(turnCalls).toHaveLength(2);
    expect(busyCalls.length).toBeGreaterThanOrEqual(2);
    expect(src.includes("busy: delegated || (paneBusy ?? transcriptRecent)"),
      "Codex must not bypass structured turn state").toBe(false);
  });
});
