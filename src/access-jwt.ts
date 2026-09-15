// Cloudflare Access JWT verification for endpoints that must not rely on the
// edge alone.
//
// The lfg API is unauthenticated by design (SECURITY.md): it binds 127.0.0.1 and
// remote clients arrive through the Cloudflare tunnel, where Access rejects
// anyone without a credential. For a shell (`/api/term`) that single layer is
// too thin: a mistake in the Access policy would make it a public shell. So a
// request that came through the tunnel (Cloudflare always sets
// `cf-connecting-ip`) must also carry a `Cf-Access-Jwt-Assertion` that verifies
// against the team's signing keys. A local request, which has no such header,
// is unchanged.

export type AccessConfig = { issuer: string; aud: string };

/** An RSA signing key as published in the Access certs JWKS. */
export type Jwk = { kty?: string; n?: string; e?: string; kid?: string; alg?: string; use?: string; key_ops?: string[] };
export type JwksSource = (issuer: string, opts?: { refresh?: boolean }) => Promise<Jwk[]>;
export type AccessResult = { ok: true } | { ok: false; reason: string };

const CLOCK_SKEW_SEC = 60;

/** `LFG_ACCESS_TEAM_DOMAIN` (bare team name or full issuer URL) + `LFG_ACCESS_AUD`. */
export function accessConfigFromEnv(env: Record<string, string | undefined> = process.env): AccessConfig | null {
  const team = env.LFG_ACCESS_TEAM_DOMAIN?.trim();
  const aud = env.LFG_ACCESS_AUD?.trim();
  if (!team || !aud) return null;
  const issuer = team.includes("://")
    ? team.replace(/\/+$/, "")
    : `https://${team.replace(/\.cloudflareaccess\.com$/, "")}.cloudflareaccess.com`;
  return { issuer, aud };
}

/** JWKS from `<issuer>/cdn-cgi/access/certs`, cached. `refresh` forces a refetch (key rotation). */
export function cachedJwks(fetchImpl: typeof fetch = fetch, ttlMs = 10 * 60_000): JwksSource {
  const cache = new Map<string, { at: number; keys: Jwk[] }>();
  return async (issuer, opts) => {
    const hit = cache.get(issuer);
    if (hit && !opts?.refresh && Date.now() - hit.at < ttlMs) return hit.keys;
    const res = await fetchImpl(`${issuer}/cdn-cgi/access/certs`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`access certs ${res.status}`);
    const body = (await res.json()) as { keys?: Jwk[] };
    const keys = Array.isArray(body.keys) ? body.keys : [];
    cache.set(issuer, { at: Date.now(), keys });
    return keys;
  };
}

function decodePart<T>(part: string): T | null {
  try {
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as T;
  } catch {
    return null;
  }
}

export async function verifyAccessJwt(
  token: string,
  cfg: AccessConfig,
  keys: JwksSource,
  now: number = Date.now(),
): Promise<AccessResult> {
  const parts = token.split(".");
  if (parts.length !== 3 || parts.some((p) => !p)) return { ok: false, reason: "malformed token" };
  const [h, p, s] = parts as [string, string, string];
  const header = decodePart<{ alg?: string; kid?: string }>(h);
  const claims = decodePart<{ iss?: string; aud?: string | string[]; exp?: number; nbf?: number }>(p);
  if (!header || !claims) return { ok: false, reason: "malformed token" };
  // Pin the algorithm: never let the token choose (alg=none / HS256 confusion).
  if (header.alg !== "RS256") return { ok: false, reason: "unsupported alg" };

  let jwk: Jwk | undefined;
  try {
    jwk = (await keys(cfg.issuer)).find((k) => k.kid === header.kid);
    if (!jwk) jwk = (await keys(cfg.issuer, { refresh: true })).find((k) => k.kid === header.kid);
  } catch {
    return { ok: false, reason: "signing keys unavailable" };
  }
  if (!jwk) return { ok: false, reason: "unknown signing key" };

  let valid = false;
  try {
    const { kid: _kid, alg: _alg, use: _use, key_ops: _ops, ...material } = jwk;
    const key = await crypto.subtle.importKey(
      "jwk", material as never, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5", key, Buffer.from(s, "base64url"), new TextEncoder().encode(`${h}.${p}`));
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: "bad signature" };

  const nowSec = now / 1000;
  if (claims.iss !== cfg.issuer) return { ok: false, reason: "wrong issuer" };
  const auds = Array.isArray(claims.aud) ? claims.aud : claims.aud ? [claims.aud] : [];
  if (!auds.includes(cfg.aud)) return { ok: false, reason: "wrong audience" };
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW_SEC < nowSec) return { ok: false, reason: "expired" };
  if (typeof claims.nbf === "number" && claims.nbf - CLOCK_SKEW_SEC > nowSec) return { ok: false, reason: "not yet valid" };
  return { ok: true };
}

/**
 * Local requests pass. Tunnelled requests (`cf-connecting-ip` present) need a
 * valid Access JWT, and are refused outright when verification isn't configured.
 */
export async function authorizeTunnelledRequest(
  req: Request,
  cfg: AccessConfig | null,
  keys: JwksSource,
  now: number = Date.now(),
): Promise<AccessResult> {
  if (!req.headers.has("cf-connecting-ip")) return { ok: true };
  if (!cfg) return { ok: false, reason: "access verification not configured" };
  const token = req.headers.get("cf-access-jwt-assertion");
  if (!token) return { ok: false, reason: "missing access token" };
  return verifyAccessJwt(token, cfg, keys, now);
}
