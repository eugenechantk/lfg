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
  };
};

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
