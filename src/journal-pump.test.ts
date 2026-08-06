import { test, expect, describe } from "bun:test";
import {
  appendDisappearanceRetractions,
  settleWithin,
  StepRunner,
  startSupervisedLoop,
} from "./journal-pump.ts";
import { PumpDeltas, type Journal, type JournalEventType } from "./journal.ts";

type Appended = { sid: string; type: JournalEventType; payload: unknown };

function fakeJournal() {
  const events: Appended[] = [];
  const j: Pick<Journal, "append"> = {
    append(sid: string, type: JournalEventType, payload: unknown) {
      events.push({ sid, type, payload });
      return events.length;
    },
  };
  return { j, events };
}

describe("appendDisappearanceRetractions", () => {
  test("retracts a busy session so clients don't latch `running` forever", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true); // the session was last seen working

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([
      { sid: "s1", type: "busy", payload: { sid: "s1", busy: false } },
    ]);
  });

  test("retracts a pending prompt too, so it can't strand as needs-input", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.promptChanged("s1", { question: "Approve?" });

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([
      { sid: "s1", type: "prompt", payload: { sid: "s1", prompt: null } },
    ]);
  });

  test("emits both when the session vanished while busy AND prompting", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true);
    deltas.promptChanged("s1", { question: "Approve?" });

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events.map((e) => e.type)).toEqual(["busy", "prompt"]);
  });

  test("a session already idle when it vanished costs no events", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", false);
    deltas.promptChanged("s1", null);

    appendDisappearanceRetractions(j, deltas, "s1");

    expect(events).toEqual([]);
  });

  test("a never-seen session emits nothing (no phantom retraction)", () => {
    const { j, events } = fakeJournal();

    appendDisappearanceRetractions(j, new PumpDeltas(), "unknown");

    // `busyChanged` reports a change against an absent baseline, which would
    // fabricate a busy:false for a session no client ever heard of. Guarding on
    // "we actually knew it was busy" is what keeps the journal honest.
    expect(events).toEqual([]);
  });

  test("forget() after retraction still lets a returning session re-state", () => {
    const { j, events } = fakeJournal();
    const deltas = new PumpDeltas();
    deltas.busyChanged("s1", true);

    appendDisappearanceRetractions(j, deltas, "s1");
    deltas.forget("s1");

    // Transfer round-trip: it comes back busy and must re-announce.
    expect(deltas.busyChanged("s1", true)).toBe(true);
    expect(events.length).toBe(1);
  });
});

// ---- loop supervision ----
//
// The regression these pin: on 2026-08-06 the poll loop stopped and every
// client's `busy` froze at its last value, which for two mid-turn codex sessions
// meant "Running" forever. The loop is the only thing that ever un-latches a
// client, so "the loop keeps ticking" is a correctness property, not hygiene.
// See `.claude/diagnosis-codex-stuck-running-20260806.md`.

const tick = () => new Promise((r) => setTimeout(r, 0));

describe("startSupervisedLoop", () => {
  test("keeps ticking after a sweep throws", async () => {
    const sweeps: number[] = [];
    const logs: string[] = [];
    let n = 0;
    const stop = startSupervisedLoop({
      name: "poll",
      intervalMs: 1,
      isStopped: () => false,
      log: (m) => logs.push(m),
      body: async () => {
        n++;
        sweeps.push(n);
        if (n === 1) throw new Error("refreshWatchSet blew up");
      },
    });
    while (sweeps.length < 3) await tick();
    stop();

    // Pre-fix this loop was dead after sweep 1 — the re-arm was the statement
    // after the throw. It must now survive and say so.
    expect(sweeps.length).toBeGreaterThanOrEqual(3);
    expect(logs.some((l) => l.includes("poll sweep threw"))).toBe(true);
  });

  test("stop() ends the loop", async () => {
    let n = 0;
    const stop = startSupervisedLoop({
      name: "msg",
      intervalMs: 1,
      isStopped: () => false,
      body: async () => {
        n++;
      },
    });
    while (n < 2) await tick();
    stop();
    const after = n;
    for (let i = 0; i < 20; i++) await tick();
    expect(n).toBe(after);
  });

  test("isStopped() ends the loop even mid-flight", async () => {
    let n = 0;
    let stopped = false;
    startSupervisedLoop({
      name: "msg",
      intervalMs: 1,
      isStopped: () => stopped,
      body: async () => {
        n++;
        stopped = true;
      },
    });
    while (n < 1) await tick();
    const after = n;
    for (let i = 0; i < 20; i++) await tick();
    expect(n).toBe(after);
  });

  test("logs a sweep that overruns its budget", async () => {
    const logs: string[] = [];
    let clockNow = 0;
    let n = 0;
    const stop = startSupervisedLoop({
      name: "poll",
      intervalMs: 1,
      warnMs: 100,
      isStopped: () => false,
      log: (m) => logs.push(m),
      now: () => clockNow,
      body: async () => {
        n++;
        clockNow += 500; // the sweep "took" 500ms
      },
    });
    while (n < 1) await tick();
    stop();
    expect(logs.some((l) => l.includes("poll sweep took 500ms"))).toBe(true);
  });
});

