// The ONE global session pump. Replaces the per-SSE-connection pump loops in
// /api/live/stream: instead of every connection tailing transcripts and
// scraping panes with private delta maps (CPU ∝ connections × sessions, and
// all delta state lost on disconnect), this single loop observes every session
// THIS HOST EXECUTES and appends state CHANGES to the journal. /api/events
// readers are then just journal cursors — connecting, disconnecting and
// reconnecting them costs nothing and loses nothing.
//
// Cross-host rule (transcripts are synced between hosts): a host journals only
// sessions it executes. Concretely — when a session APPEARS locally mid-pump
// (created here, or transferred here), its tail offset starts at the file's
// CURRENT size, never at a stored offset: any earlier content was either
// already journaled by this host in a previous run (server restart case,
// handled by trusting pump_state only for sessions alive at pump boot) or was
// executed and journaled by the other host (transfer case — replaying it here
// would double-deliver).

import { Journal, PumpDeltas } from "./journal.ts";
import { listSessions, resolveTranscript, normalizeLineMessages } from "./sessions.ts";
import type { SessionMsg } from "./sessions.ts";
import { capturePaneAsync, isBusy } from "./tmux.ts";
import { listQueue, reconcileQueued } from "./sendq.ts";
import { findEntryByAnyId as findAisdkEntryByAnyId } from "./aisdk-registry.ts";
import { codexDelegationSessionIds, notePaneBusy } from "./activity.ts";
import { forgetTurnState } from "./turn-state.ts";
import { forgetHookState } from "./hook-state.ts";
import { resolveBusy, sessionTurnState } from "./session-state.ts";
import { statSync } from "node:fs";
import {
  BrowserFrameExtractor,
  type BrowserFrameStore,
  publishBrowserFrame,
} from "./browser-preview.ts";

const MSG_TICK_MS = 700;
const POLL_TICK_MS = 1000;
// Same semantics as the old per-connection loop: a pane-less bare-CLI session
// counts as busy while its transcript was written within this window.
const BARE_BUSY_WINDOW_MS = 4000;

/**
 * How long one session's work in a sweep may take before the sweep stops waiting
 * on it and moves to the next session.
 *
 * A whole sweep of 37 sessions measures ~560ms end to end (pane scrape 4ms,
 * `sessionTurnState` <1ms, prompt resolve 1ms each), so 15s is three orders of
 * magnitude past normal — it fires only for work that is genuinely wedged, never
 * for work that is merely slow on a loaded host.
 */
const STEP_TIMEOUT_MS = 15_000;

/** A sweep slower than this is logged. Not fatal — the next one still runs. */
const SWEEP_WARN_MS = 10_000;

/**
 * Stop waiting on `p` after `ms`, reporting which happened.
 *
 * The underlying work is NOT cancelled — there is no cancellation to reach into
 * a `tmux` spawn or a file read. `StepRunner` is what keeps an abandoned step
 * from being re-entered, so the abandoned promise settles (or doesn't) alone
 * instead of accumulating a new copy every sweep.
 */
export function settleWithin<T>(
  p: Promise<T>,
  ms: number,
  clock: { setTimeout: typeof setTimeout; clearTimeout: typeof clearTimeout } = globalThis,
): Promise<{ ok: true; value: T } | { ok: false }> {
  return new Promise((resolve) => {
    const timer = clock.setTimeout(() => resolve({ ok: false }), ms);
    p.then(
      (value) => {
        clock.clearTimeout(timer);
        resolve({ ok: true, value });
      },
      () => {
        clock.clearTimeout(timer);
        resolve({ ok: false });
      },
    );
  });
}

/**
 * Runs one keyed step per sweep with a timeout, and refuses to start a second
 * copy while the first is still outstanding.
 *
 * WHY THE IN-FLIGHT GUARD. A timeout alone would turn one wedged session into a
 * spawn storm: every sweep abandons its predecessor and starts another, on the
 * single Bun event loop, forever. Skipping instead means a wedged session costs
 * exactly one outstanding promise and the other 36 keep reporting — which is the
 * whole point, since the failure this replaces froze ALL of them.
 */
