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
};

export type ApnsResult = { ok: boolean; status: number; reason?: string };

export type ApnsTransport = (args: {
  host: string;
  token: string;
  topic: string;
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

// Default transport: real HTTP/2 POST to APNs. APNs is HTTP/2-only and `fetch`
// (Bun's, as of 1.3.x) chokes on its responses — "Malformed_HTTP_Response" — so
// we use node:http2 directly, which speaks the protocol cleanly.
const realTransport: ApnsTransport = ({ host, token, topic, jwt, body }) =>
  new Promise<ApnsResult>((resolve) => {
    let settled = false;
    const done = (r: ApnsResult) => {
      if (settled) return;
      settled = true;
      resolve(r);
    };
    let client: http2.ClientHttp2Session;
    try {
      client = http2.connect(`https://${host}`);
    } catch (e) {
      return done({ ok: false, status: 0, reason: (e as Error).message });
    }
    client.on("error", (e) => done({ ok: false, status: 0, reason: (e as Error).message }));
    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "content-type": "application/json",
    });
    let status = 0;
    let data = "";
    req.on("response", (headers) => {
      status = Number(headers[":status"]) || 0;
    });
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      data += chunk;
    });
    req.on("end", () => {
      client.close();
      if (status === 200) return done({ ok: true, status });
      let reason: string | undefined;
      try {
        reason = (JSON.parse(data) as { reason?: string }).reason;
      } catch {}
      done({ ok: false, status, reason });
    });
    req.on("error", (e) => done({ ok: false, status: 0, reason: (e as Error).message }));
    req.end(body);
  });

/** Serialize an APNs payload into the on-the-wire JSON body. */
export function apnsBody(payload: ApnsPayload): string {
  return JSON.stringify({
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      "thread-id": payload.sid,
    },
    sid: payload.sid,
    kind: payload.kind,
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
  return transport({
    host: host(device.env),
    token: device.token,
    topic: cfg.topic,
    jwt: apnsJwt(cfg),
    body: apnsBody(payload),
  });
}
