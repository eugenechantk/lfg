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

import { randomBytes, randomUUID } from "node:crypto";
import { nudgeJournalPump } from "./journal-pump.ts";
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
import {
  listSessions,
  resolveTranscript,
  recentMessages,
  type Session,
  type SessionMsg,
} from "./sessions.ts";
import { PATHS } from "./config.ts";
import type { Journal } from "./journal.ts";
import { SendqStore, type SendqRow } from "./sendq-store.ts";

export type QueuedMsg = {
  id: string;
  clientId: string;
  text: string;
  // pending: waiting behind an earlier LFG send. sending: actively being typed
  // and confirmed. queued: accepted by the agent's native next-turn queue while
  // it is busy. delivered: surfaced as a real user turn. failed: delivery
  // genuinely failed after retries.
  status: "pending" | "sending" | "delivered" | "queued" | "failed";
  error?: string;
  attempts: number;
  createdAt: number;
  updatedAt: number;
  // How many times we've re-driven this message because it landed in Claude's
  // native queue (status "queued") but never surfaced and the agent then went idle
  // (the agent dropped it, or our Enter stranded it as an unsubmitted composer
  // draft). Capped so a message that genuinely can't land eventually fails
  // instead of looping. Optional/back-compat: absent === 0.
  redeliveries?: number;
};

export type EnqueueOptions = {
  clientId?: string;
  /** Test-only escape hatch; production callers leave delivery auto-starting. */
  autoKick?: boolean;
};

export type EnqueuedMsg = QueuedMsg & { duplicate?: true };
export type QueueListMsg = Omit<QueuedMsg, "clientId">;

type SessionQueue = { msgs: QueuedMsg[]; running: boolean };

// Avoid writing the same intentional Codex hold on every one-second pump tick.
// Weak keys disappear with pruned queue rows, so this needs no lifecycle sweep.
const heldTraced = new WeakSet<QueuedMsg>();

const queues = new Map<string, SessionQueue>();
let store: SendqStore | null = null;
let recovered = false;
let journal: Journal | null = null;
let lastCreatedAt = 0;

// Keep the per-session list from growing unbounded; terminal rows older than
// this many are pruned on each enqueue.
const KEEP_TERMINAL = 12;

function fromRow(row: SendqRow): QueuedMsg {
  return {
    id: row.id,
    clientId: row.clientId,
    text: row.text,
    status: row.status,
    error: row.error ?? undefined,
    attempts: row.attempts,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    redeliveries: row.redeliveries || undefined,
  };
}

function duplicateByClientId(sessionId: string, clientId: string): EnqueuedMsg | null {
  const existing = queues.get(sessionId)?.msgs.find((m) => m.clientId === clientId);
  if (existing) return Object.assign({ ...existing }, { duplicate: true as const });
  const persisted = store?.findByClientId(sessionId, clientId);
  return persisted ? Object.assign(fromRow(persisted), { duplicate: true as const }) : null;
}

function persistMsg(sessionId: string, msg: QueuedMsg): void {
  store?.upsert({
    id: msg.id,
    sessionId,
    clientId: msg.clientId,
    text: msg.text,
    status: msg.status,
    error: msg.error ?? null,
    attempts: msg.attempts,
    redeliveries: msg.redeliveries ?? 0,
    createdAt: msg.createdAt,
    updatedAt: msg.updatedAt,
  });
}

function deletePersisted(ids: string[]): void {
  store?.deleteMany(ids);
}

function nextCreatedAt(): number {
  lastCreatedAt = Math.max(Date.now(), lastCreatedAt + 1);
  return lastCreatedAt;
}

function journalDelivered(sessionId: string, msg: QueuedMsg, userTurnId: string | null): void {
  journal?.append(sessionId, "queue", {
    kind: "delivered",
    clientId: msg.clientId,
    msgId: msg.id,
    userTurnId,
  });
}

function journalFailed(sessionId: string, msg: QueuedMsg): void {
  journal?.append(sessionId, "queue", {
    kind: "failed",
    clientId: msg.clientId,
    msgId: msg.id,
  });
}