export class StepRunner {
  private inFlight = new Map<string, Promise<void>>();

  constructor(
    private readonly name: string,
    private readonly timeoutMs: number,
    private readonly log: (message: string) => void,
    private readonly clock: {
      setTimeout: typeof setTimeout;
      clearTimeout: typeof clearTimeout;
    } = globalThis,
  ) {}

  /** True when this key was skipped or abandoned rather than completed. */
  async run(key: string, fn: () => Promise<void>): Promise<boolean> {
    if (this.inFlight.has(key)) return true; // still wedged from an earlier sweep
    // `tracked` never rejects, so an abandoned step cannot surface later as an
    // unhandled rejection and take the process down with it.
    const tracked = fn().then(
      () => {
        this.inFlight.delete(key);
      },
      (err) => {
        this.inFlight.delete(key);
        this.log(`[pump] ${this.name} ${key} threw: ${err}`);
      },
    );
    this.inFlight.set(key, tracked);
    const settled = await settleWithin(tracked, this.timeoutMs, this.clock);
    if (!settled.ok) {
      this.log(`[pump] ${this.name} ${key} exceeded ${this.timeoutMs}ms — moving on`);
      return true;
    }
    return false;
  }

  /** Keys with an outstanding call. Exported state for tests and logging. */
  stalledKeys(): string[] {
    return Array.from(this.inFlight.keys());
  }

  forget(key: string): void {
    this.inFlight.delete(key);
  }
}

/**
 * A self-scheduling loop whose next tick is armed in a `finally`.
 *
 * THIS IS THE BUG THIS FILE SHIPPED. The loops used to re-arm their timer as the
 * last statement of the body:
 *
 *     const pollLoop = async () => {
 *       await refreshWatchSet();          // not inside the per-session try/catch
 *       for (const w of watched.values()) { try { … } catch {} }
 *       pollTimer = setTimeout(pollLoop, POLL_TICK_MS);
 *     };
 *
 * so one rejection out of `refreshWatchSet`, or one promise in the body that
 * never settled, killed the loop permanently — silently, with no log line and no
 * supervision. On 2026-08-06 the poll loop stopped at 14:04:55 and nothing
 * noticed for 70 minutes: message tailing is a separate loop and kept running, so
 * the pump looked alive while every `busy`/`prompt` value froze at its last
 * value. Because the journal only carries CHANGES and clients LATCH what they
 * receive, two codex sessions that were mid-turn at that instant rendered
 * "Running" forever. See `.claude/diagnosis-codex-stuck-running-20260806.md`.
 *
 * The invariant now: the timer is re-armed unless the pump was actually stopped.
 */
export function startSupervisedLoop(opts: {
  name: string;
  intervalMs: number;
  /** Slower than this and the sweep is logged. */
  warnMs?: number;
  isStopped: () => boolean;
  body: () => Promise<void>;
  log?: (message: string) => void;
  clock?: { setTimeout: typeof setTimeout; clearTimeout: typeof clearTimeout };
  now?: () => number;
}): () => void {
  const clock = opts.clock ?? globalThis;
  const now = opts.now ?? Date.now;
  const log = opts.log ?? ((m: string) => console.log(m));
  let timer: ReturnType<typeof setTimeout> | null = null;
  let cancelled = false;

  const tick = async () => {
    if (cancelled || opts.isStopped()) return;
    const startedAt = now();
    try {
      await opts.body();
    } catch (err) {
      // A throw here used to be fatal to the loop. Now it costs one sweep.
      log(`[pump] ${opts.name} sweep threw: ${err}`);
    } finally {
      const took = now() - startedAt;
      if (opts.warnMs != null && took > opts.warnMs) {
        log(`[pump] ${opts.name} sweep took ${took}ms`);
      }
      if (!cancelled && !opts.isStopped()) {
        timer = clock.setTimeout(tick, opts.intervalMs);
      }
    }
  };

  timer = clock.setTimeout(tick, opts.intervalMs);
  return () => {
    cancelled = true;
    if (timer) clock.clearTimeout(timer);
  };
}

