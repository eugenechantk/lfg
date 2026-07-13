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

export type LiveActivityRow = {
  sid: string;
  title: string;
  host: string;
  state: "working" | "blocked" | "idle";
  since: number;
};

export type LiveActivityHostStatus = {
  name: string;
  online: boolean;
};

export type LiveActivityContentState = {
  working: number;
  needsInput: number;
  rows: LiveActivityRow[];
  hosts: LiveActivityHostStatus[];
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

function contentState(input: LiveActivityContentState): LiveActivityContentState {
  return {
    working: input.working,
    needsInput: input.needsInput,
    rows: input.rows.map((row) => ({
      sid: row.sid,
      title: row.title,
      host: row.host,
      state: row.state,
      since: row.since,
    })),
    hosts: input.hosts.map((host) => ({
      name: host.name,
      online: host.online,
    })),
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
          body: fleet.alertBody ?? "LFG agents are active.",
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