describe("settleWithin", () => {
  test("returns the value when the work finishes in time", async () => {
    expect(await settleWithin(Promise.resolve(7), 1000)).toEqual({ ok: true, value: 7 });
  });

  test("reports failure instead of rejecting, so a sweep can continue", async () => {
    expect(await settleWithin(Promise.reject(new Error("nope")), 1000)).toEqual({ ok: false });
  });

  test("gives up on work that never settles", async () => {
    const never = new Promise<void>(() => {});
    expect(await settleWithin(never, 5)).toEqual({ ok: false });
  });
});

describe("StepRunner", () => {
  test("a wedged session does not block the sessions after it", async () => {
    const logs: string[] = [];
    const runner = new StepRunner("poll", 5, (m) => logs.push(m));
    const done: string[] = [];

    // s1 hangs forever; s2 and s3 must still run this sweep.
    const sweep = async () => {
      for (const sid of ["s1", "s2", "s3"]) {
        await runner.run(sid, async () => {
          if (sid === "s1") return new Promise<void>(() => {});
          done.push(sid);
        });
      }
    };
    await sweep();

    expect(done).toEqual(["s2", "s3"]);
    expect(logs.some((l) => l.includes("poll s1 exceeded"))).toBe(true);
  });

  test("does not start a second copy of a step still outstanding", async () => {
    const runner = new StepRunner("poll", 5, () => {});
    let starts = 0;
    const hang = async () => {
      starts++;
      return new Promise<void>(() => {});
    };
    await runner.run("s1", hang);
    await runner.run("s1", hang);
    await runner.run("s1", hang);

    // One wedged session costs one outstanding promise, not one per sweep —
    // otherwise the timeout turns a stall into a spawn storm.
    expect(starts).toBe(1);
    expect(runner.stalledKeys()).toEqual(["s1"]);
  });

  test("a step that throws is reported and does not stay marked in-flight", async () => {
    const logs: string[] = [];
    const runner = new StepRunner("tail", 1000, (m) => logs.push(m));

    const abandoned = await runner.run("s1", async () => {
      throw new Error("capture-pane died");
    });

    expect(abandoned).toBe(false);
    expect(logs.some((l) => l.includes("tail s1 threw"))).toBe(true);
    expect(runner.stalledKeys()).toEqual([]);
  });

  test("a step that recovers is runnable again", async () => {
    const runner = new StepRunner("poll", 5, () => {});
    let release: (() => void) | null = null;
    await runner.run("s1", () => new Promise<void>((r) => (release = r)));
    expect(runner.stalledKeys()).toEqual(["s1"]);

    release!();
    await tick();
    expect(runner.stalledKeys()).toEqual([]);

    let ran = false;
    await runner.run("s1", async () => {
      ran = true;
    });
    expect(ran).toBe(true);
  });

  test("forget() clears a departed session's outstanding entry", async () => {
    const runner = new StepRunner("poll", 5, () => {});
    await runner.run("s1", () => new Promise<void>(() => {}));
    expect(runner.stalledKeys()).toEqual(["s1"]);
    runner.forget("s1");
    expect(runner.stalledKeys()).toEqual([]);
  });
});
