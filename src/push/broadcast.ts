// APNs broadcast channels: channel management plus publishing a Live Activity
// update/end to every card subscribed to a channel.
//
// WHY THIS EXISTS. A per-card `activityUpdate` token only reaches the server if
// iOS wakes the app in the background after a push-to-start, and on an idle phone
// that frequently never happens — 9 of 14 starts on 2026-09-19 got no token back.
// Because a dead Live Activity token still answers 200, the server could not even
// tell: it counted the undelivered `end` as delivered and the frozen card stayed
// on the Lock Screen forever. A channel is addressed by id rather than by card, so
// no wake and no registration is involved at any point.
//
// Verified against Apple's docs 2026-09-20:
//   developer.apple.com/documentation/usernotifications/sending-channel-management-requests-to-apns
//   developer.apple.com/documentation/usernotifications/sending-broadcast-push-notification-requests-to-apns
//
// NOTE: broadcast CANNOT start an activity ("You can't use broadcast push
// notifications to start a Live Activity"). Starting still uses the per-device
// push-to-start token; the start payload carries `input-push-channel` so the card
// it creates listens here from birth.
import {
  apnsHttpRequest,
  type ApnsConfig,
  type ApnsHttpRequest,
  type ApnsResult,
  apnsJwt,
} from "./apns.ts";
import type { ApnsEnv } from "./channel-store.ts";
import type { LiveActivityContentState, LiveActivityPush } from "./liveactivity.ts";

/** Injectable so tests never touch the network. */
export type ApnsRequester = (request: ApnsHttpRequest) => Promise<ApnsResult>;

/**
 * Channel management lives on its own hosts, on NON-443 ports that differ per
 * environment. Both the host and the port change between sandbox and production —
 * an easy thing to half-fix, and a wrong port fails like an auth error.
 */
export function manageHost(env: ApnsEnv): string {
  return env === "production"
    ? "api-manage-broadcast.push.apple.com"
    : "api-manage-broadcast.sandbox.push.apple.com";
}

export function managePort(env: ApnsEnv): number {
  return env === "production" ? 2196 : 2195;
}

/**
 * Publishing goes to the ordinary push gateway, not the management host.
 *
 * AMBIGUITY, deliberately overridable: Apple's broadcast page says
 * "Development/Sandbox Environment: api.sandbox.push.apple.com:443" in prose, but
 * every worked example on the same page shows `host = api-broadcast.sandbox.push.apple.com`.
 * We default to the prose (which is also the gateway we already hold a pooled
 * connection to) and leave `LFG_APNS_BROADCAST_HOST` to settle it against the real
 * service without a code change.
 */
export function broadcastHost(env: ApnsEnv, envVars = process.env): string {
  const override = envVars.LFG_APNS_BROADCAST_HOST?.trim();
  if (override) return override;
  return env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
}

/**
 * `1` = Most Recent Message Stored (max 8 h). Policy `0` would buy a higher
 * publishing budget, but storing the most recent message is precisely what this
 * feature is for: a phone that was asleep when the last session finished should
 * still receive that final state when it comes back. The policy is immutable
 * after creation, so changing this needs a new channel.
 */
export const MESSAGE_STORAGE_POLICY = 1 as const;

/** How long a stored update stays worth delivering. */
export const BROADCAST_EXPIRY_UPDATE_S = 60 * 60;

/**
 * An `end` gets the full 8 h window APNs allows. A late update is stale noise, but
 * a late END is still exactly right — it dismisses a card that would otherwise
 * keep claiming work is running.
 */
export const BROADCAST_EXPIRY_END_S = 8 * 60 * 60;

/**
 * Priority 10 counts against the system's Live Activity push budget; priority 5
 * does not, and Apple explicitly recommends a mix to avoid throttling. Only
 * something a human has to act on, or a dismissal, is worth spending budget on.
 */
export function broadcastPriority(
  event: "update" | "end",
  state: Pick<LiveActivityContentState, "needsInput"> | undefined,
): 5 | 10 {
  if (event === "end") return 10;
  return (state?.needsInput ?? 0) > 0 ? 10 : 5;
}

function requireOk(result: ApnsResult, what: string): ApnsResult {
  if (!result.ok) {
    throw new Error(
      `${what} failed: status ${result.status}${result.reason ? ` ${result.reason}` : ""}`,
    );
  }
  return result;
}

