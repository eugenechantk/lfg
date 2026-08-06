// Tombstones for just-closed sessions, so removal from the session list is
// deterministic. /close only sends the session's `claude`/`codex` process a
// SIGHUP (via tmux kill-session/kill-pane); the process takes a beat to actually
// exit, so the next listSessions() pgrep can still see it and the card flickers
// back for a poll or two. We record the closed pid here the instant we kill it;
// listSessions() filters tombstoned pids out, so a closed session leaves the
// list immediately and never reappears.
//
// The tombstone self-prunes after a short TTL — by then a SIGHUP'd process is
// long gone, so the entry has done its job. The TTL also means a closed session
// that somehow refuses to die *does* resurface (honest: it really is still
// running), and a much-later recycled pid is never wrongly suppressed.
const TTL_MS = 60_000;
const closed = new Map<number, number>(); // pid -> closedAt (ms)

// Record a pid we just killed. Pruning expired entries on each write keeps the
// map from accumulating tombstones for pids that died long ago.
export function markClosed(pid: number): void {
  if (!pid || pid <= 0) return;
  const now = Date.now();
  for (const [p, at] of closed) if (now - at > TTL_MS) closed.delete(p);
  closed.set(pid, now);
}

// True while a just-closed pid is still inside its tombstone window. Expired
// entries are dropped so the check stays self-healing.
export function isClosing(pid: number): boolean {
  const at = closed.get(pid);
  if (at == null) return false;
  if (Date.now() - at > TTL_MS) {
    closed.delete(pid);
    return false;
  }
  return true;
}

// ---- closing a session for real ----
//
// `/close` used to resolve ONE session row (`listSessions().find(…)`), kill its
// pane, and report success from tmux's exit code. Both halves were wrong:
//
//   1. A sessionId can back SEVERAL panes. `resolvePaneOwners` dedupes the
//      one-pane-many-pids direction; nothing handled one-id-many-panes, which is
//      what a transcript resumed into a second pane produces. Killing the first
//      match left the other alive, so the row reappeared on the next poll and
//      "End session" looked like it did nothing.
//   2. `tmux kill-pane` exits 0 whenever the pane existed. It says nothing about
//      whether the process died — and a wedged agent is exactly the case where a
//      SIGHUP may not be enough.
//
// So: kill every target, then VERIFY, then escalate. See
// `.claude/diagnosis-stop-close-noop-20260806.md`.

/** One pane backing the session being closed. */
export type CloseTarget = {
  pid: number;
  tmuxTarget: string | null;
  tmuxName: string | null;
  /** lfg started this one: it owns its whole tmux session, so kill the session. */
  managed: boolean;
};

export type CloseOutcome = {
  pid: number;
  target: string | null;
  /** The process is gone. The only field that means the close worked. */
  killed: boolean;
  /** SIGHUP left it alive, so we sent SIGKILL. */
  escalated: boolean;
};

export type CloseDeps = {
  killSession: (name: string) => boolean;
  killPane: (target: string) => boolean;
  alive: (pid: number) => boolean;
  kill9: (pid: number) => void;
  /** Injected so tests don't sleep. */
  wait: (ms: number) => Promise<void>;
};

/**
 * How long a SIGHUP'd agent gets to exit on its own before we escalate.
 *
 * MEASURED, not guessed: a healthy `claude` takes ~1150ms to exit after
 * `tmux kill-pane` (timed on this host, 2026-08-06). An earlier 700ms value
 * escalated on every single close — including the clean ones — which would have
 * SIGKILLed agents mid-shutdown and cost them their `SessionEnd` hook, the write
 * that puts `state: "ended"` in the lease and feeds the `closed` derivation.
 * 2.5s leaves headroom for a loaded machine while still bounding a wedged agent.
 */
const REAP_GRACE_MS = 2_500;
/** Poll interval while waiting for exit, so a clean close doesn't pay the grace. */
const REAP_POLL_MS = 100;

export const defaultCloseDeps: Pick<CloseDeps, "alive" | "kill9" | "wait"> = {
  alive: (pid) => {
    if (!Number.isInteger(pid) || pid <= 0) return false;
    try {
      process.kill(pid, 0);
      return true;
    } catch {
      return false;
    }
  },
  kill9: (pid) => {
    try {
      process.kill(pid, "SIGKILL");
    } catch {}
  },
  wait: (ms) => new Promise((r) => setTimeout(r, ms)),
};