function ensureRecovered(): void {
  if (!store || recovered) return;
  recovered = true;
  for (const row of store.recoverable()) {
    const msg = fromRow(row);
    if (msg.status === "sending") {
      msg.status = "pending";
      msg.updatedAt = Date.now();
      persistMsg(row.sessionId, msg);
    }
    const s = q(row.sessionId);
    if (!s.msgs.some((m) => m.id === msg.id)) s.msgs.push(msg);
  }
}

export function setSendqStore(next: SendqStore | null): void {
  store = next;
  recovered = false;
  if (store) ensureRecovered();
}

export function setSendqJournal(next: Journal | null): void {
  journal = next;
}

export function __resetSendqForTests(): void {
  stopQueuePump();
  queues.clear();
  store = null;
  recovered = false;
  journal = null;
  lastCreatedAt = 0;
}

export function __journalQueueTerminalForTests(
  sessionId: string,
  msg: QueuedMsg,
  userTurnId: string | null = null,
): void {
  if (msg.status === "delivered") journalDelivered(sessionId, msg, userTurnId);
  else if (msg.status === "failed") journalFailed(sessionId, msg);
}

function q(sessionId: string): SessionQueue {
  let s = queues.get(sessionId);
  if (!s) {
    s = { msgs: [], running: false };
    queues.set(sessionId, s);
  }
  return s;
}

export function listQueue(sessionId: string): QueueListMsg[] {
  ensureRecovered();
  return (queues.get(sessionId)?.msgs ?? []).map(({ clientId: _clientId, ...msg }) => msg);
}

export function getMessage(sessionId: string, id: string): QueuedMsg | null {
  ensureRecovered();
  return queues.get(sessionId)?.msgs.find((m) => m.id === id) ?? null;
}

export function getMessageByClientId(sessionId: string, clientId: string): EnqueuedMsg | null {
  ensureRecovered();
  return duplicateByClientId(sessionId, clientId);
}

export function recordImmediateMessage(
  sessionId: string,
  text: string,
  clientId: string,
): EnqueuedMsg {
  ensureRecovered();
  const existing = duplicateByClientId(sessionId, clientId);
  if (existing) return existing;
  const now = nextCreatedAt();
  const msg: QueuedMsg = {
    id: randomBytes(8).toString("hex"),
    clientId,
    text,
    status: "delivered",
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  };
  persistMsg(sessionId, msg);
  // Pre-delivered rows (resume-path sends confirmed outside the pump) need the
  // ack too — the client's outbox resolves bubbles by this event, whichever
  // path delivered the text. userTurnId is unknown here; null per protocol.
  journalDelivered(sessionId, msg, null);
  store?.pruneTerminal(sessionId, KEEP_TERMINAL);
  return msg;
}

export function enqueueMessage(sessionId: string, text: string, opts: EnqueueOptions = {}): EnqueuedMsg {
  ensureRecovered();
  const clientId = opts.clientId || randomUUID();
  const existing = duplicateByClientId(sessionId, clientId);
  if (existing) return existing;
  const s = q(sessionId);
  const now = nextCreatedAt();
  const msg: QueuedMsg = {
    id: randomBytes(8).toString("hex"),
    clientId,
    text,
    status: "pending",
    attempts: 0,
    createdAt: now,
    updatedAt: now,
  };
  s.msgs.push(msg);
  persistMsg(sessionId, msg);
  traceQueue(sessionId, msg, "enqueue");
  pruneTerminal(s);
  store?.pruneTerminal(sessionId, KEEP_TERMINAL);
  if (opts.autoKick !== false) kick(sessionId);
  return msg;
}

export function retryMessage(sessionId: string, id: string): QueuedMsg | null {
  ensureRecovered();
  const s = queues.get(sessionId);
  const msg = s?.msgs.find((m) => m.id === id);
  if (!s || !msg) return null;
  if (msg.status !== "failed") return msg;
  msg.status = "pending";
  msg.error = undefined;
  msg.attempts = 0;
  msg.updatedAt = Date.now();
  persistMsg(sessionId, msg);
  kick(sessionId);
  return msg;
}

