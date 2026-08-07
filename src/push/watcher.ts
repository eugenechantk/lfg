// Always-on session watcher that turns session state transitions into push
// notifications — independent of any connected client SSE stream (that's the
// whole point: notify when the app is closed). It reuses the same detection
// primitives the live SSE loop uses (capturePane/isBusy + resolveSessionPrompt)
// and fans qualifying transitions out to every registered device via APNs.
//
// The interesting logic — deciding *when* a transition warrants a push and
// classifying it done-vs-needs-input — lives in the pure `reduceTransition`
// reducer below, which is unit-tested in isolation (no tmux, no network).
import {
  listSessions,
  resolveTranscript,
  pendingToolPrompt,
  type PendingPrompt,
} from "../sessions.ts";
import { capturePaneAsync, isBusy, parsePrompt, type PanePrompt } from "../tmux.ts";
import { findEntryByAnyId } from "../aisdk-registry.ts";
import { codexDelegationSessionIds } from "../activity.ts";
import { listDevices } from "./store.ts";
import {
  listActivityUpdateTokens,
  listPushToStartTokens,
  removeLiveActivityToken,
} from "./liveactivity-store.ts";
import {
  apnsConfigFromEnv,
  sendApns,
  type ApnsConfig,
  type ApnsPayload,
  type ApnsPayloadSession,
  type ApnsTransport,
} from "./apns.ts";
import {
  buildEnd,
  buildStart,
  buildUpdate,
  sendLiveActivity,
  type LiveActivityContentState,
  type LiveActivityRow,
  type LiveActivityPush,
} from "./liveactivity.ts";
import { unregisterDevice } from "./store.ts";
import { loadFleetActivityActive, saveFleetActivityActive } from "./fleet-active-store.ts";
import { resolveBusy, sessionDisplayState, sessionTurnState } from "../session-state.ts";
import { basename } from "node:path";

// One observation of a session at a single tick.
export type SessionState = {
  busy: boolean;
  promptPresent: boolean;
  promptQuestion?: string | null;
};

// What the watcher remembers about a session between ticks.
export type PriorState = {
  busy: boolean;
  promptPresent: boolean;
  lastNotifiedAt: number;
};

export type PushKind = "needs-input" | "finished";

export type Transition = { event: PushKind | null; state: PriorState };

// How long after one push we suppress a follow-up for the same session, so a
// "finished" immediately followed by a late-arriving prompt can't double-notify.
const DEDUPE_MS = 10_000;

/**
 * Pure transition reducer. Given the previously-remembered state and a fresh
 * observation, decide whether to emit a push and what the next remembered state
 * is. Emits at most one event per call.
 *
 * Rules:
 *  - The agent going from busy → idle is a "your turn" moment. If a prompt is
 *    pending it's needs-input; otherwise the turn just finished.
 *  - A prompt newly appearing while already idle (it can land a tick after busy
 *    flips) is needs-input.
 *  - Dedupe: never emit within DEDUPE_MS of the last emit for this session.
 *  - Seeding (first observation of a session) is the caller's job — it records
 *    state without calling this, so a session already idle/prompting at startup
 *    doesn't fire.
 */
export function reduceTransition(
  prev: PriorState,
  next: SessionState,
  now: number,
  dedupeMs = DEDUPE_MS,
): Transition {
  const carry: PriorState = {
    busy: next.busy,
    promptPresent: next.promptPresent,
    lastNotifiedAt: prev.lastNotifiedAt,
  };

  // Still (or again) working — nothing to announce yet.
  if (next.busy) return { event: null, state: carry };

  const stoppedThisTick = prev.busy && !next.busy;
  const promptJustAppeared = !prev.promptPresent && next.promptPresent;

  let candidate: PushKind | null = null;
  if (stoppedThisTick) {
    candidate = next.promptPresent ? "needs-input" : "finished";
  } else if (promptJustAppeared) {
    candidate = "needs-input";
  }

  if (candidate && now - prev.lastNotifiedAt >= dedupeMs) {
    return { event: candidate, state: { ...carry, lastNotifiedAt: now } };
  }
  return { event: null, state: carry };
}

const clip = (t: string, n: number): string => {
  const c = t.replace(/\s+/g, " ").trim();
  return c.length > n ? c.slice(0, n - 1).trimEnd() + "…" : c;
};