/**
 * Close every pane backing a session and report, per target, whether the process
 * actually died.
 *
 * Tombstoning is the caller's job (it needs `markClosed` regardless of outcome —
 * a pid that survives the kill must not linger in the list while we escalate).
 */
export async function closeAll(
  targets: CloseTarget[],
  deps: CloseDeps,
): Promise<CloseOutcome[]> {
  const out: CloseOutcome[] = [];
  for (const t of targets) {
    // A session lfg started owns its whole tmux session (one managed agent, no
    // sibling panes). An adopted one may share a tmux session with the user's
    // other panes, so only its own pane may go.
    //
    // A target may legitimately have NO usable tmux handle: `resolvePaneOwners`
    // nulls `tmuxTarget` on every row that loses a pane collision, and those are
    // exactly the duplicate rows this function exists to sweep. Such a target
    // simply skips the tmux step and is reaped by pid in the verify pass below —
    // closing must not depend on lfg having guessed the right pane.
    if (t.managed && t.tmuxName) deps.killSession(t.tmuxName);
    else if (t.tmuxTarget) deps.killPane(t.tmuxTarget);
    out.push({
      pid: t.pid,
      target: t.tmuxTarget ?? t.tmuxName,
      killed: false,
      escalated: false,
    });
  }

  // Verify as a shared second pass rather than per-target, so closing four panes
  // costs one grace period, not four. Polling (rather than one flat sleep) means
  // a clean exit is noticed as soon as it happens.
  const reap = async (grace: number) => {
    for (let waited = 0; ; waited += REAP_POLL_MS) {
      for (const o of out) if (!o.killed && !deps.alive(o.pid)) o.killed = true;
      if (out.every((o) => o.killed) || waited >= grace) return;
      await deps.wait(REAP_POLL_MS);
    }
  };

  await reap(REAP_GRACE_MS);
  // Whatever is still alive ignored the hangup — the wedged-agent case this whole
  // fix exists for. SIGKILL, then re-check: a pid we cannot reap is reported as
  // NOT killed, never assumed dead.
  const survivors = out.filter((o) => !o.killed);
  if (survivors.length) {
    for (const o of survivors) {
      deps.kill9(o.pid);
      o.escalated = true;
    }
    // SIGKILL is not negotiable, so this only needs long enough for the kernel to
    // reap — not another full grace period.
    await reap(REAP_POLL_MS * 5);
  }
  return out;
}

// ---- interrupting for real ----
//
// `/interrupt` used to be `send-keys Escape` and `return json({ ok: true })`,
// where the `ok` came from tmux's exit code — which is 0 whenever the pane
// exists. It said nothing about whether the agent read the key, so Stop reported
// success against a wedged pane that never moved. Confirm against the pane
// instead: the busy meter clearing is the observable effect of a turn ending.

export type InterruptDeps = {
  escape: (target: string) => boolean;
  capture: (target: string) => Promise<string | null>;
  busy: (pane: string) => boolean;
  wait: (ms: number) => Promise<void>;
};

/** Total time the pane gets to drop its busy meter before we report failure. */
const CONFIRM_WINDOW_MS = 1_500;
const CONFIRM_POLL_MS = 250;

export type InterruptOutcome = {
  /** The Escape was transmitted (pane existed). */
  sent: boolean;
  /**
   * The pane stopped reporting busy inside the window. `false` means the key
   * landed and nothing happened — a wedged agent, or a turn that ignores it.
   * `null` means the pane could not be scraped, so we cannot say either way.
   */
  stopped: boolean | null;
};

export async function interruptAndConfirm(
  target: string,
  deps: InterruptDeps,
): Promise<InterruptOutcome> {
  if (!deps.escape(target)) return { sent: false, stopped: false };
  // Poll rather than wait-then-check: a responsive agent clears in well under the
  // window, and Stop should feel immediate.
  for (let waited = 0; waited < CONFIRM_WINDOW_MS; waited += CONFIRM_POLL_MS) {
    await deps.wait(CONFIRM_POLL_MS);
    const pane = await deps.capture(target);
    if (pane == null) return { sent: true, stopped: null };
    if (!deps.busy(pane)) return { sent: true, stopped: true };
  }
  return { sent: true, stopped: false };
}
