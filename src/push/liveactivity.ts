// Pure APNs Live Activity payload builders plus a thin sender wrapper over the
// shared APNs JWT/HTTP2 machinery in apns.ts.
import {
  sendApnsRequest,
  type ApnsConfig,
  type ApnsResult,
  type ApnsTransport,
} from "./apns.ts";

export const LIVE_ACTIVITY_ATTRIBUTES_TYPE = "LFGSessionAttributes";
export const DEFAULT_APNS_TOPIC = "dev.omg.lfg";

export type LiveActivityContentState = {
  title: string;
  state: "working" | "blocked" | "idle";
  sid: string;
  since: number;
};

export type LiveActivityStartSession = LiveActivityContentState & {
  hostName: string;
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
    attributes?: { sid: string; hostName: string };
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

function contentState(input: LiveActivityContentState): LiveActivityContentState {
  return {
    title: input.title,
    state: input.state,
    sid: input.sid,
    since: input.since,
  };
}

export function buildStart(
  session: LiveActivityStartSession,
  attributesType = LIVE_ACTIVITY_ATTRIBUTES_TYPE,
): LiveActivityPush {
  const state = contentState(session);
  return {
    headers: headers(),
    body: {
      aps: {
        timestamp: state.since,
        event: "start",
        "content-state": state,
        "attributes-type": attributesType,
        attributes: { sid: state.sid, hostName: session.hostName },
        alert: {
          title: session.alertTitle ?? state.title,
          body: session.alertBody ?? "LFG session is working.",
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
        timestamp: state.since,
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
        timestamp: state?.since ?? dismissalDate ?? 0,
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