// A session as seen by buildPayload — a subset of the full Session that carries
// just what the client needs to render the session screen on tap.
export type PayloadSessionInput = {
  sessionId?: string | null;
  title?: string | null;
  tmuxName?: string | null;
  project?: string | null;
  cwd?: string | null;
  agent?: string | null;
  model?: string | null;
  status?: string | null;
  lastActivityAt?: number | null;
};

/// State of the one fleet Live Activity between ticks. `since` is tracked for
/// every active session, not just the rendered rows, so a session that scrolls
/// out of the visible rows and back keeps its elapsed time.
export type LiveActivityActive = {
  startedAt: number;
  contentState?: LiveActivityContentState;
  since?: Record<string, { state: LiveActivityRow["state"]; at: number }>;
};

export type LiveActivityAction = {
  event: "start" | "update" | "end";
  push: LiveActivityPush;
};

export type LiveActivityDecision = {
  action: LiveActivityAction | null;
  nextActive: LiveActivityActive | null;
};

/// Which rows the CARD renders. The precedence itself is no longer restated here
/// — it lives once in `sessionDisplayState` (../session-state.ts), shared with the
/// REST `state` field and mirrored in LFGCore for the client, so this function and
/// `FleetActivitySnapshot` can no longer drift apart by hand.
///
/// `blocked` and `idle` are real states but not card rows: a blocked session makes
/// no progress AND asks nothing, and the list's own Paused group surfaces it.
/// Closed sessions cannot reach here at all — `listSessions` returns only sessions
/// with a live process, and `closed` is exactly the absence of one.
function fleetRowState(
  session: PayloadSessionInput,
  next: SessionState,
): LiveActivityRow["state"] | null {
  const state = sessionDisplayState({
    promptPresent: next.promptPresent,
    blocked: session.status === "blocked",
    busy: next.busy,
  });
  return state === "needsInput" || state === "working" ? state : null;
}

function sameFleetContentState(
  a: LiveActivityContentState | undefined,
  b: LiveActivityContentState,
): boolean {
  if (!a) return false;
  if (a.working !== b.working || a.needsInput !== b.needsInput || a.more !== b.more) return false;
  if (a.rows.length !== b.rows.length) return false;
  // `updatedAt` deliberately excluded — it changes every tick and would make
  // every tick a push.
  return a.rows.every((row, i) =>
    row.sid === b.rows[i]!.sid &&
    row.title === b.rows[i]!.title &&
    row.state === b.rows[i]!.state &&
    row.since === b.rows[i]!.since
  );
}

/// Needs-input first so the actionable sessions survive truncation, then
/// oldest-first within a state.
export function orderFleetRows(rows: LiveActivityRow[]): LiveActivityRow[] {
  const rank = (state: LiveActivityRow["state"]) => (state === "needsInput" ? 0 : 1);
  return [...rows].sort(
    (a, b) => rank(a.state) - rank(b.state) || a.since - b.since || a.sid.localeCompare(b.sid),
  );
}

/**
 * How many rows the lock-screen card renders before folding the rest into
 * "N More". Must match `FleetActivitySnapshot.maxRows` on the client — the lock
 * screen is a fixed ~160pt frame that center-clips overheight content, silently
 * dropping the header.
 */
export const MAX_FLEET_ROWS = 3;

/**
 * Reduce this tick's observations into at most one Live Activity action.
 *
 * Note there is no per-app ceiling to respect any more: the retired per-session
 * design had to truncate at ActivityKit's hard limit of 5 concurrent activities
 * and log the sessions it dropped. One aggregate activity can never hit it.
 */