export async function createBroadcastChannel(
  cfg: ApnsConfig,
  env: ApnsEnv,
  request: ApnsRequester = apnsHttpRequest,
): Promise<string> {
  const result = requireOk(
    await request({
      host: manageHost(env),
      port: managePort(env),
      method: "POST",
      path: `/1/apps/${cfg.topic}/channels`,
      jwt: apnsJwt(cfg),
      body: JSON.stringify({
        "message-storage-policy": MESSAGE_STORAGE_POLICY,
        "push-type": "LiveActivity",
      }),
    }),
    "channel create",
  );
  // The id comes back in a HEADER; the success body is empty.
  const channelId = result.headers?.["apns-channel-id"]?.trim();
  if (!channelId) {
    throw new Error("channel create returned no channel id header");
  }
  return channelId;
}

export async function listBroadcastChannels(
  cfg: ApnsConfig,
  env: ApnsEnv,
  request: ApnsRequester = apnsHttpRequest,
): Promise<string[]> {
  const result = requireOk(
    await request({
      host: manageHost(env),
      port: managePort(env),
      method: "GET",
      path: `/1/apps/${cfg.topic}/all-channels`,
      jwt: apnsJwt(cfg),
    }),
    "channel list",
  );
  try {
    const parsed = JSON.parse(result.body ?? "{}") as { channels?: string[] };
    return parsed.channels ?? [];
  } catch {
    return [];
  }
}

export async function deleteBroadcastChannel(
  cfg: ApnsConfig,
  env: ApnsEnv,
  channelId: string,
  request: ApnsRequester = apnsHttpRequest,
): Promise<void> {
  requireOk(
    await request({
      host: manageHost(env),
      port: managePort(env),
      method: "DELETE",
      path: `/1/apps/${cfg.topic}/channels`,
      headers: { "apns-channel-id": channelId },
      jwt: apnsJwt(cfg),
    }),
    "channel delete",
  );
}

/**
 * Publish one Live Activity update/end to every card on the channel.
 *
 * Only the push's BODY is reused from the device-path builders; the headers are
 * completely different — the bundle id moves into the path, `apns-topic` is not
 * part of this endpoint at all, and `apns-expiration` is required.
 */
export async function sendBroadcastLiveActivity(
  channel: { env: ApnsEnv; channelId: string },
  push: LiveActivityPush,
  cfg: ApnsConfig,
  request: ApnsRequester = apnsHttpRequest,
  nowS: number = Math.floor(Date.now() / 1000),
): Promise<ApnsResult> {
  const event = push.body.aps.event === "end" ? "end" : "update";
  const ttl = event === "end" ? BROADCAST_EXPIRY_END_S : BROADCAST_EXPIRY_UPDATE_S;
  return request({
    host: broadcastHost(channel.env),
    method: "POST",
    path: `/4/broadcasts/apps/${cfg.topic}`,
    headers: {
      "apns-channel-id": channel.channelId,
      "apns-push-type": "liveactivity",
      "apns-priority": broadcastPriority(event, push.body.aps["content-state"]),
      // Required on this endpoint. A nonzero value is only legal against a
      // stored-message channel, which is what MESSAGE_STORAGE_POLICY creates.
      "apns-expiration": nowS + ttl,
    },
    jwt: apnsJwt(cfg),
    body: JSON.stringify(push.body),
  });
}

/**
 * The channel id for an environment, creating and persisting one on first use.
 *
 * Callers must treat "no channel" as a real, recoverable state rather than an
 * error: the capability is enabled in Apple's developer portal, not in code, so
 * until someone flips it every create returns an APNs error. Returning null lets
 * the server keep delivering everything else instead of crash-looping, and the
 * next tick simply tries again.
 */
export async function ensureBroadcastChannel(
  cfg: ApnsConfig,
  env: ApnsEnv,
  deps: {
    get?: (env: ApnsEnv) => Promise<{ channelId: string } | null>;
    save?: (env: ApnsEnv, channelId: string) => Promise<unknown>;
    create?: (cfg: ApnsConfig, env: ApnsEnv) => Promise<string>;
    log?: (line: string) => void;
  } = {},
): Promise<string | null> {
  const get = deps.get ?? (await import("./channel-store.ts")).getLiveActivityChannel;
  const save = deps.save ?? (await import("./channel-store.ts")).saveLiveActivityChannel;
  const create = deps.create ?? ((c: ApnsConfig, e: ApnsEnv) => createBroadcastChannel(c, e));
  const existing = await get(env);
  if (existing?.channelId) return existing.channelId;
  try {
    const channelId = await create(cfg, env);
    await save(env, channelId);
    return channelId;
  } catch (e) {
    deps.log?.(`[liveactivity] channel create (${env}) failed: ${(e as Error).message}`);
    return null;
  }
}