export type PumpDeps = {
  /** serve.ts's resolveSessionPrompt — structured transcript prompt, else pane scrape. */
  resolvePrompt: (tp: string | null, pane: string | null) => Promise<unknown>;
  browserFrames?: BrowserFrameStore;
};

type Watched = {
  sid: string;
  tp: string;
  target: string | null;
  buf: string; // partial trailing line between ticks
  frameExtractor: BrowserFrameExtractor;
};

// Set while a pump is running: re-scrape ONE session right now instead of
// waiting up to POLL_TICK_MS for the next sweep.
//
// A confirmed send is the case that matters. The keystrokes have landed and the
// pane is already busy, but the client cannot know that until the pump next
// looks — so "I sent it" and "it is running" were separated by up to a second of
// nothing, on top of the ~700ms the send itself takes. Measured before this:
// delivered at 741ms, first busy event over SSE at 1486ms.
//
// This re-scrapes rather than fabricating a `busy: true` event: the pane is the
// authority, so a nudge that arrives a beat early reports the truth instead of
// asserting something the next tick would contradict.
let nudgeOne: ((sid: string) => void) | null = null;

export function nudgeJournalPump(sid: string): void {
  nudgeOne?.(sid);
}

/**
 * Journal the state a vanished session leaves behind.
 *
 * A session that disappears — pane killed, process gone, transferred to the
 * other host — otherwise leaves `busy: true` as the last thing any client ever
 * heard about it. Clients LATCH these values: `busy[sid]` is only overwritten by
 * a newer event, and no newer event is ever coming. That stranded `true` is why
 * an ended session kept rendering as "running" on the Live Activity forever.
 *
 * Must be called BEFORE `deltas.forget(sid)`: forget clears the last-value maps,
 * after which the change checks report "no change" and emit nothing.
 *
 * Retracts only what was actually asserted: a session already idle when it
 * disappeared costs no events, and one with no baseline at all (added to the
 * watch set but gone before its first poll) emits nothing rather than a phantom
 * `busy: false` for a state no client was ever told about.
 */
export function appendDisappearanceRetractions(
  j: Pick<Journal, "append">,
  deltas: PumpDeltas,
  sid: string,
): void {
  if (deltas.lastBusyValue(sid) === true && deltas.busyChanged(sid, false)) {
    j.append(sid, "busy", { sid, busy: false });
  }
  if (deltas.hadPrompt(sid) && deltas.promptChanged(sid, null)) {
    j.append(sid, "prompt", { sid, prompt: null });
  }
}