export function reduceFleetLiveActivity(args: {
  observations: Array<{ session: PayloadSessionInput; observed: SessionState }>;
  active: LiveActivityActive | null;
  now: number;
}): LiveActivityDecision {
  const priorSince = args.active?.since ?? {};
  const since: Record<string, { state: LiveActivityRow["state"]; at: number }> = {};

  let working = 0;
  let needsInput = 0;
  const rows: LiveActivityRow[] = [];

  for (const { session, observed } of args.observations) {
    const sid = session.sessionId ?? "";
    if (!sid) continue;
    const state = fleetRowState(session, observed);
    if (!state) continue;

    if (state === "needsInput") needsInput++;
    else working++;

    // A session changing state restarts its timer rather than inheriting the
    // elapsed time of its previous one.
    const prior = priorSince[sid];
    const at = prior && prior.state === state ? prior.at : args.now;
    since[sid] = { state, at };

    rows.push({
      sid,
      title: clip(session.title || session.tmuxName || sid.slice(0, 8) || "Session", 80),
      state,
      since: at,
    });
  }

  const ordered = orderFleetRows(rows);
  const contentState: LiveActivityContentState = {
    working,
    needsInput,
    rows: ordered.slice(0, MAX_FLEET_ROWS),
    more: Math.max(0, ordered.length - MAX_FLEET_ROWS),
    updatedAt: args.now,
  };

  const total = working + needsInput;

  if (!args.active) {
    if (total === 0) return { action: null, nextActive: null };
    return {
      action: { event: "start", push: buildStart({ contentState }) },
      nextActive: { startedAt: args.now, contentState, since },
    };
  }

  if (total === 0) {
    return {
      action: { event: "end", push: buildEnd(contentState, args.now) },
      nextActive: null,
    };
  }

  if (sameFleetContentState(args.active.contentState, contentState)) {
    // Nothing renderable changed — keep the refreshed `since` map but send
    // nothing.
    return { action: null, nextActive: { ...args.active, since } };
  }

  return {
    action: { event: "update", push: buildUpdate(contentState) },
    nextActive: { ...args.active, contentState, since },
  };
}

// Compact session snapshot embedded in the push so the client can render the
// session instantly on tap instead of waiting for the reconnect + refresh.
function snapshot(s: PayloadSessionInput): ApnsPayloadSession | undefined {
  const id = s.sessionId ?? "";
  if (!id) return undefined;
  return {
    id,
    title: s.title ? clip(s.title, 80) : undefined,
    project: s.project ?? null,
    cwd: s.cwd ?? null,
    agent: s.agent ?? undefined,
    model: s.model ?? null,
    status: s.status ?? null,
    lastActivityAt: s.lastActivityAt ?? null,
  };
}

/** Build the user-facing APNs payload for a session + event. Pure. */
export function buildPayload(
  session: PayloadSessionInput,
  kind: PushKind,
  question?: string | null,
): ApnsPayload {
  const sid = session.sessionId ?? "";
  const name = clip(session.title || session.tmuxName || sid.slice(0, 8) || "Session", 48);
  const snap = snapshot(session);
  if (kind === "needs-input") {
    return {
      title: `🙋 ${name}`,
      body: question ? clip(question, 140) : "An agent is waiting for your input.",
      sid,
      kind,
      session: snap,
    };
  }
  return {
    title: `✅ ${name}`,
    body: "The agent finished its turn.",
    sid,
    kind,
    session: snap,
  };
}

// ---- wiring (the impure parts) ----

// Observe a single session's live state via the same primitives the SSE loop
// uses. Pane-less aisdk/codex sessions get busy from the registry and never
// surface pane-scraped prompts (matching the live stream's behavior).
async function observeSession(s: {
  sessionId?: string | null;
  tmuxTarget?: string | null;
}): Promise<SessionState> {
  const delegated = s.sessionId ? codexDelegationSessionIds().has(s.sessionId) : false;
  if (!s.tmuxTarget) {
    const entry = s.sessionId ? findEntryByAnyId(s.sessionId) : null;
    return { busy: (entry ? entry.busy : false) || delegated, promptPresent: false };
  }
  const pane = await capturePaneAsync(s.tmuxTarget);
  const tp = s.sessionId ? await resolveTranscript(s.sessionId) : null;
  let prompt: PendingPrompt | PanePrompt | null = tp ? await pendingToolPrompt(tp) : null;
  if (!prompt && pane) prompt = parsePrompt(pane);
  // The SAME derivation the journal pump runs (`journal-pump.ts`), through the
  // same two functions — not a second implementation of the same idea. This used
  // to call `transcriptTurnState` directly, which skipped the hook layer and the
  // STALL_MS demotion, so this card counted a session working long after the app's
  // own list had let it go. See `session-state.ts`'s `resolveBusy`.
  const verdict = await sessionTurnState({ sessionId: s.sessionId, transcriptPath: tp });
  const busy = resolveBusy({ verdict, paneBusy: pane ? isBusy(pane) : false, delegated });
  return { busy, promptPresent: !!prompt, promptQuestion: prompt?.question ?? null };
}

