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
  LIVE_ACTIVITY_ATTRIBUTES_TYPE,
  buildEnd,
  buildStart,
  buildUpdate,
  sendLiveActivity,
  type LiveActivityContentState,
  type LiveActivityPush,
} from "./liveactivity.ts";
import { unregisterDevice } from "./store.ts";

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

export type LiveActivityActive = {
  startedAt: number;
  contentState?: LiveActivityContentState;
};

export type LiveActivityAction = {
  event: "start" | "update" | "end";
  push: LiveActivityPush;
};

export type LiveActivityDecision = {
  action: LiveActivityAction | null;
  nextActive: LiveActivityActive | null;
};

function liveActivityState(next: SessionState): LiveActivityContentState["state"] {
  if (next.busy) return "working";
  if (next.promptPresent) return "blocked";
  return "idle";
}

function sameContentState(a: LiveActivityContentState | undefined, b: LiveActivityContentState): boolean {
  return !!a && a.title === b.title && a.state === b.state && a.sid === b.sid && a.since === b.since;
}

function buildLiveActivityContentState(
  session: PayloadSessionInput,
  next: SessionState,
  active: LiveActivityActive | null | undefined,
  nowSec: number,
): LiveActivityContentState {
  const sid = session.sessionId ?? "";
  const state = liveActivityState(next);
  const title = clip(session.title || session.tmuxName || sid.slice(0, 8) || "Session", 80);
  const prior = active?.contentState;
  return {
    title,
    state,
    sid,
    since: prior && prior.sid === sid && prior.state === state && prior.title === title ? prior.since : nowSec,
  };
}

export function reduceLiveActivityTransition(args: {
  session: PayloadSessionInput;
  previous: PriorState | null | undefined;
  observed: SessionState;
  active: LiveActivityActive | null | undefined;
  now: number;
  hostName: string;
}): LiveActivityDecision {
  const contentState = buildLiveActivityContentState(
    args.session,
    args.observed,
    args.active,
    args.now,
  );

  if (!args.active) {
    if (!args.observed.busy) return { action: null, nextActive: null };
    return {
      action: {
        event: "start",
        push: buildStart(
          { ...contentState, hostName: args.hostName },
          LIVE_ACTIVITY_ATTRIBUTES_TYPE,
        ),
      },
      nextActive: { startedAt: args.now, contentState },
    };
  }

  const nextActive: LiveActivityActive = { ...args.active, contentState };
  const idleForTwoTicks =
    !args.observed.busy &&
    !args.observed.promptPresent &&
    !!args.previous &&
    !args.previous.busy &&
    !args.previous.promptPresent;
  if (idleForTwoTicks) {
    const endState = { ...contentState, since: args.now };
    return {
      action: { event: "end", push: buildEnd(endState, args.now) },
      nextActive: null,
    };
  }

  const blockedFromBusy = !!args.previous?.busy && !args.observed.busy && args.observed.promptPresent;
  const contentChanged = !sameContentState(args.active.contentState, contentState);
  if (blockedFromBusy || (contentChanged && contentState.state !== "idle")) {
    return {
      action: { event: "update", push: buildUpdate(contentState) },
      nextActive,
    };
  }

  return { action: null, nextActive };
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
  if (!s.tmuxTarget) {
    const entry = s.sessionId ? findEntryByAnyId(s.sessionId) : null;
    return { busy: entry ? entry.busy : false, promptPresent: false };
  }
  const pane = await capturePaneAsync(s.tmuxTarget);
  const tp = s.sessionId ? await resolveTranscript(s.sessionId) : null;
  let prompt: PendingPrompt | PanePrompt | null = tp ? await pendingToolPrompt(tp) : null;
  if (!prompt && pane) prompt = parsePrompt(pane);
  const busy = pane ? isBusy(pane) : false;
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
    active: Map<string, LiveActivityActive>;
    pushToStartTokens: () => Promise<Array<{ token: string; env: "sandbox" | "production" }>>;
    updateTokensForSession: (
      sessionId: string,
    ) => Promise<Array<{ token: string; env: "sandbox" | "production" }>>;
    send: (
      device: { token: string; env: "sandbox" | "production" },
      push: LiveActivityPush,
      cfg: ApnsConfig,
    ) => Promise<{ ok: boolean; status: number; reason?: string }>;
    onDeadToken?: (token: string) => Promise<void> | void;
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
  sid: string,
  decision: LiveActivityDecision,
  deps: NonNullable<TickDeps["liveActivities"]>,
  cfg: ApnsConfig,
  startTokens: Array<{ token: string; env: "sandbox" | "production" }>,
  log?: (line: string) => void,
): Promise<void> {
  if (!decision.action) {
    if (decision.nextActive) deps.active.set(sid, decision.nextActive);
    else deps.active.delete(sid);
    return;
  }

  if (decision.action.event === "start") {
    const sent = await sendLiveActivityToTokens(startTokens, decision.action.push, deps, cfg, log);
    if (sent > 0 && decision.nextActive) deps.active.set(sid, decision.nextActive);
    return;
  }

  const updateTokens = await deps.updateTokensForSession(sid);
  if (!updateTokens.length) return;
  const sent = await sendLiveActivityToTokens(updateTokens, decision.action.push, deps, cfg, log);
  if (sent <= 0) return;
  if (decision.nextActive) deps.active.set(sid, decision.nextActive);
  else deps.active.delete(sid);
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
    if (liveActivities) {
      const decision = reduceLiveActivityTransition({
        session: s,
        previous: prev,
        observed: state,
        active: liveActivities.active.get(sid),
        now: Math.floor(observedAt / 1000),
        hostName: deps.hostName?.() ?? "lfg",
      });
      await applyLiveActivityDecision(
        sid,
        decision,
        liveActivities,
        deps.cfg,
        liveStartTokens,
        deps.log,
      );
    }
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
    for (const k of [...liveActivities.active.keys()]) if (!seen.has(k)) liveActivities.active.delete(k);
  }
}

let timer: ReturnType<typeof setInterval> | null = null;
type StartPushWatcherDeps = Pick<Partial<TickDeps>, "head" | "hostId" | "hostName">;

export function liveActivitiesEnabled(env = process.env): boolean {
  return env.LFG_LIVE_ACTIVITIES === "1";
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
  const active = new Map<string, LiveActivityActive>();
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
      updateTokensForSession: listActivityUpdateTokens,
      send: sendLiveActivity,
      onDeadToken: removeLiveActivityToken,
    };
  }
  let running = false;
  timer = setInterval(async () => {
    if (running) return; // skip if the previous tick is still going (slow panes)
    running = true;
    try {
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
