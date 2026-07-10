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
import { statSync } from "node:fs";

const MSG_TICK_MS = 700;
const POLL_TICK_MS = 1000;
// Same semantics as the old per-connection loop: a pane-less bare-CLI session
// counts as busy while its transcript was written within this window.
const BARE_BUSY_WINDOW_MS = 4000;

export type PumpDeps = {
  /** serve.ts's msgWithHtml — attaches rendered markdown to prose messages. */
  renderMsg: (m: SessionMsg) => unknown;
  /** serve.ts's resolveSessionPrompt — structured transcript prompt, else pane scrape. */
  resolvePrompt: (tp: string | null, pane: string | null) => Promise<unknown>;
};

type Watched = {
  sid: string;
  tp: string;
  target: string | null;
  buf: string; // partial trailing line between ticks
};

export function startJournalPump(j: Journal, deps: PumpDeps): () => void {
  const deltas = new PumpDeltas();
  const watched = new Map<string, Watched>();
  let bootSids: Set<string> | null = null; // sessions alive at pump boot: may trust pump_state
  let stopped = false;

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
      watched.set(sid, { sid, tp, target: s.tmuxTarget ?? null, buf: "" });
    }
    if (bootSids) bootSids = null; // boot trust window is one enumeration only
    for (const sid of Array.from(watched.keys())) {
      if (!seen.has(sid)) {
        watched.delete(sid);
        deltas.forget(sid); // if it comes back, it re-states its baseline
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
        for (const m of normalizeLineMessages(l)) {
          j.append(w.sid, "msg", { sid: w.sid, m: deps.renderMsg(m) });
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
      notePaneBusy(w.sid, paneBusy);
      const busy = paneBusy || delegated;
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
    let msgTimer: ReturnType<typeof setTimeout> | null = null;
    const msgLoop = async () => {
      if (stopped) return;
      for (const w of watched.values()) {
        if (stopped) return;
        await tailOne(w);
      }
      msgTimer = setTimeout(msgLoop, MSG_TICK_MS);
    };
    msgTimer = setTimeout(msgLoop, MSG_TICK_MS);

    let pollTimer: ReturnType<typeof setTimeout> | null = null;
    const pollLoop = async () => {
      if (stopped) return;
      await refreshWatchSet();
      for (const w of watched.values()) {
        if (stopped) return;
        try {
          await pollOne(w);
          queueOne(w);
          if (await reconcileQueued(w.sid)) queueOne(w);
        } catch {}
      }
      pollTimer = setTimeout(pollLoop, POLL_TICK_MS);
    };
    pollTimer = setTimeout(pollLoop, POLL_TICK_MS);
    const pruneTimer = setInterval(() => {
      if (!stopped) j.prune();
    }, 60 * 60 * 1000);
    j.prune();

    stop = () => {
      stopped = true;
      if (msgTimer) clearTimeout(msgTimer);
      if (pollTimer) clearTimeout(pollTimer);
      clearInterval(pruneTimer);
    };
    if (stopped) stop(); // stop() was requested before boot finished
  })();

  return () => stop();
}
