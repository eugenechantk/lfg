// close/interrupt must report the OUTCOME, not the transport's exit code.
// Both endpoints used to answer `200 {"ok":true}` off a `tmux` exit status that
// only ever proved the pane existed.
// See `.claude/diagnosis-stop-close-noop-20260806.md`.
import { describe, expect, test } from "bun:test";
import { closeAll, interruptAndConfirm, type CloseTarget } from "./closing.ts";

const noWait = () => Promise.resolve();

/** A killer whose panes really die, tracked so we can assert what was targeted. */
function fakeHost(deadOnHup: number[]) {
  const killedSessions: string[] = [];
  const killedPanes: string[] = [];
  const sigkilled: number[] = [];
  const dead = new Set(deadOnHup);
  return {
    killedSessions,
    killedPanes,
    sigkilled,
    deps: {
      killSession: (n: string) => (killedSessions.push(n), true),
      killPane: (t: string) => (killedPanes.push(t), true),
      alive: (pid: number) => !dead.has(pid),
      kill9: (pid: number) => {
        sigkilled.push(pid);
        dead.add(pid); // SIGKILL works in this fake unless the test says otherwise
      },
      wait: noWait,
    },
  };
}

const pane = (pid: number, name: string, managed = false): CloseTarget => ({
  pid,
  tmuxTarget: `${name}:0.0`,
  tmuxName: name,
  managed,
});

describe("closeAll — every pane backing the session", () => {
  // SC1. THE bug: two panes claimed one sessionId (a transcript resumed into a
  // second pane), `.find()` killed the first, and the row came straight back.
  test("kills all targets, not just the first", async () => {
    const h = fakeHost([65399, 68901]);
    const out = await closeAll([pane(65399, "lfg-b7fee2", true), pane(68901, "cy-000647")], h.deps);
    expect(h.killedSessions).toEqual(["lfg-b7fee2"]); // managed → whole session
    expect(h.killedPanes).toEqual(["cy-000647:0.0"]); // adopted → just the pane
    expect(out.map((o) => o.killed)).toEqual([true, true]);
  });

  test("reports every pid it tried, so the caller can tombstone all of them", async () => {
    const h = fakeHost([1, 2, 3]);
    const out = await closeAll([pane(1, "a"), pane(2, "b"), pane(3, "c")], h.deps);
    expect(out.map((o) => o.pid)).toEqual([1, 2, 3]);
  });

  // SC2. A SIGHUP that leaves the agent alive is the wedged case this exists for.
  test("escalates to SIGKILL when the process survives the hangup", async () => {
    const h = fakeHost([]); // nothing dies on HUP
    const out = await closeAll([pane(999, "wedged")], h.deps);
    expect(h.sigkilled).toEqual([999]);
    expect(out[0]).toEqual({ pid: 999, target: "wedged:0.0", killed: true, escalated: true });
  });

  test("a pid that survives even SIGKILL is reported NOT killed", async () => {
    const h = fakeHost([]);
    h.deps.kill9 = () => {}; // unreapable (zombie, EPERM)
    const out = await closeAll([pane(4, "stuck")], h.deps);
    expect(out[0].killed).toBe(false);
    expect(out[0].escalated).toBe(true);
  });

  test("one dead + one unreapable → the survivor is still surfaced", async () => {
    const h = fakeHost([10]);
    h.deps.kill9 = () => {};
    const out = await closeAll([pane(10, "ok"), pane(11, "stuck")], h.deps);
    expect(out.filter((o) => !o.killed).map((o) => o.pid)).toEqual([11]);
  });

  // A collision-loser row has `tmuxTarget` nulled by `resolvePaneOwners` but is
  // still a real live agent — and it is precisely the duplicate this sweep exists
  // for. Closing must not depend on lfg having guessed the right pane.
  test("a target with no usable tmux handle is still reaped, by pid", async () => {
    const h = fakeHost([]);
    const out = await closeAll([{ pid: 7, tmuxTarget: null, tmuxName: null, managed: false }], h.deps);
    expect(h.killedPanes).toEqual([]); // nothing to drive tmux with
    expect(h.sigkilled).toEqual([7]); // …so the pid is reaped directly
    expect(out[0]).toEqual({ pid: 7, target: null, killed: true, escalated: true });
  });

  test("a pane that was already gone is not needlessly SIGKILLed", async () => {
    const h = fakeHost([21]); // dies on the hangup
    await closeAll([pane(21, "clean")], h.deps);
    expect(h.sigkilled).toEqual([]);
  });

  // A healthy `claude` takes ~1150ms to exit after kill-pane (measured on this
  // host). An earlier 700ms grace escalated on EVERY close, hard-killing agents
  // mid-shutdown and costing them the `SessionEnd` hook that writes
  // `state: "ended"` into the lease. A slow-but-clean exit must be waited out.
  test("a slow clean exit is waited out, not escalated", async () => {
    let polls = 0;
    const h = fakeHost([]);
    h.deps.alive = () => ++polls < 12; // ~1.2s at the 100ms poll interval
    const out = await closeAll([pane(30, "slow")], h.deps);
    expect(h.sigkilled).toEqual([]);
    expect(out[0]).toEqual({ pid: 30, target: "slow:0.0", killed: true, escalated: false });
  });

  test("a clean exit returns as soon as it is seen, without burning the full grace", async () => {
    let waits = 0;
    const h = fakeHost([]);
    let polls = 0;
    h.deps.alive = () => ++polls < 3;
    h.deps.wait = () => (waits++, Promise.resolve());
    await closeAll([pane(31, "quick")], h.deps);
    expect(waits).toBeLessThan(5); // not the 25 the full 2.5s grace would take
  });

  test("no targets is not an error", async () => {
    expect(await closeAll([], fakeHost([]).deps)).toEqual([]);
  });
});

