// APNs sender — token-based (.p8 / JWT ES256) auth, HTTP/2 to Apple's gateway.
// No third-party push library: Bun's node:crypto signs the ES256 JWT and fetch
// speaks HTTP/2 to the APNs endpoints. The transport is injectable so the watcher
// and its tests can run without real credentials or network.
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";
import http2 from "node:http2";

export type ApnsConfig = {
  key: string; // .p8 PEM contents
  keyId: string;
  teamId: string;
  topic: string; // bundle id, e.g. dev.omg.lfg
};

// A compact snapshot of the session, carried in the push so the client can
// render the session screen instantly on tap — before the (re)connect + refresh
// round-trip completes. Small text fields only; APNs caps the payload at 4KB.
export type ApnsPayloadSession = {
  id: string;
  title?: string;
  project?: string | null;
  cwd?: string | null;
  agent?: string;
  model?: string | null;
  status?: string | null;
  lastActivityAt?: number | null;
};

export type ApnsPayload = {
  title: string;
  body: string;
  sid: string; // session id, for deep-linking + thread grouping
  kind: "needs-input" | "finished";
  session?: ApnsPayloadSession;
  hostId?: string;
  seq?: number;
};

/**
 * `headers` carries the APNs RESPONSE headers, and only the channel-management
 * calls need them: channel creation returns the new id in `apns-channel-id`
 * rather than in the (empty) body. Device sends leave it undefined.
 */
export type ApnsResult = {
  ok: boolean;
  status: number;
  reason?: string;
  headers?: Record<string, string>;
  body?: string;
};
export type ApnsPushType = "alert" | "liveactivity";

/**
 * A raw HTTP/2 request to one of Apple's APNs endpoints.
 *
 * The device path (`/3/device/<token>`) is no longer the only shape we speak:
 * broadcast publishes to `/4/broadcasts/apps/<bundleId>` on the normal gateway,
 * and channel management speaks to `api-manage-broadcast[.sandbox].push.apple.com`
 * on a NON-443 port (2195 sandbox, 2196 production) with GET and DELETE as well
 * as POST. Rather than duplicate the connection pooling, timeout and eviction
 * rules that the device path learned the hard way, every shape goes through one
 * request function.
 */
export type ApnsHttpRequest = {
  host: string;
  /// Defaults to 443. Channel management uses 2195/2196.
  port?: number;
  method: "POST" | "GET" | "DELETE";
  path: string;
  /// Everything beyond `:method`, `:path` and `authorization`.
  headers?: Record<string, string | number>;
  jwt: string;
  body?: string;
};

export type ApnsWireRequest = {
  topic: string;
  pushType: ApnsPushType;
  priority?: number;
  body: string;
};

export type ApnsTransport = (args: {
  host: string;
  token: string;
  topic: string;
  pushType: ApnsPushType;
  priority?: number;
  jwt: string;
  body: string;
}) => Promise<ApnsResult>;

/**
 * Read APNs config from the environment. `LFG_APNS_KEY` may be either the inline
 * .p8 PEM or a path to the .p8 file. Returns null when push isn't configured, so
 * callers (the watcher, the /health endpoint) can treat push as a no-op feature.
 */
export function apnsConfigFromEnv(env = process.env): ApnsConfig | null {
  const rawKey = env.LFG_APNS_KEY?.trim();
  const keyId = env.LFG_APNS_KEY_ID?.trim();
  const teamId = env.LFG_APNS_TEAM_ID?.trim();
  if (!rawKey || !keyId || !teamId) return null;
  let key = rawKey;
  // Inline PEM begins with the PKCS#8 header; otherwise treat it as a file path.
  if (!rawKey.includes("BEGIN PRIVATE KEY")) {
    try {
      key = readFileSync(rawKey, "utf8");
    } catch {
      return null;
    }
  }
  return {
    key,
    keyId,
    teamId,
    topic: env.LFG_APNS_TOPIC?.trim() || "dev.omg.lfg",
  };
}

