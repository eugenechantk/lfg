// Throwaway auditor test — NOT part of src. Probes reduceTransition rule edges
// the new watcher.test.ts cases do not cover.
import { test, expect, describe } from "bun:test";
import { reduceTransition, type PriorState, type SessionState } from "/Users/eugenechan/dev/personal/lfg/src/push/watcher.ts";
const seed = (busy: boolean, promptPresent: boolean): PriorState => ({ busy, promptPresent, lastNotifiedAt: Number.NEGATIVE_INFINITY });
const obs = (busy: boolean, promptPresent: boolean): SessionState => ({ busy, promptPresent });

describe("existing rules still hold", () => {
  test("busy → idle, no prompt → finished", () => {
    expect(reduceTransition(seed(true, false), obs(false, false), 1000).event).toBe("finished");
  });
  test("idle, prompt appears → needs-input", () => {
    expect(reduceTransition(seed(false, false), obs(false, true), 1000).event).toBe("needs-input");
  });
  test("busy → idle WITH prompt appearing same tick → needs-input (not finished)", () => {
    expect(reduceTransition(seed(true, false), obs(false, true), 1000).event).toBe("needs-input");
  });
  test("finished then prompt 3s later is deduped", () => {
    const a = reduceTransition(seed(true, false), obs(false, false), 1000);
    expect(reduceTransition(a.state, obs(false, true), 4000).event).toBeNull();
  });
  test("idle → idle no prompt: silent", () => {
    expect(reduceTransition(seed(false, false), obs(false, false), 1000).event).toBeNull();
  });
  test("prompt answered while idle then busy again: silent", () => {
    expect(reduceTransition(seed(false, true), obs(true, false), 1000).event).toBeNull();
  });
});

describe("EDGE: dedupe-swallowed busy prompt is never re-announced", () => {
  test("finished@t0, user replies, prompt appears while busy @t0+3s (deduped), later busy→idle with prompt still pending → NO push ever", () => {
    const a = reduceTransition(seed(true, false), obs(false, false), 1000);   // finished push
    expect(a.event).toBe("finished");
    const b = reduceTransition(a.state, obs(true, false), 2000);             // user replied, busy again
    expect(b.event).toBeNull();
    const c = reduceTransition(b.state, obs(true, true), 4000);              // question appears while busy, 3s after push → deduped
    expect(c.event).toBeNull();
    expect(c.state.promptPresent).toBe(true);
    const d = reduceTransition(c.state, obs(true, true), 30_000);            // still busy, still asking
    expect(d.event).toBeNull();
    const e = reduceTransition(d.state, obs(false, true), 60_000);           // turn state drops to idle, prompt still pending
    // OLD reducer: stoppedThisTick && promptPresent → "needs-input". NEW: nothing.
    expect(e.event).toBeNull();
  });
});

describe("EDGE: seeded busy+prompt then idle", () => {
  test("seeded (busy, prompt) → idle with same prompt → NO push (old reducer: needs-input)", () => {
    expect(reduceTransition(seed(true, true), obs(false, true), 1000).event).toBeNull();
  });
});