export function startJournalPump(j: Journal, deps: PumpDeps): () => void {
  const deltas = new PumpDeltas();
  const watched = new Map<string, Watched>();
  let bootSids: Set<string> | null = null; // sessions alive at pump boot: may trust pump_state
  let stopped = false;

  // One per loop, so a session wedged in `tailOne` can still be polled and vice
  // versa. Declared here rather than beside the loops so `refreshWatchSet` can
  // drop a departed session's entry along with everything else it forgets.
  const tailStep = new StepRunner("tail", STEP_TIMEOUT_MS, (m) => console.log(m));
  const pollStep = new StepRunner("poll", STEP_TIMEOUT_MS, (m) => console.log(m));

  const initialOffset = (sid: string, tp: string): number => {
    let size = 0;
    try {
      size = Bun.file(tp).size;
    } catch {}
    if (bootSids?.has(sid)) {
      // Alive across our restart: the stored offset lets us journal whatever
      // was appended during the restart gap (bounded, it was ours to deliver).
      const stored = j.getOffset(sid);
      if (stored != null && stored <= size) return stored;
    }
    return size; // new-to-us session: start at the end, journal only what's next
  };

  const refreshWatchSet = async () => {
    let sessions;
    try {
      sessions = await listSessions();
    } catch {
      return; // transient enumeration failure — keep the current set
    }
    const seen = new Set<string>();
    for (const s of sessions) {
      const sid = s.sessionId;
      if (!sid) continue;
      seen.add(sid);
      const existing = watched.get(sid);
      if (existing) {
        existing.target = s.tmuxTarget ?? null; // pane can (re)appear
        continue;
      }
      const tp = await resolveTranscript(sid).catch(() => null);
      if (!tp) continue;
      j.setOffset(sid, initialOffset(sid, tp));
      watched.set(sid, {
        sid,
        tp,
        target: s.tmuxTarget ?? null,
        buf: "",
        frameExtractor: new BrowserFrameExtractor(),
      });
    }
    if (bootSids) bootSids = null; // boot trust window is one enumeration only
    for (const sid of Array.from(watched.keys())) {
      if (!seen.has(sid)) {
        appendDisappearanceRetractions(j, deltas, sid);
        forgetTurnState(watched.get(sid)!.tp);
        forgetHookState(sid, watched.get(sid)!.tp);
        watched.delete(sid);
        deltas.forget(sid); // if it comes back, it re-states its baseline
        tailStep.forget(sid);
        pollStep.forget(sid);
      }
    }
  };

  const tailOne = async (w: Watched) => {
    try {
      const f = Bun.file(w.tp);
      const size = f.size;
      let offset = j.getOffset(w.sid) ?? size;
      if (size < offset) {
        // Truncated/rewritten. Do NOT restart at 0 — that would re-journal the
        // whole transcript and double-deliver to every cursor forever. Skip to
        // the new end; the client's REST history fetch covers the gap.
        j.setOffset(w.sid, size);
        w.buf = "";
        return;
      }
      if (size === offset) return;
      const chunk = await f.slice(offset, size).text();
      let buf = w.buf + chunk;
      const lines = buf.split("\n");
      w.buf = lines.pop() ?? "";
      for (const l of lines) {
        if (!l) continue;
        const frame = w.frameExtractor.consume(l);
        if (frame && deps.browserFrames) publishBrowserFrame(j, deps.browserFrames, w.sid, frame);
        for (const m of normalizeLineMessages(l)) {
          j.append(w.sid, "msg", { sid: w.sid, m });
        }
      }
      j.setOffset(w.sid, size);
    } catch {}
  };

  const pollOne = async (w: Watched) => {
    try {
      const delegated = codexDelegationSessionIds().has(w.sid);
      if (!w.target) {
        // Pane-less: registry busy (aisdk), else transcript-freshness heuristic.
        const entry = findAisdkEntryByAnyId(w.sid);
        let baseBusy: boolean;
        if (entry) baseBusy = entry.busy;
        else {
          try {
            baseBusy = Date.now() - statSync(w.tp).mtimeMs < BARE_BUSY_WINDOW_MS;
          } catch {
            baseBusy = false;
          }
        }
        const busy = baseBusy || delegated;
        if (deltas.busyChanged(w.sid, busy)) j.append(w.sid, "busy", { sid: w.sid, busy });
        return;
      }
      const pane = await capturePaneAsync(w.target);
      const prompt = (await deps.resolvePrompt(w.tp, pane)) ?? null;
      if (deltas.promptChanged(w.sid, prompt))
        j.append(w.sid, "prompt", { sid: w.sid, prompt });
      const paneBusy = pane ? isBusy(pane) : false;
      notePaneBusy(w.sid, paneBusy); // still the REST fallback when both layers abstain
      // Ask the agent (hooks) and its transcript, in that order of certainty but
      // arbitrated by recency — see `session-state.ts` for why rank alone would
      // latch busy on every steering send. The pane only backstops both. We are
      // in the pane-backed branch, so the process is known to exist; these layers
      // answer "is a turn in flight", not "is this alive".
      const verdict = await sessionTurnState({ sessionId: w.sid, transcriptPath: w.tp });
      const busy = resolveBusy({ verdict, paneBusy, delegated });
      if (deltas.busyChanged(w.sid, busy)) j.append(w.sid, "busy", { sid: w.sid, busy });
    } catch {}
  };

  const queueOne = (w: Watched) => {
    const queue = listQueue(w.sid);
    if (deltas.queueChanged(w.sid, queue)) j.append(w.sid, "queue", { sid: w.sid, queue });
  };

  let stop: () => void = () => {
    stopped = true;
  };

  // Boot: know which sessions may trust their stored offsets, then start loops.
  void (async () => {
    try {
      const initial = await listSessions();
      bootSids = new Set(initial.map((s) => s.sessionId).filter((x): x is string => !!x));
    } catch {
      bootSids = new Set();
    }
    await refreshWatchSet();

    // BACKPRESSURE IS LOAD-BEARING. The first version fired pollOne for every
    // session in parallel on a fixed interval: on a machine where one tick's
    // pane-scrapes take >1s, the next tick stacks MORE spawns on top of the
    // still-running ones, unboundedly, until the single event loop drowns —
    // this wedged the Air's server hard (TCP accepted via kernel backlog, HTTP
    // never answered, for minutes). Serialized self-scheduling loops instead:
    // a slow machine degrades to a slower cadence, never to a pileup.
    //
    // `startSupervisedLoop` + `StepRunner` add the other half: serialization must
    // not mean that one wedged session stops the sweep, and a sweep that throws
    // must not stop the loop. See `startSupervisedLoop` for the incident.
    const stopMsgLoop = startSupervisedLoop({
      name: "msg",
      intervalMs: MSG_TICK_MS,
      warnMs: SWEEP_WARN_MS,
      isStopped: () => stopped,
      body: async () => {
        for (const w of watched.values()) {
          if (stopped) return;
          await tailStep.run(w.sid, () => tailOne(w));
        }
      },
    });

    const stopPollLoop = startSupervisedLoop({
      name: "poll",
      intervalMs: POLL_TICK_MS,
      warnMs: SWEEP_WARN_MS,
      isStopped: () => stopped,
      body: async () => {
        // `refreshWatchSet` is the one step whose failure used to kill the loop:
        // it sits before the per-session try/catch, so a throw from `j.setOffset`
        // or `appendDisappearanceRetractions` escaped everything. It is now inside
        // the supervised body AND bounded, because a hang here starves every
        // session at once rather than just one.
        await settleWithin(refreshWatchSet(), STEP_TIMEOUT_MS);
        for (const w of watched.values()) {
          if (stopped) return;
          await pollStep.run(w.sid, async () => {
            await pollOne(w);
            queueOne(w);
            if (await reconcileQueued(w.sid)) queueOne(w);
          });
        }
      },
    });

    // Coalesced per-session nudge. `inFlight` keeps a burst of sends from
    // stacking scrapes of the same pane on the single event loop.
    const inFlight = new Set<string>();
    nudgeOne = (sid: string) => {
      if (stopped || inFlight.has(sid)) return;
      const w = watched.get(sid);
      if (!w) return;
      inFlight.add(sid);
      void (async () => {
        try {
          await pollOne(w);
          queueOne(w);
        } catch {} finally {
          inFlight.delete(sid);
        }
      })();
    };

    const pruneTimer = setInterval(() => {
      if (!stopped) j.prune();
    }, 60 * 60 * 1000);
    j.prune();

    stop = () => {
      stopped = true;
      stopMsgLoop();
      stopPollLoop();
      clearInterval(pruneTimer);
    };
    if (stopped) stop(); // stop() was requested before boot finished
  })();

  return () => {
    nudgeOne = null;
    stop();
  };
}