function b64url(buf: Buffer): string {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// APNs JWTs are valid up to 60 min and must not be minted more than once every
// 20 min; cache and reuse one for ~50 min.
let cached: { jwt: string; mintedAt: number; keyId: string } | null = null;
const JWT_TTL_MS = 50 * 60 * 1000;

export function apnsJwt(cfg: ApnsConfig, nowMs = Date.now()): string {
  if (cached && cached.keyId === cfg.keyId && nowMs - cached.mintedAt < JWT_TTL_MS) {
    return cached.jwt;
  }
  const header = b64url(Buffer.from(JSON.stringify({ alg: "ES256", kid: cfg.keyId })));
  const claims = b64url(
    Buffer.from(JSON.stringify({ iss: cfg.teamId, iat: Math.floor(nowMs / 1000) })),
  );
  const signingInput = `${header}.${claims}`;
  const keyObj = createPrivateKey(cfg.key);
  // ECDSA P-256 + SHA-256, JOSE raw (R||S) signature format — Node defaults to DER.
  const sig = sign("sha256", Buffer.from(signingInput), { key: keyObj, dsaEncoding: "ieee-p1363" });
  const jwt = `${signingInput}.${b64url(sig)}`;
  cached = { jwt, mintedAt: nowMs, keyId: cfg.keyId };
  return jwt;
}

/** Reset the cached JWT (used by tests). */
export function _resetApnsJwtCache(): void {
  cached = null;
}

function host(env: "sandbox" | "production"): string {
  return env === "production" ? "api.push.apple.com" : "api.development.push.apple.com";
}

/**
 * One long-lived HTTP/2 session per APNs host, reused across sends.
 *
 * The transport used to `http2.connect` + `close` PER PUSH. Apple explicitly
 * asks clients to hold connections open and treats rapid connection churn as
 * abuse — and the delivery trace shows the price: 609 of 809 logged failures
 * were `status 0` "socket disconnected before secure TLS connection was
 * established". Those weren't network weather; they were the churn itself.
 * A session that errors, closes, or receives GOAWAY is dropped from the pool
 * and the next send dials fresh.
 */
const apnsSessions = new Map<string, http2.ClientHttp2Session>();

// Keyed by host AND port: channel management shares no connection with the push
// gateway, and `api-manage-broadcast…:2195` and `:2196` are different servers.
function apnsSession(host: string, port = 443): http2.ClientHttp2Session {
  const key = `${host}:${port}`;
  const existing = apnsSessions.get(key);
  if (existing && !existing.closed && !existing.destroyed) return existing;
  const session = http2.connect(`https://${host}:${port}`);
  const drop = () => {
    if (apnsSessions.get(key) === session) apnsSessions.delete(key);
  };
  // 'error' needs a listener even when idle or Node crashes the process; the
  // in-flight request observes the same failure through its own 'error' event.
  session.on("error", drop);
  session.on("close", drop);
  session.on("goaway", () => session.close());
  apnsSessions.set(key, session);
  return session;
}

// A hung request must not wedge the push watcher: its tick loop skips while a
// previous tick is still running, so one stalled stream would silently stop
// ALL pushes. Generous bound — APNs answers in well under a second.
const APNS_REQUEST_TIMEOUT_MS = 10_000;

/**
 * One HTTP/2 request to APNs, over the pooled session.
 *
 * `ok` is true for any 2xx, not only 200: channel creation answers **201**, and
 * channel deletion answers **204**, so pinning success to 200 would report every
 * successful management call as a failure.
 */
function apnsHttpAttempt({
  host,
  port = 443,
  method,
  path,
  headers: extra,
  jwt,
  body,
}: ApnsHttpRequest): Promise<ApnsResult> {
  const key = `${host}:${port}`;
  return new Promise<ApnsResult>((resolve) => {
    let settled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const done = (r: ApnsResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(r);
    };
    let session: http2.ClientHttp2Session | undefined;
    let req: http2.ClientHttp2Stream;
    const evict = () => {
      if (session && apnsSessions.get(key) === session) apnsSessions.delete(key);
      try {
        session?.destroy();
      } catch {}
    };
    try {
      session = apnsSession(host, port);
      const h: http2.OutgoingHttpHeaders = {
        ":method": method,
        ":path": path,
        authorization: `bearer ${jwt}`,
        ...(body !== undefined ? { "content-type": "application/json" } : {}),
        ...(extra ?? {}),
      };
      req = session.request(h);
    } catch (e) {
      // The session refused to even open a stream — it is not coming back.
      evict();
      return done({ ok: false, status: 0, reason: (e as Error).message });
    }
    timer = setTimeout(() => {
      // A timed-out stream means the SESSION is suspect (half-dead TCP path);
      // evict it so the retry and later sends dial fresh instead of queueing
      // 10s stalls behind the same wedged connection.
      req.close(http2.constants.NGHTTP2_CANCEL);
      evict();
      done({ ok: false, status: 0, reason: "request timeout" });
    }, APNS_REQUEST_TIMEOUT_MS);
    let status = 0;
    let responseHeaders: Record<string, string> = {};
    let data = "";
    req.on("response", (h) => {
      status = Number(h[":status"]) || 0;
      responseHeaders = Object.fromEntries(
        Object.entries(h)
          .filter(([k]) => !k.startsWith(":"))
          .map(([k, v]) => [k, Array.isArray(v) ? (v[0] ?? "") : String(v ?? "")]),
      );
    });
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      data += chunk;
    });
    req.on("end", () => {
      if (status >= 200 && status < 300) {
        return done({ ok: true, status, headers: responseHeaders, body: data });
      }
      let reason: string | undefined;
      try {
        reason = (JSON.parse(data) as { reason?: string }).reason;
      } catch {}
      done({ ok: false, status, reason, headers: responseHeaders, body: data });
    });
    req.on("error", (e) => done({ ok: false, status: 0, reason: (e as Error).message }));
    if (body !== undefined) req.end(body);
    else req.end();
  });
}

