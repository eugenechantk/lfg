// Pure APNs Live Activity payload builders plus a thin sender wrapper over the
// shared APNs JWT/HTTP2 machinery in apns.ts.
import {
  sendApnsRequest,
  type ApnsConfig,
  type ApnsResult,
  type ApnsTransport,
} from "./apns.ts";

export const LIVE_ACTIVITY_ATTRIBUTES_TYPE = "LFGFleetAttributes";
export const DEFAULT_APNS_TOPIC = "dev.omg.lfg";

/// One row of the aggregate card. `state` mirrors the client enum — note it is
/// `needsInput`, not `blocked`: `blocked` means *paused* on the client and is a
/// different colour.
export type LiveActivityRow = {
  sid: string;
  title: string;
  state: "working" | "needsInput";
  since: number;
};

/// Content state of the single fleet Live Activity. There is deliberately no
/// "unread" count: unread is a per-device client concept derived from *idle*
/// sessions, so it is neither active nor knowable here.
export type LiveActivityContentState = {
  working: number;
  needsInput: number;
  rows: LiveActivityRow[];
  more: number;
  updatedAt: number;
};

export type LiveActivityStartFleet = {
  contentState: LiveActivityContentState;
  fleetId?: string;
  alertTitle?: string;
  alertBody?: string;
};

export type LiveActivityHeaders = {
  "apns-push-type": "liveactivity";
  "apns-topic": string;
  "apns-priority": 10;
};

export type LiveActivityEvent = "start" | "update" | "end";

export type LiveActivityBody = {
  aps: {
    timestamp: number;
    event: LiveActivityEvent;
    "content-state"?: LiveActivityContentState;
    "attributes-type"?: string;
    attributes?: { fleetId: string };
    alert?: { title: string; body: string };
    "dismissal-date"?: number;
    /// Orders this app's own Live Activities (Lock Screen order, island pick).
    /// Does NOT affect placement against other apps' activities — see `relevanceScore`.
    "relevance-score"?: number;
  };
};

/**
 * Relevance for the fleet card. NOTE (2026-09-20): this ranks Live Activities
 * of the SAME app only — "the system shows the Live Activity with the highest
 * relevance score in the Dynamic Island" is about *your* activities. Which app's
 * card is attached to the island and which is the detached bubble is the
 * system's choice ("The system chooses a Live Activity from one app to appear
 * attached … while it presents a Live Activity from another app detached"), and
 * no API influences it. Kept because it is harmless and correct should the app
 * ever run two cards; a fleet waiting on a human outranks one merely working.
 * The app mirrors this in `FleetActivityController`.
 */
export function relevanceScore(state: Pick<LiveActivityContentState, "needsInput">): number {
  return state.needsInput > 0 ? 100 : 90;
}

export type LiveActivityPush = {
  headers: LiveActivityHeaders;
  body: LiveActivityBody;
};

export function liveActivityTopic(bundleId: string): string {
  return `${bundleId}.push-type.liveactivity`;
}

function headers(bundleId = DEFAULT_APNS_TOPIC): LiveActivityHeaders {
  return {
    "apns-push-type": "liveactivity",
    "apns-topic": liveActivityTopic(bundleId),
    "apns-priority": 10,
  };
}

// Normalises to exactly the wire shape, dropping anything extra a caller passed.
function contentState(input: LiveActivityContentState): LiveActivityContentState {
  return {
    working: input.working,
    needsInput: input.needsInput,
    rows: input.rows.map((r) => ({
      sid: r.sid,
      title: r.title,
      state: r.state,
      since: r.since,
    })),
    more: input.more,
    updatedAt: input.updatedAt,
  };
}

export function buildStart(
  fleet: LiveActivityStartFleet,
  attributesType = LIVE_ACTIVITY_ATTRIBUTES_TYPE,
): LiveActivityPush {
  const state = contentState(fleet.contentState);
  return {
    headers: headers(),
    body: {
      aps: {
        timestamp: state.updatedAt,
        event: "start",
        "content-state": state,
        "relevance-score": relevanceScore(state),
        "attributes-type": attributesType,
        attributes: { fleetId: fleet.fleetId ?? "fleet" },
        alert: {
          title: fleet.alertTitle ?? "lfg",
          body: fleet.alertBody ?? "LFG sessions are active.",
        },
      },
    },
  };
}

export function buildUpdate(content: LiveActivityContentState): LiveActivityPush {
  const state = contentState(content);
  return {
    headers: headers(),
    body: {
      aps: {
        timestamp: state.updatedAt,
        event: "update",
        "content-state": state,
        "relevance-score": relevanceScore(state),
      },
    },
  };
}

export function buildEnd(
  content?: LiveActivityContentState,
  dismissalDate?: number,
): LiveActivityPush {
  const state = content ? contentState(content) : undefined;
  return {
    headers: headers(),
    body: {
      aps: {
        timestamp: state?.updatedAt ?? dismissalDate ?? 0,
        event: "end",
        ...(state ? { "content-state": state } : {}),
        ...(typeof dismissalDate === "number" ? { "dismissal-date": dismissalDate } : {}),
      },
    },
  };
}

function withTopic(push: LiveActivityPush, bundleId: string): LiveActivityPush {
  return {
    ...push,
    headers: { ...push.headers, "apns-topic": liveActivityTopic(bundleId) },
  };
}

export async function sendLiveActivity(
  device: { token: string; env: "sandbox" | "production" },
  push: LiveActivityPush,
  cfg: ApnsConfig,
  transport?: ApnsTransport,
): Promise<ApnsResult> {
  const request = withTopic(push, cfg.topic);
  return sendApnsRequest(
    device,
    {
      topic: request.headers["apns-topic"],
      pushType: request.headers["apns-push-type"],
      priority: request.headers["apns-priority"],
      body: JSON.stringify(request.body),
    },
    cfg,
    transport,
  );
}
