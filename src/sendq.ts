// Confirmed-delivery outbound message queue, one per Claude Code session.
//
// Driving an interactive TUI over tmux send-keys is racy: a fixed sleep before
// Enter loses messages when the TUI is busy, two quick sends interleave in the
// same input box, and a dropped Enter silently strands text in the composer
// while the caller is told "ok". This module turns send-and-pray into
// send-confirm-retry: it serializes one delivery at a time per session, types
// then waits until our text actually appears in the composer, presses Enter,
// then waits until the text *leaves* the box (the rendering-agnostic signal
// that Claude accepted it). It retries a stranded Enter, clears+retypes a
// dropped type, and only marks a message failed when it truly never landed.

import { randomBytes } from "node:crypto";
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import {
  capturePane,
  isBusy,
  parsePrompt,
  questionSelectorOpen,
  inputBoxText,
  tmuxType,
  tmuxPaste,
  tmuxEnter,
  tmuxClearInput,
  tmuxInterrupt,
  feedbackPromptOpen,
  tmuxDismissFeedback,
} from "./tmux.ts";
import { listSessions, resolveTranscript, recentMessages } from "./sessions.ts";
import { PATHS } from "./config.ts";

export type QueuedMsg = {
  id: string;
  text: string;
  // pending: held in lfg's own queue — either behind an earlier send, or because
  // the agent is busy (hold-in-lfg: we do NOT push into Claude's native queue
  // while it's mid-turn; we deliver when it goes idle). sending: actively being
  // typed + confirmed right now. delivered: surfaced as a real user turn.
  // queued: legacy/edge — the agent flipped busy mid-delivery so the draft landed
  // in Claude's own queue; reconcileQueued promotes or re-drives it. failed:
  // delivery genuinely failed after retries.
  status: "pending" | "sending" | "delivered" | "queued" | "failed";
  error?: string;
  attempts: number;
  createdAt: number;
  updatedAt: number;
  // How many times we've re-driven this message because it landed in Claude's
  // own queue (status "queued") but never surfaced and the agent then went idle
  // (Claude dropped it, or our Enter stranded it as an unsubmitted composer
  // draft). Capped so a message that genuinely can't land eventually fails
  // instead of looping. Optional/back-compat: absent === 0.
  redeliveries?: number;
};

type SessionQueue = { msgs: QueuedMsg[]; running: boolean };

const queues = new Map<string, SessionQueue>();

// Keep the per-session list from growing unbounded; terminal rows older than
// this many are pruned on each enqueue.
const KEEP_TERMINAL = 12;

function q(sessionId: string): SessionQueue {
  let s = queues.get(sessionId);
  if (!s) {
    s = { msgs: [], running: false };
    queues.set(sessionId, s);
  }
  return s;
}

export function listQueue(sessionId: string): QueuedMsg[] {
  return queues.get(sessionId)?.msgs ?? [];
}

export function getMessage(sessionId: string, id: string): QueuedMsg | null {
  return queues.get(sessionId)?.msgs.find((m) => m.id === id) ?? null;
}

export function enqueueMessage(sessionId: string, text: string): QueuedMsg {
  const s = q(sessionId);
  const now = Date.now();
  const msg: QueuedMsg = {
    id: randomBytes(8).toString("hex"),
    text,
    status: "pending",
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  };
  s.msgs.push(msg);
  pruneTerminal(s);
  kick(sessionId);
  return msg;
}

export function retryMessage(sessionId: string, id: string): QueuedMsg | null {
  const s = queues.get(sessionId);
  const msg = s?.msgs.find((m) => m.id === id);
  if (!s || !msg) return null;
  if (msg.status !== "failed") return msg;
  msg.status = "pending";
  msg.error = undefined;
  msg.attempts = 0;
  msg.updatedAt = Date.now();
  kick(sessionId);
  return msg;
}

// Drop messages the user no longer needs to see — everything that's reached a
// terminal state (delivered/queued/failed). In-flight messages (pending/
// sending) stay so a clear never silently abandons a send mid-delivery.
export function clearResolved(sessionId: string): number {
  const s = queues.get(sessionId);
  if (!s) return 0;
  const before = s.msgs.length;
  s.msgs = s.msgs.filter((m) => m.status === "pending" || m.status === "sending");
  return before - s.msgs.length;
}

function pruneTerminal(s: SessionQueue) {
  const terminal = s.msgs.filter(
    (m) => m.status === "delivered" || m.status === "queued" || m.status === "failed",
  );
  if (terminal.length <= KEEP_TERMINAL) return;
  const drop = new Set(
    terminal
      .sort((a, b) => a.updatedAt - b.updatedAt)
      .slice(0, terminal.length - KEEP_TERMINAL),
  );
  s.msgs = s.msgs.filter((m) => !drop.has(m));
}

