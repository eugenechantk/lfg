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

export type LiveActivitySessionState = {
  state: "working" | "blocked" | "finished";
  title: string;
  dir: string;
  host: string;
  since: number;
  updatedAt: number;
  subtitle?: string;
  added?: number;
  removed?: number;
  files?: number;
};

export type LiveActivityStartSession = {
  contentState: LiveActivitySessionState;
  sessionId: string;
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
    "content-state"?: LiveActivitySessionState;
    "attributes-type"?: string;
    attributes?: { sessionId: string };
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

function contentState(input: LiveActivitySessionState): LiveActivitySessionState {
  return {
    state: input.state,
    title: input.title,
    dir: input.dir,
    host: input.host,
    since: input.since,
    updatedAt: input.updatedAt,
    ...(typeof input.subtitle === "string" ? { subtitle: input.subtitle } : {}),
    ...(typeof input.added === "number" ? { added: input.added } : {}),
    ...(typeof input.removed === "number" ? { removed: input.removed } : {}),
    ...(typeof input.files === "number" ? { files: input.files } : {}),
  };
}

export function buildStart(
  session: LiveActivityStartSession,
  attributesType = LIVE_ACTIVITY_ATTRIBUTES_TYPE,
): LiveActivityPush {
  const state = contentState(session.contentState);
  return {
    headers: headers(),
    body: {
      aps: {
        timestamp: state.updatedAt,
        event: "start",
        "content-state": state,
        "attributes-type": attributesType,
        attributes: { sessionId: session.sessionId },
        alert: {
          title: session.alertTitle ?? "lfg",
          body: session.alertBody ?? "LFG session is active.",
        },
      },
    },
  };
}

export function buildUpdate(content: LiveActivitySessionState): LiveActivityPush {
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
  content?: LiveActivitySessionState,
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