// Drop messages the user no longer needs to see. In-flight messages (pending,
// sending, or already committed to the agent's native queue) stay so a clear
// never silently abandons tracking for a send that will still execute.
export function clearResolved(sessionId: string): number {
  ensureRecovered();
  const s = queues.get(sessionId);
  if (!s) return 0;
  const before = s.msgs.length;
  const active = (m: QueuedMsg) =>
    m.status === "pending" || m.status === "sending" || m.status === "queued";
  const removed = s.msgs.filter((m) => !active(m));
  s.msgs = s.msgs.filter(active);
  deletePersisted(removed.map((m) => m.id));
  return before - s.msgs.length;
}

function pruneTerminal(s: SessionQueue) {
  const terminal = s.msgs.filter(
    (m) => m.status === "delivered" || m.status === "failed",
  );
  if (terminal.length <= KEEP_TERMINAL) return;
  const drop = new Set(
    terminal
      .sort((a, b) => a.updatedAt - b.updatedAt)
      .slice(0, terminal.length - KEEP_TERMINAL),
  );
  s.msgs = s.msgs.filter((m) => !drop.has(m));
  deletePersisted([...drop].map((m) => m.id));
}

async function sessionTarget(sessionId: string): Promise<string | null> {
  return (await listSessions()).find((s) => s.sessionId === sessionId)?.tmuxTarget ?? null;
}

type DeliveryContext = { agent: Session["agent"] | null; busy: boolean };

// Use the same structured turn-state verdict as REST/SSE instead of a second,
// delivery-only pane scrape. Codex rotates its footer while working; letting
// that presentation detail decide when to drain LFG's queue is what produced
// both very late sends and busy-turn steering.
async function deliveryContext(sessionId: string): Promise<DeliveryContext> {
  const session = (await listSessions()).find((s) => s.sessionId === sessionId);
  return session ? { agent: session.agent, busy: session.busy } : { agent: null, busy: false };
}

export type PendingDeliveryDisposition = "deliver" | "hold";

// Claude's composer owns a true next-turn queue, so immediate handoff is safe.
// Codex's similarly worded UI actually says "submitted after next tool call":
// it steers the CURRENT turn. A request phrased for the next turn is therefore
// acknowledged and visible in the transcript but never executed separately.
// Keep Codex follow-ups durable in LFG until the structured turn state is idle.
export function pendingDeliveryDisposition(
  agent: Session["agent"] | null,
  agentBusy: boolean,
): PendingDeliveryDisposition {
  return agent === "codex" && agentBusy ? "hold" : "deliver";
}

function kick(sessionId: string) {
  ensureRecovered();
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
        const context = await deliveryContext(sessionId);
        if (pendingDeliveryDisposition(context.agent, context.busy) === "hold") {
          if (!heldTraced.has(next)) {
            heldTraced.add(next);
            traceQueue(sessionId, next, "hold", {
              reason: "codex active turn",
              busy: context.busy,
              agent: context.agent,
            });
          }
          break;
        }
        next.status = "sending";
        next.updatedAt = Date.now();
        persistMsg(sessionId, next);
        traceQueue(sessionId, next, "deliver-start");
        let deliveredUserTurnId: string | null = null;
        try {
          const result = await deliver(sessionId, next);
          deliveredUserTurnId = result.userTurnId;
        } catch (e) {
          next.status = "failed";
          next.error = e instanceof Error ? e.message : String(e);
        }
        next.updatedAt = Date.now();
        persistMsg(sessionId, next);
        const status = (next as QueuedMsg).status;
        traceQueue(sessionId, next, `deliver-${status}`, { error: next.error });
        if (status === "delivered") journalDelivered(sessionId, next, deliveredUserTurnId);
        else if (status === "failed") journalFailed(sessionId, next);
        pruneTerminal(s);
        store?.pruneTerminal(sessionId, KEEP_TERMINAL);
        // Starting one Codex turn changes its state asynchronously. Do not race
        // the next pending row into that new turn before listSessions observes
        // it as busy; the one-second pump will re-evaluate against the structured
        // state and deliver the next row after this turn really ends.
        if (context.agent === "codex" && status !== "failed") break;
      }
    } finally {
      s.running = false;
    }
  })();
}