async function sessionTarget(sessionId: string): Promise<string | null> {
  return (await listSessions()).find((s) => s.sessionId === sessionId)?.tmuxTarget ?? null;
}

// hold-in-lfg gate: hold a pending message (don't type it yet) ONLY when the
// agent is confirmably busy. If the pane is gone or unreadable we do NOT hold —
// we let deliver() run so it either delivers or fails fast (a held-forever
// message would be worse than a clean failure). Idle ⇒ deliver now.
async function agentBusy(sessionId: string): Promise<boolean> {
  const target = await sessionTarget(sessionId);
  if (!target) return false;
  const pane = capturePane(target);
  if (pane == null) return false;
  return isBusy(pane);
}

function kick(sessionId: string) {
  const s = q(sessionId);
  if (s.running) return;
  if (!s.msgs.some((m) => m.status === "pending")) return;
  s.running = true;
  (async () => {
    try {
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const next = s.msgs.find((m) => m.status === "pending");
        if (!next) break;
        // hold-in-lfg: while the agent is mid-turn, leave the message pending in
        // our queue rather than pushing it into Claude's native queue. The pump
        // re-kicks once the agent goes idle. This keeps the message fully under
        // lfg's control so it can be removed/edited/sent-now from the client.
        if (await agentBusy(sessionId)) break;
        next.status = "sending";
        next.updatedAt = Date.now();
        try {
          await deliver(sessionId, next);
        } catch (e) {
          next.status = "failed";
          next.error = e instanceof Error ? e.message : String(e);
        }
        next.updatedAt = Date.now();
      }
    } finally {
      s.running = false;
    }
  })();
}

// Client-independent background pump: the held-in-lfg queue only drains when the
// agent is idle, and a message may be queued while no client SSE stream is open
// (app closed). So a server-owned ticker drives delivery + reconciliation for
// every session with outstanding work, regardless of who's watching. Started
// once from serve.ts at boot.
let pumpTimer: ReturnType<typeof setInterval> | null = null;
export function startQueuePump(intervalMs = 1000): void {
  if (pumpTimer) return;
  pumpTimer = setInterval(() => {
    for (const [sid, s] of queues) {
      if (s.running) continue;
      if (s.msgs.some((m) => m.status === "pending")) kick(sid);
      else if (s.msgs.some((m) => m.status === "queued")) void reconcileQueued(sid);
    }
  }, intervalMs);
}
export function stopQueuePump(): void {
  if (pumpTimer) clearInterval(pumpTimer);
  pumpTimer = null;
}

// Remove a message that hasn't been delivered yet. Because we hold messages in
// lfg's own queue (not Claude's) until the agent is idle, a pending message can
// be yanked cleanly — it was never in Claude. A message that's actively being
// typed ("sending") can't be safely pulled mid-keystroke, and a terminal one is
// nothing to cancel. Returns true if it was removed.
export function removeMessage(sessionId: string, id: string): boolean {
  const s = queues.get(sessionId);
  if (!s) return false;
  const m = s.msgs.find((x) => x.id === id);
  if (!m || m.status === "sending" || m.status === "delivered") return false;
  s.msgs = s.msgs.filter((x) => x.id !== id);
  return true;
}