function apnsAttempt({
  host,
  token,
  topic,
  pushType,
  priority,
  jwt,
  body,
}: Parameters<ApnsTransport>[0]): Promise<ApnsResult> {
  return apnsHttpAttempt({
    host,
    method: "POST",
    path: `/3/device/${token}`,
    headers: {
      "apns-topic": topic,
      "apns-push-type": pushType,
      ...(typeof priority === "number" ? { "apns-priority": priority } : {}),
    },
    jwt,
    body,
  });
}

/** Issue an arbitrary APNs request with the same transient-failure retry as sends. */
export function apnsHttpRequest(request: ApnsHttpRequest): Promise<ApnsResult> {
  return sendWithTransientRetry(() => apnsHttpAttempt(request));
}

/**
 * Retry ONLY transport-level failures (`status 0` — TLS/socket/timeout, i.e.
 * APNs never spoke). Any real HTTP status, including 410/400/500, is APNs'
 * answer and is authoritative — retrying those would double-send alerts on
 * flaky 5xxs and mask dead tokens. Exported for tests; the delay parameter
 * exists so tests don't sleep.
 */
export async function sendWithTransientRetry(
  fn: () => Promise<ApnsResult>,
  attempts = 2,
  delayMs = 250,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
): Promise<ApnsResult> {
  let last: ApnsResult = { ok: false, status: 0 };
  for (let i = 0; i < attempts; i++) {
    last = await fn();
    if (last.ok || last.status !== 0) return last;
    if (i < attempts - 1) await sleep(delayMs);
  }
  return last;
}

// Default transport: real HTTP/2 POST to APNs over the pooled session, with one
// transient retry. APNs is HTTP/2-only and `fetch` (Bun's, as of 1.3.x) chokes
// on its responses — "Malformed_HTTP_Response" — so we use node:http2 directly.
const realTransport: ApnsTransport = (args) => sendWithTransientRetry(() => apnsAttempt(args));

/** Serialize an APNs payload into the on-the-wire JSON body. */
export function apnsBody(payload: ApnsPayload): string {
  return JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      "thread-id": payload.sid,
      "content-available": 1,
    },
    sid: payload.sid,
    kind: payload.kind,
    ...(payload.hostId ? { hostId: payload.hostId } : {}),
    ...(typeof payload.seq === "number" ? { seq: payload.seq } : {}),
    // Compact session snapshot for instant-render on tap (omitted when absent).
    ...(payload.session ? { session: payload.session } : {}),
  });
}

export async function sendApns(
  device: { token: string; env: "sandbox" | "production" },
  payload: ApnsPayload,
  cfg: ApnsConfig,
  transport: ApnsTransport = realTransport,
): Promise<ApnsResult> {
  return sendApnsRequest(
    device,
    { topic: cfg.topic, pushType: "alert", body: apnsBody(payload) },
    cfg,
    transport,
  );
}

export async function sendApnsRequest(
  device: { token: string; env: "sandbox" | "production" },
  request: ApnsWireRequest,
  cfg: ApnsConfig,
  transport: ApnsTransport = realTransport,
): Promise<ApnsResult> {
  return transport({
    host: host(device.env),
    token: device.token,
    topic: request.topic,
    pushType: request.pushType,
    priority: request.priority,
    jwt: apnsJwt(cfg),
    body: request.body,
  });
}