// Client-independent background pump: a message may be recovered while no
// client SSE stream is open (app closed), so a server-owned ticker drives
// delivery + native-queue reconciliation regardless of who's watching.
let pumpTimer: ReturnType<typeof setInterval> | null = null;
export function startQueuePump(intervalMs = 1000): void {
  if (pumpTimer) return;
  ensureRecovered();
  pumpTimer = setInterval(() => {
    ensureRecovered();
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

// Remove a message that will not execute (again). A pending/failed row can be
// removed cleanly, and so can a `delivered` one — that row is a receipt for a
// turn the agent has already run, not a retraction of pending work, and the
// client's only way to dismiss a stuck bubble is this call succeeding. Only
// `sending` (mid-keystroke) and `queued` (already in the agent's native
// next-turn queue) still have a future, so neither can be retracted truthfully.
// Returns true only when the message will no longer execute.
export function removeMessage(sessionId: string, id: string): boolean {
  ensureRecovered();
  const s = queues.get(sessionId);
  if (!s) return false;
  const m = s.msgs.find((x) => x.id === id);
  if (!m || m.status === "sending" || m.status === "queued") return false;
  s.msgs = s.msgs.filter((x) => x.id !== id);
  store?.delete(id);
  return true;
}

// "Send now + interrupt": stop the current turn and run this message next. Move
// it to the head of the queue, interrupt the agent (so it idles), and kick — the
// pump/kick delivers it the moment the Escape lands. A message that already
// reached the agent's native queue (status "queued") is run by the interrupt directly.
export async function sendNow(sessionId: string, id: string): Promise<boolean> {
  ensureRecovered();
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

// How long a message may sit "queued" (in the agent's native queue) while the session
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

// Re-driving is only safe once the agent is provably idle, and ONE pane capture
// cannot prove that: our own paste into the composer redraws the pane and
// `isBusy` reads false for a second or two mid-turn (journal `busy` flipped
// false at 07:36:07/10Z on 2026-09-07, each on a sendq deliver-start). A single
// such capture re-typed a batch of seven messages 17 minutes before the turn
// actually ended. Idle must hold across polls for this long before it counts.
const IDLE_CONFIRM_MS = 3_000;

export class IdleConfirmer {
  private firstIdleAt = new Map<string, number>();
  constructor(private readonly minMs: number = IDLE_CONFIRM_MS) {}
  /** Feed one observation; true only once idle has held for ≥ minMs. */
  observe(sid: string, idle: boolean, now: number): boolean {
    if (!idle) {
      this.firstIdleAt.delete(sid);
      return false;
    }
    const since = this.firstIdleAt.get(sid);
    if (since == null) {
      this.firstIdleAt.set(sid, now);
      return false;
    }
    return now - since >= this.minMs;
  }
}
const idleConfirmer = new IdleConfirmer();

// When the 40-message window does not reach back to when a queued message was
// created (a long turn's tool calls pushed its absorbed turn out of view), read
// a deeper tail before deciding — but not on every poll tick.
const DEEP_SCAN_BYTES = 4 * 1024 * 1024;
const DEEP_SCAN_MIN_INTERVAL_MS = 30_000;
const lastDeepScanAt = new Map<string, number>();

// Pure: mark every "queued" message whose needle appears in `userText` as
// delivered. Returns the rows it promoted (caller persists/journals them).
export function promoteSurfacedCore(msgs: QueuedMsg[], userText: string, now: number): QueuedMsg[] {
  const turn = norm(userText);
  if (!turn) return [];
  const promoted: QueuedMsg[] = [];
  for (const m of msgs) {
    if (m.status !== "queued") continue;
    const needle = norm(m.text).slice(0, NEEDLE_LEN);
    if (!needle || !turn.includes(needle)) continue;
    m.status = "delivered";
    m.error = undefined;
    m.updatedAt = now;
    promoted.push(m);
  }
  return promoted;
}

// Called by the journal pump for every user text turn it journals, so a message
// Claude absorbed mid-turn (see queueOperationMessage in sessions.ts) is
// acknowledged the moment the transcript records it — not on some later
// reconcile, whose 40-message window a long turn's tool calls have usually
// pushed the turn out of by the time the session goes idle.
export function noteSurfacedUserTurn(sessionId: string, m: SessionMsg): void {
  if (m.role !== "user" || m.kind !== "text") return;
  ensureRecovered();
  const s = queues.get(sessionId);
  if (!s || !s.msgs.some((x) => x.status === "queued")) return;
  const promoted = promoteSurfacedCore(s.msgs, m.text, Date.now());
  if (!promoted.length) return;
  for (const p of promoted) {
    persistMsg(sessionId, p);
    traceQueue(sessionId, p, "surfaced-delivered", { userTurnId: m.id });
    journalDelivered(sessionId, p, m.id);
  }
  pruneTerminal(s);
  store?.pruneTerminal(sessionId, KEEP_TERMINAL);
}

// Whether our pending draft is currently sitting in the composer. For a typed
// (single-line) send that's the needle verbatim; for a pasted (multi-line) send
// Claude collapses the draft to a "[Pasted text +N lines]" chip, so the needle
// never appears — match that marker instead. null = composer not visible.
export function composerTextHoldsNeedle(box: string, needle: string): boolean {
  const n = norm(box);
  return n.includes(needle) || /pasted\s+(?:text|content)\b/i.test(n);
}

function composerHoldsInput(target: string, needle: string): boolean | null {
  const box = inputBoxText(target);
  if (box == null) return null;
  return composerTextHoldsNeedle(box, needle);
}

// Submit policy (2026-09-17): type, press Enter, let the transcript judge.
//
// deliver() used to confirm the draft in the composer BEFORE pressing Enter
// and, on "draft absent", clear the box and retype up to three times. Six
// weeks of ~/.lfg/sendq.log (2026-08-06 → 09-17) say what that bought: 1,202
// sends succeeded on the first attempt, ONE succeeded on a retry, and all 54
// failures were the confirmation itself misreading the pane ("message never
// left the input box after retries") — the keystrokes had landed every time
// and the queue wiped them with its own Ctrl-U. Lost keystrokes are not a
// real failure mode; a misread composer is (four border-parser fixes, and
// counting). So the composer read is advisory only: it shortens the settle
// wait when it can see the draft and can prompt one more Enter when it
// positively still sees the draft after one, but no reading of it blocks the
// submit or fails the send. The authorities are the transcript (idle: a new
// user turn = delivered) and reconcileQueued (busy or unreadable: "queued",
// promoted once the text surfaces, re-driven on sustained idle if it never
// does, and only THEN failed).
//
// What one post-Enter observation means:
//   transcript grew            → delivered, whatever the composer says.
//   composer readable & absent → the draft left the box: queued (busy Claude
//                                took it into its native queue), or delivered
//                                for a slash command, which never surfaces as
//                                a user turn (/clear even wipes the transcript).
//   composer unreadable (null) → same as absent: a selector/overlay opened on
//                                submit, or the parser can't follow the pane —
//                                either way no evidence Enter failed.
//   composer still holds it    → keep watching; after the window, Enter again.
export type SubmitOutcome = "delivered" | "queued" | "hold";

export function submitOutcome(
  transcriptGrew: boolean,
  held: boolean | null,
  isCommand: boolean,
): SubmitOutcome {
  if (transcriptGrew) return "delivered";
  if (held === true) return "hold";
  return isCommand ? "delivered" : "queued";
}

// How long to let the TUI take the typed bytes as text before the Enter
// arrives (an Enter inside the same input burst can be read as a pasted
// newline). Polls stop early once the composer visibly holds the draft.
const SETTLE_POLLS = 10;
const SETTLE_POLL_MS = 150;

// One line per lifecycle event, appended to data/sendq.log and never pruned.
//
// Why this exists: the queue rows themselves are the only record of what
// happened to a send, and `pruneTerminal`/`KEEP_TERMINAL` erase them — so a
// "my message never arrived" report an hour later has nothing left to read,
// and the answer (native-queued? never enqueued? failed and pruned?)
// has to be re-derived by live repro. The trace is deliberately boring and
// cheap: no pane capture and one JSON line per lifecycle transition.
function traceQueue(
  sessionId: string,
  msg: QueuedMsg,
  event: string,
  extra: Record<string, unknown> = {},
): void {
  // The unit tests drive real enqueues; without this they append hundreds of
  // synthetic lines to the host's own trace, which is the file someone reads
  // to explain a real lost message.
  if (process.env.NODE_ENV === "test") return;
  try {
    mkdirSync(PATHS.data, { recursive: true });
    appendFileSync(
      join(PATHS.data, "sendq.log"),
      JSON.stringify({
        t: new Date().toISOString(),
        event,
        sessionId,
        id: msg.id,
        status: msg.status,
        attempts: msg.attempts,
        redeliveries: msg.redeliveries ?? 0,
        ageMs: Date.now() - msg.createdAt,
        text: msg.text.slice(0, 80),
        ...extra,
      }) + "\n",
    );
  } catch {}
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

async function transcriptUserMatches(
  transcriptPath: string | null,
  needle: string,
): Promise<{ count: number; newestId: string | null }> {
  if (!transcriptPath) return { count: 0, newestId: null };
  try {
    const msgs = await recentMessages(transcriptPath, 120);
    const matches = msgs.filter(
      (m) => m.role === "user" && m.kind === "text" && norm(m.text).includes(needle),
    );
    return { count: matches.length, newestId: matches[matches.length - 1]?.id ?? null };
  } catch {
    return { count: 0, newestId: null };
  }
}

// Pure core of reconcileQueued, split out so the promote/redeliver logic is unit
// testable without tmux/transcript IO. Mutates `msgs` in place and returns
// { changed, kick }: `changed` if any status moved (caller re-emits), `kick` if
// any message was reset to "pending" (caller must re-run the delivery loop).
//
// Three transitions for a "queued" message (one that left the composer into
// the agent's native queue while busy):
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
  opts: {
    idleConfirmed: boolean;
    now: number;
    graceMs?: number;
    // Timestamp of the oldest transcript message `recentUserTexts` was drawn
    // from. A message created BEFORE that point may have surfaced out of view
    // (Claude absorbed it into a long turn), so its absence from the window
    // proves nothing and it must not be re-driven or failed. null = the window
    // reaches the start of the transcript.
    windowStartTs?: number | null;
  },
): { changed: boolean; kick: boolean } {
  const grace = opts.graceMs ?? ORPHAN_IDLE_GRACE_MS;
  const normedTurns = recentUserTexts.map(norm);
  let changed = false;
  let kick = false;
  for (const m of msgs) {
    if (m.status !== "queued") continue;
    const needle = norm(m.text).slice(0, NEEDLE_LEN);
    const covered = opts.windowStartTs == null || opts.windowStartTs <= m.createdAt;
    if (normedTurns.some((t) => t.includes(needle))) {
      m.status = "delivered";
      m.updatedAt = opts.now;
      changed = true;
    } else if (!covered) {
      continue;
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
// the agent's native queue rather than the transcript — deliver() can't wait for it
// to surface without blocking the per-session queue behind a turn that may run
// for minutes. So we reconcile lazily: whenever the UI polls, promote any
// queued message that has since shown up in the transcript to "delivered" (the
// UI then drops it), or — when the agent has gone idle without it surfacing —
// re-drive it so it actually gets picked up now that the agent is ready (see
// reconcileQueuedCore). Returns true if anything changed so the caller re-emits.
export async function reconcileQueued(sessionId: string): Promise<boolean> {
  ensureRecovered();
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
  // We can only re-drive a queued message once we've confirmed the session is
  // idle — a busy Claude may still be mid-turn with the message legitimately
  // waiting in its queue, so re-driving then would double-send. If we can't read
  // the pane, treat it as not-idle (leave the message queued) rather than risk
  // it. Probe the pane only when there's an aged candidate to re-drive, never
  // while our own delivery loop is typing into it (the paste redraws the pane
  // and reads as idle mid-turn), and only count idle once it has held across
  // polls (IdleConfirmer).
  const now = Date.now();
  const hasAged = pending.some((m) => now - m.updatedAt > ORPHAN_IDLE_GRACE_MS);
  let idleConfirmed = false;
  if (hasAged) {
    if (s.running) {
      idleConfirmer.observe(sessionId, false, now);
    } else {
      const target = (await listSessions()).find((x) => x.sessionId === sessionId)?.tmuxTarget;
      const pane = target ? capturePane(target) : null;
      idleConfirmed = idleConfirmer.observe(sessionId, pane != null && !isBusy(pane), now);
    }
  }

  // The window must reach back to when each aged message was queued, or its
  // absence proves nothing (Claude may have absorbed it into a long turn whose
  // tool calls pushed the turn out of the last 40 messages). If it doesn't,
  // read a deeper tail — rate-limited, since this runs on the pump's poll.
  let windowStartTs = firstTimestamp(recent);
  if (
    idleConfirmed &&
    windowStartTs != null &&
    pending.some((m) => m.createdAt < windowStartTs!) &&
    now - (lastDeepScanAt.get(sessionId) ?? 0) >= DEEP_SCAN_MIN_INTERVAL_MS
  ) {
    lastDeepScanAt.set(sessionId, now);
    try {
      recent = await recentMessages(transcriptPath, 0, { maxBytes: DEEP_SCAN_BYTES });
      windowStartTs = firstTimestamp(recent);
    } catch {}
  }
  const recentUserMsgs = recent.filter((r) => r.role === "user" && r.kind === "text");
  const recentUserTexts = recentUserMsgs.map((r) => r.text);

  const before = new Map(
    s.msgs.map((m) => [
      m.id,
      {
        status: m.status,
        attempts: m.attempts,
        redeliveries: m.redeliveries ?? 0,
        error: m.error,
      },
    ]),
  );
  const { changed, kick: needsKick } = reconcileQueuedCore(s.msgs, recentUserTexts, {
    idleConfirmed,
    now,
    windowStartTs,
  });
  if (changed) {
    for (const m of s.msgs) {
      const prev = before.get(m.id);
      if (!prev) continue;
      const redeliveries = m.redeliveries ?? 0;
      if (
        prev.status === m.status &&
        prev.attempts === m.attempts &&
        prev.redeliveries === redeliveries &&
        prev.error === m.error
      ) {
        continue;
      }
      persistMsg(sessionId, m);
      traceQueue(sessionId, m, `reconcile-${m.status}`, {
        from: prev.status,
        idleConfirmed,
        error: m.error,
      });
      if (prev.status !== "delivered" && m.status === "delivered") {
        const needle = norm(m.text).slice(0, NEEDLE_LEN);
        const match = [...recentUserMsgs].reverse().find((r) => norm(r.text).includes(needle));
        journalDelivered(sessionId, m, match?.id ?? null);
      } else if (prev.status !== "failed" && m.status === "failed") {
        journalFailed(sessionId, m);
      }
    }
    pruneTerminal(s);
    store?.pruneTerminal(sessionId, KEEP_TERMINAL);
  }
  // A re-driven message is back to "pending"; run the delivery loop so it's
  // actually (re)submitted to the now-idle agent. kick() no-ops if already busy.
  if (needsKick) kick(sessionId);
  return changed;
}

function firstTimestamp(msgs: SessionMsg[]): number | null {
  for (const m of msgs) if (m.ts != null) return m.ts;
  return null;
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

async function deliver(sessionId: string, msg: QueuedMsg): Promise<{ userTurnId: string | null }> {
  const sess = (await listSessions()).find((s) => s.sessionId === sessionId);
  const target = sess?.tmuxTarget ?? null;
  if (!target) {
    msg.status = "failed";
    msg.error = "session is not in a tmux pane";
    return { userTurnId: null };
  }
  const transcriptPath = await resolveTranscript(sessionId);
  const needle = norm(msg.text).slice(0, NEEDLE_LEN);
  const transcriptMatchesBefore = await transcriptUserMatches(transcriptPath, needle);

  // Clear any session-rating overlay first — it swallows Enter and would
  // otherwise swallow the Enter of every send.
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
  // never left the input box after retries" (pre-2026-09-17 policy). The
  // footer-based detector fixes it.
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
      return { userTurnId: null };
    }
  }

  // Multi-line messages must be pasted, not typed: send-keys -l transmits each
  // embedded newline as an Enter, so a typed multi-line message submits/fragments
  // at the first newline and the full text never lands as one draft. Bracketed
  // paste makes the TUI take the newlines as newlines.
  const multiline = /[\r\n]/.test(msg.text);
  // Wipe any foreign draft first. The composer may already hold text the user
  // (or a stranded earlier send) left there; insertion appends, so without this
  // our message fuses onto it. Ctrl-U on an empty box is a harmless no-op.
  tmuxClearInput(target);
  await sleep(120);
  if (multiline) tmuxPaste(target, msg.text);
  else tmuxType(target, msg.text);
  msg.attempts = 1;
  msg.updatedAt = Date.now();
  persistMsg(sessionId, msg);
  for (let i = 0; i < SETTLE_POLLS; i++) {
    await sleep(SETTLE_POLL_MS);
    if (composerHoldsInput(target, needle) === true) break;
  }

  // See submitOutcome for the policy. Each round is one Enter plus a watch
  // window; a further round only happens when the composer POSITIVELY still
  // shows the draft, and an extra Enter on an already-empty box is a no-op, so
  // a misread here costs a keystroke, never the message.
  const ENTER_ROUNDS = 3;
  const isCommand = msg.text.trimStart().startsWith("/");
  for (let round = 0; round < ENTER_ROUNDS; round++) {
    if (round > 0) {
      msg.attempts++;
      msg.updatedAt = Date.now();
      persistMsg(sessionId, msg);
    }
    // The rating overlay can surface between turns, right as we're about to
    // submit; clear it again so this Enter isn't swallowed.
    if (clearFeedbackPrompt(target)) await sleep(300);
    tmuxEnter(target);
    for (let i = 0; i < 24; i++) {
      await sleep(150);
      const transcriptMatchesNow = await transcriptUserMatches(transcriptPath, needle);
      const grew = transcriptMatchesNow.count > transcriptMatchesBefore.count;
      const outcome = submitOutcome(grew, composerHoldsInput(target, needle), isCommand);
      if (outcome === "hold") continue;
      msg.status = outcome;
      msg.error = undefined;
      persistMsg(sessionId, msg);
      // Say so now rather than up to a poll tick later.
      nudgeJournalPump(sessionId);
      return { userTurnId: grew ? transcriptMatchesNow.newestId : null };
    }
  }

  // Never surfaced and the composer never read as cleared. That is not proof
  // of failure — it is exactly the misread this policy stops trusting (a
  // region spanning the transcript echoes our own text back as "still in the
  // box"). Park it queued: reconcileQueued promotes it the moment the text
  // surfaces, and re-drives it — then fails it — only once a provably idle
  // agent has not picked it up.
  msg.status = "queued";
  msg.error = undefined;
  persistMsg(sessionId, msg);
  logDeliverFailure(sessionId, msg, target);
  nudgeJournalPump(sessionId);
  return { userTurnId: null };
}
