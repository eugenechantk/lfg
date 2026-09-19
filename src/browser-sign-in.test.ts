import { test, expect } from "bun:test";
import {
  BrowserSignInHub,
  validateTransfer,
  signInHTTP,
  allowsSignInAdapter, signInReason } from "./browser-sign-in.ts";
const cookie = {
  name: "session",
  value: "test-secret",
  domain: "portal.example.com",
  hostOnly: true,
  path: "/",
  secure: true,
  httpOnly: true,
};
const payload = () => ({
  targetId: "target",
  url: "https://portal.example.com/",
  domains: ["portal.example.com"],
  cookies: [cookie],
});
test("cookie boundary preserves attributes and rejects widening, public suffixes, insecure URLs and malformed input", () => {
  expect(validateTransfer(payload()).cookies[0]).toEqual(cookie);
  for (const patch of [
    { url: "http://example.com" },
    { domains: ["com"] },
    { cookies: [{ ...cookie, domain: "other.example.com" }] },
    { cookies: [{ ...cookie, path: "bad" }] },
    { cookies: [{ ...cookie, value: "x".repeat(5000) }] },
    { cookies: [] },
    { cookies: [{ ...cookie, expires: 1 }] },
    { cookies: [{ ...cookie, partitionKey: "https://example.com" }] },
  ]) {
    expect(() => validateTransfer({ ...payload(), ...patch })).toThrow();
  }
  expect(
    validateTransfer({
      ...payload(),
      cookies: [{ ...cookie, domain: ".example.com", hostOnly: false }],
      domains: ["example.com"],
    }),
  ).toBeDefined();
});
function fake() {
  return {
    sent: [] as any[],
    closed: false,
    send(s: string) {
      this.sent.push(JSON.parse(s));
      return 1;
    },
    close() {
      this.closed = true;
    },
  };
}
test("only authenticated destinations appear; ack from wrong socket cannot complete import", async () => {
  const hub = new BrowserSignInHub(() => "secret", { timeout: 50 });
  const a = fake(),
    b = fake();
  hub.open(a);
  hub.open(b);
  hub.message(
    a,
    JSON.stringify({
      type: "hello",
      token: "secret",
      name: "Chrome personal",
      kind: "chrome",
    }),
  );
  hub.message(
    b,
    JSON.stringify({
      type: "hello",
      token: "wrong",
      name: "attacker",
      kind: "chrome",
    }),
  );
  expect(b.closed).toBe(true);
  expect(hub.targets()).toHaveLength(1);
  const targetId = hub.targets()[0]!.id;
  const result = hub.transfer({ ...payload(), targetId });
  const job = a.sent.find((x) => x.type === "import");
  hub.message(b, JSON.stringify({ type: "result", id: job.id, installed: 1 }));
  const other = fake();
  hub.open(other);
  hub.message(
    other,
    JSON.stringify({
      type: "hello",
      token: "secret",
      name: "Other browser",
      kind: "playwright",
    }),
  );
  let finished = false;
  void result.then(() => {
    finished = true;
  });
  hub.message(
    other,
    JSON.stringify({ type: "result", id: job.id, installed: 1 }),
  );
  await Promise.resolve();
  expect(finished).toBe(false);
  hub.close(other);
  hub.message(a, JSON.stringify({ type: "result", id: job.id, installed: 1 }));
  expect(await result).toEqual({ state: "installed", installed: 1, total: 1 });
  hub.close(a);
  expect(hub.targets()).toEqual([]);
  hub.dispose();
});
test("offline/busy targets fail; disconnect and timeout never imply success or replay cookies", async () => {
  const hub = new BrowserSignInHub(() => "secret", { timeout: 20 });
  const a = fake();
  hub.open(a);
  hub.message(
    a,
    JSON.stringify({
      type: "hello",
      token: "secret",
      name: "Playwright",
      kind: "playwright",
    }),
  );
  const targetId = hub.targets()[0]!.id;
  const p = hub.transfer({ ...payload(), targetId });
  await expect(hub.transfer({ ...payload(), targetId })).rejects.toThrow();
  expect((await p).state).toBe("unknown");
  expect(a.closed).toBe(true);
  expect(hub.targets()).toHaveLength(0);
  hub.open(a);
  hub.message(
    a,
    JSON.stringify({
      type: "hello",
      token: "secret",
      name: "Playwright",
      kind: "playwright",
    }),
  );
  const replacement = hub.targets()[0]!.id;
  expect(replacement).not.toBe(targetId);
  const p2 = hub.transfer({ ...payload(), targetId: replacement });
  hub.close(a);
  expect((await p2).state).toBe("unknown");
  await expect(hub.transfer({ ...payload(), targetId })).rejects.toThrow();
  hub.dispose();
});

test("adapter upgrades require loopback and reject website origins", () => {
  expect(
    allowsSignInAdapter(
      new Request("http://127.0.0.1:9983/api/browser-sign-in/adapter"),
    ),
  ).toBe(true);
  expect(
    allowsSignInAdapter(
      new Request("http://127.0.0.1:9983/api/browser-sign-in/adapter", {
        headers: { Origin: "https://evil.example" },
      }),
    ),
  ).toBe(false);
  expect(
    allowsSignInAdapter(
      new Request("https://mac.example/api/browser-sign-in/adapter"),
    ),
  ).toBe(false);
  expect(
    allowsSignInAdapter(
      new Request("http://127.0.0.1:9983/api/browser-sign-in/adapter", {
        headers: { "cf-connecting-ip": "1.2.3.4" },
      }),
    ),
  ).toBe(false);
});
test("HTTPS reverse proxy works; malformed data never echoes secrets", async () => {
  const hub = new BrowserSignInHub(() => "secret");
  const response = await signInHTTP(
    new Request("http://mac.example/api/browser-sign-in/targets", {
      headers: { "x-forwarded-proto": "https", "cf-connecting-ip": "1.2.3.4" },
    }),
    hub,
  );
  expect(response.status).toBe(200);
  expect(response.headers.get("cache-control")).toBe("no-store");
  const untrusted = await signInHTTP(
    new Request("http://mac.example/api/browser-sign-in/targets"),
    hub,
  );
  expect(untrusted.status).toBe(403);
  const invalid = await signInHTTP(
    new Request("http://127.0.0.1:9983/api/browser-sign-in/transfer", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: '{"secret":"sensitive-value"}',
    }),
    hub,
  );
  expect(invalid.status).toBe(400);
  expect(await invalid.text()).not.toContain("sensitive-value");
  hub.dispose();
});
test("partial import is distinct from confirmed delivery", async () => {
  const hub = new BrowserSignInHub(() => "secret"),
    a = fake();
  hub.open(a);
  hub.message(
    a,
    JSON.stringify({
      type: "hello",
      token: "secret",
      name: "Chrome",
      kind: "chrome",
    }),
  );
  const result = hub.transfer({
    ...payload(),
    targetId: hub.targets()[0]!.id,
    cookies: [cookie, { ...cookie, name: "second" }],
  });
  hub.message(
    a,
    JSON.stringify({ type: "result", id: a.sent.at(-1).id, installed: 1 }),
  );
  expect(await result).toEqual({ state: "partial", installed: 1, total: 2 });
  hub.dispose();
});