describe("interruptAndConfirm — the Escape landing is not the same as it working", () => {
  const deps = (panes: (string | null)[], busyFor: (p: string) => boolean) => {
    let i = 0;
    return {
      escape: () => true,
      capture: () => Promise.resolve(panes[Math.min(i++, panes.length - 1)]),
      busy: (p: string) => busyFor(p),
      wait: noWait,
    };
  };

  // SC3. Reproduced live on the wedged session: 200 ok, still busy afterwards.
  test("pane stays busy for the whole window → stopped:false", async () => {
    const r = await interruptAndConfirm("w:0.0", deps(["✻ Crunched for 2m 4s"], () => true));
    expect(r).toEqual({ sent: true, stopped: false });
  });

  test("busy meter clears → stopped:true", async () => {
    const r = await interruptAndConfirm("w:0.0", deps(["idle pane"], () => false));
    expect(r).toEqual({ sent: true, stopped: true });
  });

  test("clears part-way through the window, not only on the first poll", async () => {
    const r = await interruptAndConfirm(
      "w:0.0",
      deps(["busy", "busy", "done"], (p) => p === "busy"),
    );
    expect(r.stopped).toBe(true);
  });

  test("an unscrapeable pane is null — 'unknown', never a claimed success", async () => {
    const r = await interruptAndConfirm("w:0.0", deps([null], () => false));
    expect(r).toEqual({ sent: true, stopped: null });
  });

  test("send-keys failing is reported as not sent", async () => {
    const d = deps(["x"], () => false);
    d.escape = () => false;
    const r = await interruptAndConfirm("w:0.0", d);
    expect(r).toEqual({ sent: false, stopped: false });
  });

  // Bug 010: a lone ESC can sit buffered in the TUI's input parser (it can't
  // tell it from the start of an escape sequence), so one send-keys can
  // silently do nothing — the same failure dismissPrompt retries around.
  test("a pane that stays busy gets Escape re-sent on a slow cadence", async () => {
    const d = deps(["✻ Crunched for 2m 4s"], () => true);
    let escapes = 0;
    d.escape = () => { escapes++; return true; };
    const r = await interruptAndConfirm("w:0.0", d);
    expect(r).toEqual({ sent: true, stopped: false });
    // 5s window, re-send each 1.5s of continued busy: initial + 3 retries.
    expect(escapes).toBe(4);
  });

  test("an idle composer never receives a second Escape", async () => {
    // A second Esc on an idle composer opens rewind/backtrack — the retry is
    // gated on the pane still reading busy.
    const d = deps(["busy", "done"], (p) => p === "busy");
    let escapes = 0;
    d.escape = () => { escapes++; return true; };
    const r = await interruptAndConfirm("w:0.0", d);
    expect(r.stopped).toBe(true);
    expect(escapes).toBe(1);
  });

  test("a re-send that fails mid-window reports unknown, not success", async () => {
    const d = deps(["busy"], () => true);
    let escapes = 0;
    d.escape = () => { escapes++; return escapes === 1; };
    const r = await interruptAndConfirm("w:0.0", d);
    expect(r).toEqual({ sent: true, stopped: null });
  });
});
