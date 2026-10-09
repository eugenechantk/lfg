import { test, expect } from "bun:test";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { iphonePreviewRoutes } from "./iphone-preview.ts";

async function fixture() {
  const root = await mkdtemp(join(tmpdir(), "lfg-phone-preview-"));
  const key = createHash("sha256").update("phone-udid").digest("hex").slice(0, 24);
  await mkdir(join(root, "devices", "hihi"), { recursive: true });
  await mkdir(join(root, "by-device", key), { recursive: true });
  await writeFile(join(root, "devices", "hihi", "config.json"), JSON.stringify({ udid: "phone-udid" }));
  await writeFile(join(root, "config.json"), JSON.stringify({ udid: "phone-udid" }));
  let paused = true;
  let frame: Buffer = Buffer.from([0xff, 0xd8, 1, 2, 0xff, 0xd9]);
  let mode = "jpeg";
  let starts = 0;
  const actions: string[] = [];
  const worker = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch(req) {
    const url = new URL(req.url);
    expect(url.searchParams.get("token")).toBe("private-worker-secret");
    actions.push(url.pathname);
    if (url.pathname === "/status") return Response.json({ paused });
    if (url.pathname === "/pause") paused = true;
    if (url.pathname === "/resume") paused = false;
    if (url.pathname === "/frame") {
      if (mode === "empty") return new Response(null, { status: 204 });
      if (mode === "redirect") return Response.redirect("https://example.com");
      return new Response(frame, { headers: { "Content-Type": mode === "jpeg" ? "image/jpeg" : "text/html" } });
    }
    return Response.json({});
  } });
  const state = join(root, "by-device", key, "preview.json");
  await writeFile(state, JSON.stringify({ base: worker.url.origin, token: "private-worker-secret" }));
  const routes = iphonePreviewRoutes({ root, access: null, start: async () => { starts++; } });
  const host = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: routes });
  const request = (path = "devices", init?: RequestInit) => fetch(new URL(`/api/iphone-preview/${path}`, host.url), init);
  const toggle = (enabled: boolean) => request("hihi/enabled", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ enabled }) });
  return { root, state, request, toggle, actions, starts: () => starts,
    mode: (v: string) => { mode = v; }, frame: (v: Buffer) => { frame = v; },
    cleanup: async () => { host.stop(true); worker.stop(true); await rm(root, { recursive: true, force: true }); } };
}

test("real HTTP lists profiles once, never starts capture or exposes private details", async () => {
  const f = await fixture();
  try {
    const response = await f.request();
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({ devices: [{ id: "hihi", name: "hihi" }] });
    expect(f.starts()).toBe(0);
    expect(f.actions).toEqual([]);
  } finally { await f.cleanup(); }
});

test("on/frame/off uses private worker auth, and paused preview cannot return a cached frame", async () => {
  const f = await fixture();
  try {
    expect((await f.request("hihi/frame")).status).toBe(409);
    expect((await f.toggle(true)).status).toBe(200);
    const frame = await f.request("hihi/frame");
    expect(frame.headers.get("content-type")).toBe("image/jpeg");
    expect(await frame.bytes()).toEqual(new Uint8Array([0xff, 0xd8, 1, 2, 0xff, 0xd9]));
    expect((await f.toggle(false)).status).toBe(200);
    expect((await f.request("hihi/frame")).status).toBe(409);
    expect(f.starts()).toBe(1);
  } finally { await f.cleanup(); }
});

test("forged remote authentication, cross-origin POST, and invalid profiles are rejected", async () => {
  const f = await fixture();
  try {
    for (const path of ["devices", "hihi/frame", "hihi/enabled"]) {
      expect((await f.request(path, { headers: { "cf-connecting-ip": "8.8.8.8", "cf-access-jwt-assertion": "forged" } })).status).toBe(403);
    }
    expect((await f.request("hihi/enabled", { method: "POST", headers: { Origin: "https://evil.example" } })).status).toBe(403);
    expect((await f.request("hihi/enabled", { method: "POST", body: "{}" })).status).toBe(415);
    for (const body of ["null", "false", "[]", "{}", '{"enabled":"false"}', "{"]) {
      expect((await f.request("hihi/enabled", { method: "POST", headers: { "Content-Type": "application/json" }, body })).status).toBe(400);
    }
    expect((await f.request("%2Fetc%2Fpasswd/frame")).status).toBe(404);
    expect((await f.request("unknown/frame")).status).toBe(404);
    expect(f.starts()).toBe(0);
  } finally { await f.cleanup(); }
});

test("missing frames, redirects, non-JPEG and oversized responses never leak into preview", async () => {
  const f = await fixture();
  try {
    await f.toggle(true);
    f.mode("empty"); expect((await f.request("hihi/frame")).status).toBe(204);
    for (const mode of ["redirect", "html"]) {
      f.mode(mode); expect((await f.request("hihi/frame")).status).toBe(503);
    }
    f.mode("jpeg"); f.frame(Buffer.alloc(8 * 1024 * 1024 + 1));
    expect((await f.request("hihi/frame")).status).toBe(503);
  } finally { await f.cleanup(); }
});

test("corrupt worker state cannot proxy other hosts or the LFG listener", async () => {
  const f = await fixture();
  try {
    for (const base of ["https://evil.example", "http://127.0.0.1:8766", "http://localhost:8160", "http://127.0.0.1:8160/secret"]) {
      await writeFile(f.state, JSON.stringify({ base, token: "must-not-leak" }));
      const r = await f.request("hihi/frame");
      expect(r.status).toBe(503);
      expect(await r.text()).not.toContain("must-not-leak");
    }
  } finally { await f.cleanup(); }
});

test("a stop arriving during startup is applied last, including after a failed start", async () => {
  const f = await fixture();
  try {
    for (const fails of [false, true]) {
      let started!: () => void;
      let release!: () => void;
      const entered = new Promise<void>(resolve => { started = resolve; });
      const gate = new Promise<void>(resolve => { release = resolve; });
      const routes = iphonePreviewRoutes({ root: f.root, access: null, start: async () => {
        started(); await gate; if (fails) throw Error("failed start");
      } });
      const request = (enabled: boolean) => routes(new Request("http://127.0.0.1/api/iphone-preview/hihi/enabled", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ enabled }),
      }));
      const on = request(true);
      await entered;
      const off = request(false);
      release();
      expect((await on).status).toBe(fails ? 503 : 200);
      expect((await off).status).toBe(200);
      expect(f.actions.at(-1)).toBe("/pause");
      expect((await f.request("hihi/frame")).status).toBe(409);
    }
  } finally { await f.cleanup(); }
});
