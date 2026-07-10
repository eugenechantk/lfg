import { test, expect, describe, afterEach } from "bun:test";
import { generateKeyPairSync, verify } from "node:crypto";
import {
  apnsConfigFromEnv,
  apnsJwt,
  apnsBody,
  sendApns,
  _resetApnsJwtCache,
  type ApnsConfig,
  type ApnsTransport,
} from "./apns.ts";

// A throwaway P-256 keypair so we can sign + verify a real ES256 JWT without a
// real Apple .p8.
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;
const cfg: ApnsConfig = { key: pem, keyId: "ABC123", teamId: "TEAM456", topic: "dev.omg.lfg" };

afterEach(() => _resetApnsJwtCache());

describe("apnsConfigFromEnv", () => {
  test("returns null when unconfigured (SC7)", () => {
    expect(apnsConfigFromEnv({} as NodeJS.ProcessEnv)).toBeNull();
  });

  test("reads inline PEM + ids", () => {
    const c = apnsConfigFromEnv({
      LFG_APNS_KEY: pem,
      LFG_APNS_KEY_ID: "K",
      LFG_APNS_TEAM_ID: "T",
    } as unknown as NodeJS.ProcessEnv);
    expect(c?.keyId).toBe("K");
    expect(c?.topic).toBe("dev.omg.lfg");
  });
});

describe("apnsJwt", () => {
  test("produces a verifiable ES256 JWT with the right header/claims", () => {
    const jwt = apnsJwt(cfg, 1_700_000_000_000);
    const [h, c, sig] = jwt.split(".");
    const header = JSON.parse(Buffer.from(h, "base64url").toString());
    const claims = JSON.parse(Buffer.from(c, "base64url").toString());
    expect(header).toEqual({ alg: "ES256", kid: "ABC123" });
    expect(claims).toEqual({ iss: "TEAM456", iat: 1_700_000_000 });
    // Verify the signature against the public key (raw P1363 → must pass).
    const ok = verify(
      "sha256",
      Buffer.from(`${h}.${c}`),
      { key: publicKey, dsaEncoding: "ieee-p1363" },
      Buffer.from(sig, "base64url"),
    );
    expect(ok).toBe(true);
  });

  test("caches within the TTL and re-mints after it", () => {
    const t0 = 1_700_000_000_000;
    const a = apnsJwt(cfg, t0);
    const b = apnsJwt(cfg, t0 + 60_000); // 1 min later → cached
    expect(b).toBe(a);
    const c = apnsJwt(cfg, t0 + 60 * 60_000); // 60 min later → re-mint
    expect(c).not.toBe(a);
  });
});

describe("sendApns", () => {
  test("hits the sandbox host for a sandbox device and forwards the body", async () => {
    const calls: { host: string; token: string; body: string }[] = [];
    const transport: ApnsTransport = async (a) => {
      calls.push({ host: a.host, token: a.token, body: a.body });
      return { ok: true, status: 200 };
    };
    await sendApns(
      { token: "devtok", env: "sandbox" },
      { title: "T", body: "B", sid: "s1", kind: "finished" },
      cfg,
      transport,
    );
    expect(calls[0].host).toBe("api.development.push.apple.com");
    expect(calls[0].token).toBe("devtok");
    expect(JSON.parse(calls[0].body).aps.alert.title).toBe("T");
  });

  test("uses the production host for a production device", async () => {
    let host = "";
    await sendApns(
      { token: "t", env: "production" },
      { title: "T", body: "B", sid: "s", kind: "finished" },
      cfg,
      async (a) => ((host = a.host), { ok: true, status: 200 }),
    );
    expect(host).toBe("api.push.apple.com");
  });

  test("apnsBody carries thread-id + routing fields", () => {
    const body = JSON.parse(apnsBody({ title: "T", body: "B", sid: "s9", kind: "needs-input" }));
    expect(body.aps["thread-id"]).toBe("s9");
    expect(body.aps["content-available"]).toBe(1);
    expect(body.sid).toBe("s9");
    expect(body.kind).toBe("needs-input");
  });

  test("apnsBody carries optional journal wake keys", () => {
    const body = JSON.parse(
      apnsBody({
        title: "T",
        body: "B",
        sid: "s9",
        kind: "finished",
        hostId: "host-1",
        seq: 42,
      }),
    );
    expect(body.hostId).toBe("host-1");
    expect(body.seq).toBe(42);
  });
});