// "Send now + interrupt": stop the current turn and run this message next. Move
// it to the head of the queue, interrupt the agent (so it idles), and kick — the
// pump/kick delivers it the moment the Escape lands. A message that already
// reached Claude's own queue (status "queued") is run by the interrupt directly.
export async function sendNow(sessionId: string, id: string): Promise<boolean> {
  const s = queues.get(sessionId);
  if (!s) return false;
  const m = s.msgs.find((x) => x.id === id);
  if (!m || (m.status !== "pending" && m.status !== "queued")) return false;
  // promote to the front of the pending order
  s.msgs = s.msgs.filter((x) => x.id !== id);
  s.msgs.unshift(m);
  const target = await sessionTarget(sessionId);
  if (target) tmuxInterrupt(target); // stop the current turn so the agent idles
  kick(sessionId);
  return true;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const norm = (s: string) => s.replace(/\s+/g, " ").trim();

// We match a normalized prefix rather than the whole message: the composer
// wraps long input across lines, so a full-string compare against the capture
// would never match.
const NEEDLE_LEN = 48;

// How long a message may sit "queued" (in Claude's own queue) while the session
// is idle before we re-drive it. A queued message normally surfaces as a
// transcript turn the instant Claude drains its queue, so if the session is idle
// and the message still hasn't surfaced after this grace window, Claude did NOT
// auto-run it — it was dropped (Escape/interrupt, the user edited it away, a
// later turn superseded it) or our Enter stranded it as an unsubmitted composer
// draft. Either way the agent is now ready and the message needs to be (re)sent.
// The grace guards the brief idle blip between deliver() returning and Claude
// auto-running the message (which happens sub-second when it does happen).
const ORPHAN_IDLE_GRACE_MS = 10_000;

// Re-drive an unsurfaced "queued" message at most this many times before giving
// up and failing it, so a message that genuinely can't land doesn't loop forever.
const MAX_REDELIVERIES = 2;

// Whether our pending draft is currently sitting in the composer. For a typed
// (single-line) send that's the needle verbatim; for a pasted (multi-line) send
// Claude collapses the draft to a "[Pasted text +N lines]" chip, so the needle
// never appears — match that marker instead. null = composer not visible.
function composerHoldsInput(target: string, needle: string): boolean | null {
  const box = inputBoxText(target);
  if (box == null) return null;
  const n = norm(box);
  return n.includes(needle) || /pasted text/i.test(n);
}

// Append a delivery failure (reason + a tail of the pane) to data/sendq.log so a
// stuck send is diagnosable after the fact instead of only by catching it live.
function logDeliverFailure(sessionId: string, msg: QueuedMsg, target: string | null): void {
  try {
    mkdirSync(PATHS.data, { recursive: true });
    const tail = target
      ? (capturePane(target) ?? "").split("\n").slice(-16).join("\n")
      : "(no target)";
    appendFileSync(
      join(PATHS.data, "sendq.log"),
      JSON.stringify({
        t: new Date().toISOString(),
        sessionId,
        id: msg.id,
        attempts: msg.attempts,
        error: msg.error,
        text: msg.text.slice(0, 120),
      }) +
        "\n" +
        tail +
        "\n---\n",
    );
  } catch {}
}

async function transcriptUserMatchCount(
  transcriptPath: string | null,
  needle: string,
): Promise<number> {
  if (!transcriptPath) return 0;
  try {
    const msgs = await recentMessages(transcriptPath, 120);
    return msgs.filter(
      (m) => m.role === "user" && m.kind === "text" && norm(m.text).includes(needle),
    ).length;
  } catch {
    return 0;
  }
}

// Pure core of reconcileQueued, split out so the promote/redeliver logic is unit
// testable without tmux/transcript IO. Mutates `msgs` in place and returns
// { changed, kick }: `changed` if any status moved (caller re-emits), `kick` if
// any message was reset to "pending" (caller must re-run the delivery loop).
//
// Three transitions for a "queued" message (one that left the composer into
// Claude's own queue while busy):
//   - surfaced  → "delivered": its text now appears as a real user turn.
//   - unsurfaced + agent idle → "pending" (re-drive): Claude did not auto-run it
//     within the grace window, so it was dropped (Escape/interrupt, edited away,
//     superseded) or our Enter stranded it as an unsubmitted composer draft. The
//     agent is now ready, so re-drive deliver() — it submits the stranded draft
//     or re-types, then confirms via transcript growth. Capped by redeliveries.
//   - re-drive cap exhausted → "failed": surface a Retry instead of looping.
// idleConfirmed is the authority: only an idle Claude has provably drained its
// queue, so a still-"queued" message there is genuinely not going to self-run.
export function reconcileQueuedCore(
  msgs: QueuedMsg[],
  recentUserTexts: string[],
  opts: { idleConfirmed: boolean; now: number; graceMs?: number },
): { changed: boolean; kick: boolean } {
  const grace = opts.graceMs ?? ORPHAN_IDLE_GRACE_MS;
  const normedTurns = recentUserTexts.map(norm);
  let changed = false;
  let kick = false;
  for (const m of msgs) {
    if (m.status !== "queued") continue;
    const needle = norm(m.text).slice(0, NEEDLE_LEN);
    if (normedTurns.some((t) => t.includes(needle))) {
      m.status = "delivered";
      m.updatedAt = opts.now;
      changed = true;
    } else if (opts.idleConfirmed && opts.now - m.updatedAt > grace) {
      if ((m.redeliveries ?? 0) < MAX_REDELIVERIES) {
        // Re-drive on the now-idle agent. Reset attempts so deliver()'s per-call
        // retry budget starts fresh; bump redeliveries to bound the outer loop.
        m.redeliveries = (m.redeliveries ?? 0) + 1;
        m.attempts = 0;
        m.error = undefined;
        m.status = "pending";
        m.updatedAt = opts.now;
        changed = true;
        kick = true;
      } else {
        m.status = "failed";
        m.error = "the agent never picked this up after retries — resend";
        m.updatedAt = opts.now;
        changed = true;
      }
    }
  }
  return { changed, kick };
}

// A "queued" message left the input box while Claude was busy, so it sat in
// Claude's own queue rather than the transcript — deliver() can't wait for it
// to surface without blocking the per-session queue behind a turn that may run
// for minutes. So we reconcile lazily: whenever the UI polls, promote any
// queued message that has since shown up in the transcript to "delivered" (the
// UI then drops it), or — when the agent has gone idle without it surfacing —
// re-drive it so it actually gets picked up now that the agent is ready (see
// reconcileQueuedCore). Returns true if anything changed so the caller re-emits.
export async function reconcileQueued(sessionId: string): Promise<boolean> {
  const s = queues.get(sessionId);
  if (!s) return false;
  const pending = s.msgs.filter((m) => m.status === "queued");
  if (!pending.length) return false;
  const transcriptPath = await resolveTranscript(sessionId);
  if (!transcriptPath) return false;
  let recent;
  try {
    recent = await recentMessages(transcriptPath, 40);
  } catch {
    return false;
  }
  const recentUserTexts = recent
    .filter((r) => r.role === "user" && r.kind === "text")
    .map((r) => r.text);

  // We can only re-drive a queued message once we've confirmed the session is
  // idle — a busy Claude may still be mid-turn with the message legitimately
  // waiting in its queue, so re-driving then would double-send. If we can't read
  // the pane, treat it as not-idle (leave the message queued) rather than risk
  // it. Probe the pane only when there's an aged candidate to re-drive.
  const now = Date.now();
  const hasAged = pending.some((m) => now - m.updatedAt > ORPHAN_IDLE_GRACE_MS);
  let idleConfirmed = false;
  if (hasAged) {
    const target = (await listSessions()).find((x) => x.sessionId === sessionId)?.tmuxTarget;
    const pane = target ? capturePane(target) : null;
    idleConfirmed = pane != null && !isBusy(pane);
  }

  const { changed, kick: needsKick } = reconcileQueuedCore(s.msgs, recentUserTexts, {
    idleConfirmed,
    now,
  });
  // A re-driven message is back to "pending"; run the delivery loop so it's
  // actually (re)submitted to the now-idle agent. kick() no-ops if already busy.
  if (needsKick) kick(sessionId);
  return changed;
}

// If the session-rating overlay is up it swallows Enter, so clear it before we
// type/submit. Returns true if it dismissed one (caller can give the TUI a beat
// to settle).
function clearFeedbackPrompt(target: string): boolean {
  const pane = capturePane(target);
  if (pane && feedbackPromptOpen(pane)) {
    tmuxDismissFeedback(target);
    return true;
  }
  return false;
}

async function deliver(sessionId: string, msg: QueuedMsg): Promise<void> {
  const sess = (await listSessions()).find((s) => s.sessionId === sessionId);
  const target = sess?.tmuxTarget ?? null;
  if (!target) {
    msg.status = "failed";
    msg.error = "session is not in a tmux pane";
    return;
  }
  const transcriptPath = await resolveTranscript(sessionId);
  const needle = norm(msg.text).slice(0, NEEDLE_LEN);
  const transcriptMatchesBefore = await transcriptUserMatchCount(transcriptPath, needle);

  // Clear any session-rating overlay first — it swallows Enter and would
  // otherwise strand every send with "never left the input box".
  if (clearFeedbackPrompt(target)) await sleep(300);

  // "Chat about this": when a selector (permission / plan / question dialog) is
  // open, sending a message means the user chose to type a reply instead of
  // clicking an option. Dismiss the selector (Escape) so the composer is
  // reachable, then fall through to the normal type+submit path. We used to
  // refuse and fail the send ("answer it first"), which dead-ended every
  // chat-instead-of-answer. Up to two Escapes (the first can be dropped by a
  // busy TUI); each is gated on the selector still being open, so we never Esc
  // an idle composer (which would trip the rewind-history overlay).
  //
  // We detect "selector open" two ways: parsePrompt catches permission/plan
  // dialogs (whose active option carries a `❯` cursor), and questionSelectorOpen
  // catches AskUserQuestion dialogs whose active option is highlighted via
  // reverse-video — capture-pane strips the highlight, so NO option line reads
  // as selected and parsePrompt returns null. Gating dismissal on parsePrompt
  // alone skipped the Escape for those question dialogs, fell through to typing
  // into a composer that isn't reachable, and stranded the send with "message
  // never left the input box after retries". The footer-based detector fixes it.
  const selectorOpen = (p: string) => !!parsePrompt(p) || questionSelectorOpen(p);
  for (let attempt = 0; attempt < 2; attempt++) {
    const pane = capturePane(target);
    if (!pane || !selectorOpen(pane)) break;
    tmuxInterrupt(target); // single Escape — cancels the open selector
    let cleared = false;
    for (let i = 0; i < 14; i++) {
      await sleep(150);
      const p = capturePane(target);
      if (!p || !selectorOpen(p)) {
        cleared = true;
        break;
      }
    }
    if (cleared) break;
    if (attempt === 1) {
      msg.status = "failed";
      msg.error = "a prompt/selector wouldn't dismiss — answer it first";
      return;
    }
  }

  const MAX_ATTEMPTS = 3;
  // Multi-line messages must be pasted, not typed: send-keys -l transmits each
  // embedded newline as an Enter, so a typed multi-line message submits/fragments
  // at the first newline and the full text never lands as one draft. Bracketed
  // paste makes the TUI take the newlines as newlines.
  const multiline = /[\r\n]/.test(msg.text);
  while (msg.attempts < MAX_ATTEMPTS) {
    msg.attempts++;
    msg.updatedAt = Date.now();

    // Only (re)insert when our draft isn't already sitting in the box (a previous
    // attempt may have inserted it but failed to submit — reinserting doubles it).
    if (composerHoldsInput(target, needle) !== true) {
      // Wipe any foreign draft first. The composer may already hold text the
      // user (or a stranded earlier send) left there; insertion appends, so
      // without this our message fuses onto it. Ctrl-U on an empty box is a
      // harmless no-op.
      tmuxClearInput(target);
      await sleep(120);
      if (multiline) tmuxPaste(target, msg.text);
      else tmuxType(target, msg.text);
      let settled = false;
      for (let i = 0; i < 20; i++) {
        await sleep(150);
        if (composerHoldsInput(target, needle) === true) {
          settled = true;
          break;
        }
      }
      if (!settled) {
        // Insertion didn't register (cold TUI, lost keys, dropped paste). Clear
        // any partial and loop to retry from scratch.
        tmuxClearInput(target);
        await sleep(200);
        continue;
      }
    }

    // The rating overlay can surface between turns, right as we're about to
    // submit; clear it again so this Enter isn't swallowed.
    if (clearFeedbackPrompt(target)) await sleep(300);

    // Submit, then confirm acceptance. We do NOT require the composer scrape to
    // re-find our needle: a busy Claude swallows the text straight into its own
    // queue and clears the composer, and the pane redraws while streaming, so a
    // needle re-match is unreliable and used to strand the send ("never left the
    // box") even though it had landed. The authority is instead:
    //   (a) the text surfacing as a new user turn in the transcript — idle path,
    //       delivered; or
    //   (b) the composer clearing — the draft left the box into Claude's queue,
    //       busy path → "queued"; reconcileQueued promotes it once it surfaces.
    tmuxEnter(target);
    for (let i = 0; i < 24; i++) {
      await sleep(150);
      const held = composerHoldsInput(target, needle);
      const transcriptMatchesNow = await transcriptUserMatchCount(transcriptPath, needle);
      if (transcriptMatchesNow > transcriptMatchesBefore) {
        msg.status = "delivered";
        msg.error = undefined;
        return;
      }
      // held === false: composer visible and our draft is gone.
      // held === null: composer vanished — a selector/overlay opened right after
      //   Enter (the message triggered a permission prompt, or the rating overlay
      //   surfaced). Either way the draft is no longer pending in the box, so the
      //   submit landed. Only held === true (draft still there) means Enter
      //   didn't take.
      if (held === false || held === null) {
        // A slash command (/clear, /compact, …) executes immediately and never
        // surfaces as a user-text turn — /clear even wipes the transcript — so
        // the transcript probe would never confirm it. Treat it delivered the
        // moment it leaves the box. Otherwise it may be queued behind the current
        // turn (reconcileQueued promotes it once it surfaces).
        const isCommand = msg.text.trimStart().startsWith("/");
        msg.status = isCommand ? "delivered" : "queued";
        msg.error = undefined;
        return;
      }
    }
    // Still in the box → the Enter didn't submit. Loop: we'll skip re-inserting
    // (draft present) and press Enter again.
  }

  msg.status = "failed";
  msg.error = "message never left the input box after retries";
  logDeliverFailure(sessionId, msg, target);
}
