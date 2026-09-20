// APNs from a Worker: ES256 provider token via WebCrypto, HTTP/2 via fetch.

export type ApnsEnv = "production" | "sandbox";
export type ApnsSecrets = { APNS_KEY_P8: string; APNS_KEY_ID: string; APNS_TEAM_ID: string; APNS_TOPIC: string };
export type ApnsResult = { ok: boolean; status: number; reason?: string };

const b64url = (bytes: ArrayBuffer | Uint8Array | string): string => {
  const u8 = typeof bytes === "string" ? new TextEncoder().encode(bytes) : new Uint8Array(bytes as ArrayBuffer);
  let s = "";
  for (const b of u8) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

let cached: { jwt: string; at: number; kid: string } | null = null;

/** Provider token. Apple accepts one for up to an hour and throttles re-minting
 *  ("TooManyProviderTokenUpdates"), so it is reused for 40 minutes. */
export async function providerToken(s: ApnsSecrets, nowMs = Date.now()): Promise<string> {
  if (cached && cached.kid === s.APNS_KEY_ID && nowMs - cached.at < 40 * 60_000) return cached.jwt;
  const pem = s.APNS_KEY_P8.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const input = `${b64url(JSON.stringify({ alg: "ES256", kid: s.APNS_KEY_ID }))}.${b64url(
    JSON.stringify({ iss: s.APNS_TEAM_ID, iat: Math.floor(nowMs / 1000) }),
  )}`;
  // WebCrypto ECDSA signatures are already IEEE P1363 (r||s), which is what JWS wants.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  cached = { jwt: `${input}.${b64url(sig)}`, at: nowMs, kid: s.APNS_KEY_ID };
  return cached.jwt;
}

const host = (env: ApnsEnv) => (env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com");

async function post(url: string, headers: Record<string, string>, body: unknown): Promise<ApnsResult> {
  try {
    const r = await fetch(url, { method: "POST", headers, body: JSON.stringify(body) });
    if (r.ok) return { ok: true, status: r.status };
    let reason: string | undefined;
    try { reason = ((await r.json()) as { reason?: string }).reason; } catch { /* non-JSON */ }
    return { ok: false, status: r.status, reason };
  } catch (e) {
    return { ok: false, status: 0, reason: String(e).slice(0, 160) };
  }
}

/** Push-to-start (or any per-token Live Activity push). */
export async function sendToToken(s: ApnsSecrets, env: ApnsEnv, token: string, body: unknown): Promise<ApnsResult> {
  return post(`https://${host(env)}/3/device/${token}`, {
    authorization: `bearer ${await providerToken(s)}`,
    "apns-topic": `${s.APNS_TOPIC}.push-type.liveactivity`,
    "apns-push-type": "liveactivity",
    "apns-priority": "10",
    "apns-expiration": "0",
  }, body);
}

/** Broadcast to every card subscribed to the channel. */
export async function sendToChannel(s: ApnsSecrets, env: ApnsEnv, channelId: string, body: unknown, priority: 5 | 10): Promise<ApnsResult> {
  return post(`https://${host(env)}/4/broadcasts/apps/${s.APNS_TOPIC}`, {
    authorization: `bearer ${await providerToken(s)}`,
    "apns-channel-id": channelId,
    "apns-push-type": "liveactivity",
    "apns-priority": String(priority),
    // Stored by the channel's "most recent message" policy for a card that is
    // briefly offline; an hour is plenty for a fleet status.
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
  }, body);
}