export type TickDeps = {
  sessions: () => Promise<
    Array<
      PayloadSessionInput & {
        tmuxTarget?: string | null;
      }
    >
  >;
  observe: (s: { sessionId?: string | null; tmuxTarget?: string | null }) => Promise<SessionState>;
  devices: () => Promise<Array<{ token: string; env: "sandbox" | "production" }>>;
  cfg: ApnsConfig;
  send: (
    device: { token: string; env: "sandbox" | "production" },
    payload: ApnsPayload,
    cfg: ApnsConfig,
  ) => Promise<{ ok: boolean; status: number; reason?: string }>;
  onDeadToken?: (token: string) => Promise<void> | void;
  head?: () => number;
  hostId?: () => string;
  hostName?: () => string;
  liveActivities?: {
    /// The one fleet activity, or null when none is live. A box (not a bare
    /// value) so the tick can swap it and the caller observes the change.
    active: { current: LiveActivityActive | null };
    pushToStartTokens: () => Promise<Array<{ token: string; env: "sandbox" | "production" }>>;
    activityUpdateTokens: () => Promise<Array<{ token: string; env: "sandbox" | "production" }>>;
    send: (
      device: { token: string; env: "sandbox" | "production" },
      push: LiveActivityPush,
      cfg: ApnsConfig,
    ) => Promise<{ ok: boolean; status: number; reason?: string }>;
    onDeadToken?: (token: string) => Promise<void> | void;
    persistActive?: (active: LiveActivityActive | null) => Promise<void> | void;
  };
  now?: () => number;
  log?: (line: string) => void;
};

function withWakeMetadata(payload: ApnsPayload, deps: Pick<TickDeps, "head" | "hostId">): ApnsPayload {
  const hostId = deps.hostId?.();
  const seq = deps.head?.();
  return {
    ...payload,
    ...(hostId ? { hostId } : {}),
    ...(typeof seq === "number" && Number.isFinite(seq) ? { seq } : {}),
  };
}

