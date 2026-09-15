import { test, expect, beforeAll } from "bun:test";
import {
  accessConfigFromEnv,
  authorizeTunnelledRequest,
  cachedJwks,
  verifyAccessJwt,
  type AccessConfig,
  type JwksSource,
  type Jwk,
} from "./access-jwt.ts";

const cfg: AccessConfig = {
  issuer: "https://team-x.cloudflareaccess.com",
  aud: "aud-123",
};

let privateKey: CryptoKey;
let otherPrivateKey: CryptoKey;
let jwk: Jwk;
const b64url = (b: ArrayBuffer | Uint8Array | string) =>
  Buffer.from(typeof b === "string" ? b : b instanceof Uint8Array ? b : new Uint8Array(b))
    .toString("base64url");

beforeAll(async () => {
  const alg = { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" };
  const pair = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  const other = await crypto.subtle.generateKey(alg, true, ["sign", "verify"]);
  privateKey = pair.privateKey;
  otherPrivateKey = other.privateKey;
  jwk = { ...(await crypto.subtle.exportKey("jwk", pair.publicKey) as Jwk), kid: "k1" };
});

const now = 1_800_000_000_000;
const keys: JwksSource = async () => [jwk];

async function sign(claims: Record<string, unknown>, opts: { key?: CryptoKey; kid?: string; alg?: string } = {}) {
  const header = b64url(JSON.stringify({ alg: opts.alg ?? "RS256", kid: opts.kid ?? "k1", typ: "JWT" }));
  const payload = b64url(JSON.stringify(claims));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", opts.key ?? privateKey, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(sig)}`;
}

const good = () => ({ iss: cfg.issuer, aud: [cfg.aud], exp: now / 1000 + 600, iat: now / 1000 - 5 });

test("a valid Access JWT verifies", async () => {
  const r = await verifyAccessJwt(await sign(good()), cfg, keys, now);
  expect(r).toEqual({ ok: true });
});

test("string aud is accepted too", async () => {
  const r = await verifyAccessJwt(await sign({ ...good(), aud: cfg.aud }), cfg, keys, now);
  expect(r.ok).toBe(true);
});

test("rejects a token signed by a different key", async () => {
  const r = await verifyAccessJwt(await sign(good(), { key: otherPrivateKey }), cfg, keys, now);
  expect(r).toEqual({ ok: false, reason: "bad signature" });
});

test("rejects wrong audience, wrong issuer, expiry, not-yet-valid", async () => {
  expect((await verifyAccessJwt(await sign({ ...good(), aud: ["other"] }), cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt(await sign({ ...good(), iss: "https://evil.cloudflareaccess.com" }), cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt(await sign({ ...good(), exp: now / 1000 - 120 }), cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt(await sign({ ...good(), nbf: now / 1000 + 600 }), cfg, keys, now)).ok).toBe(false);
});

test("rejects alg none / HS256 and malformed tokens", async () => {
  expect((await verifyAccessJwt(await sign(good(), { alg: "none" }), cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt(await sign(good(), { alg: "HS256" }), cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt("not.a.jwt", cfg, keys, now)).ok).toBe(false);
  expect((await verifyAccessJwt("", cfg, keys, now)).ok).toBe(false);
});

test("rejects an unknown kid", async () => {
  const r = await verifyAccessJwt(await sign(good(), { kid: "nope" }), cfg, keys, now);
  expect(r).toEqual({ ok: false, reason: "unknown signing key" });
});

const req = (headers: Record<string, string>) => new Request("http://127.0.0.1:8766/api/term", { headers });

test("local requests (no cf-connecting-ip) pass without a token or config", async () => {
  expect(await authorizeTunnelledRequest(req({}), null, keys, now)).toEqual({ ok: true });
});

test("tunnelled requests fail closed when Access is not configured", async () => {
  const r = await authorizeTunnelledRequest(req({ "cf-connecting-ip": "1.2.3.4" }), null, keys, now);
  expect(r).toEqual({ ok: false, reason: "access verification not configured" });
});

test("tunnelled requests need a valid Cf-Access-Jwt-Assertion", async () => {
  const tunnelled = { "cf-connecting-ip": "1.2.3.4" };
  expect((await authorizeTunnelledRequest(req(tunnelled), cfg, keys, now)).ok).toBe(false);
  const ok = await authorizeTunnelledRequest(
    req({ ...tunnelled, "cf-access-jwt-assertion": await sign(good()) }), cfg, keys, now);
  expect(ok).toEqual({ ok: true });
});

test("config from env accepts a bare team name or a full issuer URL", () => {
  expect(accessConfigFromEnv({})).toBeNull();
  expect(accessConfigFromEnv({ LFG_ACCESS_TEAM_DOMAIN: "team-x" })).toBeNull();
  expect(accessConfigFromEnv({ LFG_ACCESS_TEAM_DOMAIN: "team-x", LFG_ACCESS_AUD: "aud-123" })).toEqual(cfg);
  expect(accessConfigFromEnv({ LFG_ACCESS_TEAM_DOMAIN: "https://team-x.cloudflareaccess.com/", LFG_ACCESS_AUD: "aud-123" })).toEqual(cfg);
});

test("cachedJwks fetches the certs endpoint once and refetches on demand", async () => {
  const calls: string[] = [];
  const fakeFetch = (async (url: string) => {
    calls.push(String(url));
    return new Response(JSON.stringify({ keys: [jwk] }));
  }) as unknown as typeof fetch;
  const source = cachedJwks(fakeFetch, 60_000);
  expect(await source(cfg.issuer)).toEqual([jwk]);
  expect(await source(cfg.issuer)).toEqual([jwk]);
  expect(calls).toEqual(["https://team-x.cloudflareaccess.com/cdn-cgi/access/certs"]);
  await source(cfg.issuer, { refresh: true });
  expect(calls.length).toBe(2);
});