function isDeadApnsToken(r: { ok: boolean; status: number; reason?: string }): boolean {
  return !r.ok && (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered");
}

async function sendLiveActivityToTokens(
  tokens: Array<{ token: string; env: "sandbox" | "production" }>,
  push: LiveActivityPush,
  deps: NonNullable<TickDeps["liveActivities"]>,
  cfg: ApnsConfig,
  log?: (line: string) => void,
): Promise<number> {
  let sent = 0;
  for (const token of tokens) {
    const r = await deps.send(token, push, cfg);
    if (r.ok) {
      sent++;
    } else if (isDeadApnsToken(r)) {
      await deps.onDeadToken?.(token.token);
    } else {
      log?.(`[liveactivity] ${token.token.slice(0, 8)}… ${r.status} ${r.reason ?? ""}`.trim());
    }
  }
  return sent;
}

async function applyLiveActivityDecision(
  decision: LiveActivityDecision,
  deps: NonNullable<TickDeps["liveActivities"]>,
  cfg: ApnsConfig,
  startTokens: Array<{ token: string; env: "sandbox" | "production" }>,
  log?: (line: string) => void,
): Promise<void> {
  if (!decision.action) {
    // No push, but the reducer may still have refreshed bookkeeping (the
    // `since` map). Keep it in memory; it is not worth a disk write.
    deps.active.current = decision.nextActive;
    return;
  }

  const tokens = decision.action.event === "start"
    ? startTokens
    : await deps.activityUpdateTokens();
  if (!tokens.length) return;

  const sent = await sendLiveActivityToTokens(tokens, decision.action.push, deps, cfg, log);
  if (sent <= 0) return;

  deps.active.current = decision.nextActive;
  await deps.persistActive?.(decision.nextActive);
}

/**
 * Run one watcher tick against injected dependencies. Exposed (rather than
 * buried in the interval) so it can be driven deterministically in tests. The
 * `prior` map carries per-session memory across ticks; the caller owns it.
 */
export async function runPushTick(prior: Map<string, PriorState>, deps: TickDeps): Promise<void> {
  const now = deps.now ?? Date.now;
  const sessions = await deps.sessions();
  const devices = await deps.devices();
  const liveActivities = deps.liveActivities;
  const liveStartTokens = liveActivities ? await liveActivities.pushToStartTokens() : [];
  if (!devices.length && !liveActivities) {
    // Nobody listening — keep state seeded so we don't fire a backlog when a
    // device registers mid-flight, but skip the work of observing.
    return;
  }
  const seen = new Set<string>();
  const liveActivityObservations: Array<{
    session: PayloadSessionInput;
    observed: SessionState;
    previous?: PriorState;
  }> = [];
  for (const s of sessions) {
    const sid = s.sessionId;
    if (!sid) continue;
    seen.add(sid);
    let state: SessionState;
    try {
      state = await deps.observe(s);
    } catch {
      continue;
    }
    const observedAt = now();
    const prev = prior.get(sid);
    if (liveActivities) liveActivityObservations.push({ session: s, observed: state, previous: prev });
    if (!prev) {
      // First sighting — seed without emitting. -Infinity marks "never notified"
      // so the first genuine transition isn't swallowed by the dedupe window.
      prior.set(sid, {
        busy: state.busy,
        promptPresent: state.promptPresent,
        lastNotifiedAt: Number.NEGATIVE_INFINITY,
      });
      continue;
    }
    const { event, state: nextState } = reduceTransition(prev, state, observedAt);
    prior.set(sid, nextState);
    if (!event) continue;
    const payload = withWakeMetadata(buildPayload(s, event, state.promptQuestion), deps);
    for (const d of devices) {
      const r = await deps.send(d, payload, deps.cfg);
      if (!r.ok && (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered")) {
        await deps.onDeadToken?.(d.token);
      } else if (!r.ok) {
        deps.log?.(`[push] ${d.token.slice(0, 8)}… ${r.status} ${r.reason ?? ""}`.trim());
      }
    }
  }
  // Drop memory for sessions that no longer exist.
  for (const k of [...prior.keys()]) if (!seen.has(k)) prior.delete(k);
  if (liveActivities) {
    const decision = reduceFleetLiveActivity({
      observations: liveActivityObservations,
      active: liveActivities.active.current,
      now: Math.floor(now() / 1000),
    });
    await applyLiveActivityDecision(
      decision,
      liveActivities,
      deps.cfg,
      liveStartTokens,
      deps.log,
    );
  }
}

let timer: ReturnType<typeof setInterval> | null = null;
type StartPushWatcherDeps = Pick<Partial<TickDeps>, "head" | "hostId" | "hostName">;

/**
 * The live fleet activity, at module scope rather than inside `startPushWatcher`,
 * because the CLIENT can end the card and the server has to hear about it — see
 * `noteFleetActivityEnded`.
 */
const fleetActive: { current: LiveActivityActive | null } = { current: null };

/**
 * Set when the client reports the card gone, cleared once that report has been
 * honoured by the boot-time load. Without it, an "ended" arriving while
 * `loadFleetActivityActive()` is still in flight is overwritten by the on-disk
 * state a moment later, resurrecting the card the client just told us is dead.
 */
let fleetEndedReported = false;

/**
 * The client ended (or replaced) the fleet card; forget the one we think is live.
 *
 * WHY THE SERVER CANNOT WORK THIS OUT ALONE. `FleetActivityController` ends the
 * card when the APP's active count reaches zero. The watcher's count is computed
 * independently and does not have to reach zero at the same moment, so the server
 * can be left believing a card exists that the device has already dismissed. It
 * then sends `update` forever — and since a dead Live Activity token still
 * answers 200, nothing ever tells it otherwise. Only the client knows.
 *
 * Clearing `current` makes the next tick take the `!args.active` branch and send
 * a **push-to-start**, which is the one event that can put a card back on a
 * suspended device.
 * See `.claude/diagnosis-live-activity-background-updates.md`.
 */
export async function noteFleetActivityEnded(): Promise<void> {
  fleetActive.current = null;
  fleetEndedReported = true;
  await saveFleetActivityActive(null);
}

/**
 * A client registered an `activityUpdate` token, which is proof that a card
 * exists on that device right now — ActivityKit only issues one for a live
 * activity.
 *
 * Adopt it instead of leaving `current` null, or the next tick would take the
 * `!args.active` branch and **push-to-start a second card** next to the one the
 * app just created. Adopting with no `contentState` is deliberate:
 * `sameFleetContentState(undefined, …)` is false, so the very next tick pushes
 * the current content to the freshly registered token rather than waiting for
 * something to change.
 */
export function noteFleetActivityStarted(now: () => number = Date.now): void {
  if (fleetActive.current) return; // already tracking a card; keep its baselines
  fleetActive.current = { startedAt: Math.floor(now() / 1000) };
  fleetEndedReported = false;
}

/**
 * Test seam. `noteFleetActivityEnded`/`noteFleetActivityStarted` are called from
 * HTTP handlers and mutate module state that the watcher's tick reads, so a test
 * needs the same box the server passes into `runPushTick` to observe them.
 */
export function currentFleetActivity(): { current: LiveActivityActive | null } {
  return fleetActive;
}

export function liveActivitiesEnabled(env = process.env): boolean {
  return env.LFG_LIVE_ACTIVITIES === "1";
}

/**
 * The port the primary server binds. `serve.ts` defaults `LFG_PORT` to this, so
 * "is this the primary?" and "is this on the canonical port?" are the same
 * question.
 */
export const CANONICAL_SERVE_PORT = 8766;

/**
 * Whether THIS server should push to real devices.
 *
 * Agents routinely start a second `lfg serve` on a spare port to poke at an
 * endpoint. That scratch server reads the same `~/.lfg` token store as the
 * primary, so it happily sent real APNs Live Activity pushes to a real phone —
 * with its own in-memory `active.current`, meaning two watchers fighting over one
 * card. One was found doing exactly that mid-investigation.
 *
 * So: default to pushing only from the canonical port, and make the override
 * explicit in both directions (`LFG_PUSH_WATCHER=1` for a primary deliberately
 * moved to another port, `=0` to silence one that is on the canonical port).
 */
export function pushWatcherEnabled(port: number, env = process.env): boolean {
  if (env.LFG_PUSH_WATCHER === "1") return true;
  if (env.LFG_PUSH_WATCHER === "0") return false;
  return port === CANONICAL_SERVE_PORT;
}

/**
 * Start the background watcher. No-op (and self-stopping) when APNs isn't
 * configured, so an install without push credentials pays nothing. Safe to call
 * repeatedly — only one interval runs.
 */
export function startPushWatcher(
  log: (line: string) => void = () => {},
  injected: StartPushWatcherDeps = {},
): void {
  if (timer) return;
  const cfg = apnsConfigFromEnv();
  if (!cfg) return; // push not configured → feature is off
  const prior = new Map<string, PriorState>();
  const active = fleetActive;
  fleetEndedReported = false;
  let fleetActiveLoaded = false;
  const fleetActiveLoad = loadFleetActivityActive()
    .then((loaded) => {
      // A client "ended" report that landed mid-load is NEWER than what is on
      // disk. Honour it and drop the stale snapshot.
      if (!fleetEndedReported) active.current = loaded;
      fleetActiveLoaded = true;
    })
    .catch(() => {
      fleetActiveLoaded = true;
    });
  const deps: TickDeps = {
    sessions: listSessions,
    observe: observeSession,
    devices: listDevices,
    cfg,
    send: sendApns,
    onDeadToken: unregisterDevice,
    head: injected.head,
    hostId: injected.hostId,
    hostName: injected.hostName,
    log,
  };
  if (liveActivitiesEnabled()) {
    deps.liveActivities = {
      active,
      pushToStartTokens: listPushToStartTokens,
      activityUpdateTokens: listActivityUpdateTokens,
      send: sendLiveActivity,
      onDeadToken: removeLiveActivityToken,
      persistActive: saveFleetActivityActive,
    };
  }
  let running = false;
  timer = setInterval(async () => {
    if (running) return; // skip if the previous tick is still going (slow panes)
    running = true;
    try {
      if (deps.liveActivities && !fleetActiveLoaded) await fleetActiveLoad;
      await runPushTick(prior, deps);
    } catch (e) {
      log(`[push] tick error: ${(e as Error).message}`);
    } finally {
      running = false;
    }
  }, 2000);
  log("[push] watcher started");
}

export function stopPushWatcher(): void {
  if (timer) clearInterval(timer);
  timer = null;
}

/** Whether push is configured at all (drives the /api/push/health response). */
export function pushConfigured(): boolean {
  return apnsConfigFromEnv() !== null;
}
