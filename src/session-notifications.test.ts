import { afterAll, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionNotifications, sessionNotificationRoutes } from "./session-notifications";
import { buildPayload, runPushTick, type PriorState, type TickDeps } from "./push/watcher";
import { apnsBody } from "./push/apns";

const root = mkdtempSync(join(tmpdir(), "lfg-notifications-"));
afterAll(() => rmSync(root, { recursive: true, force: true }));
const sid = "aaaaaaaa-1111-4111-8111-111111111111";
function fixture() {
  const sent: any[] = [], events: any[] = [];
  const file = join(root, crypto.randomUUID() + ".json");
  const options = {
    sessions: async () => [{ sessionId: sid, title: "Fix notifications", lastUserAt: 100 }],
    emit: (id: string, note: any) => { events.push({ id, note }); },
    devices: async () => [{ token: "phone", env: "production" as const }, { token: "ipad", env: "sandbox" as const }],
    send: async (device: any, payload: any) => { sent.push({ device, payload }); return { ok: device.token !== "ipad", status: device.token === "ipad" ? 503 : 200 }; },
    now: () => 200,
  };
  return { file, options, sent, events, service: new SessionNotifications(file, options) };
}

test("fans custom result out independently and records acceptance without claiming delivery", async () => {
  const f = fixture();
  const r = await f.service.send(sid, { requestID: "result-1", status: "completed", message: "Fixed alerts. All 12 tests pass." });
  expect(f.events).toHaveLength(1);
  expect(f.sent.map(s => s.device.token)).toEqual(["phone", "ipad"]);
  expect(f.sent[0].payload).toMatchObject({ sid, kind: "finished", title: "✅ Fix notifications", body: "Completed: Fixed alerts. All 12 tests pass." });
  expect(r.notification).toMatchObject({ status: "completed", title: "Fix notifications", message: "Fixed alerts. All 12 tests pass.", turnStartedAt: 100 });
  expect(r.mobile).toEqual({ state: "partial", attempted: 2, accepted: 1, failed: 1 });
  expect(f.service.latest(sid)?.id).toBe(r.notification.id);
  expect(f.service.completedTurn(sid, { lastUserAt: 100 })).toBe(true);
  expect(f.service.completedTurn(sid, { lastUserAt: 150 })).toBe(true);
  expect(f.service.completedTurn(sid, { lastUserAt: 300 })).toBe(false);
  await f.service.send(sid, { requestID: "later", status: "reminder", message: "Review the result." });
  expect(f.service.completedTurn(sid, { lastUserAt: 100 })).toBe(true);
  expect((await new SessionNotifications(f.file, f.options).ready).completedTurn(sid, { lastUserAt: 100 })).toBe(true);
});

test("maximum Unicode copy remains within the APNs alert payload limit", async () => {
  const f = fixture();
  await f.service.send(sid, { requestID: "unicode", status: "working", title: "🧪".repeat(80), message: "🧪".repeat(500) });
  expect(Buffer.byteLength(apnsBody(f.sent[0].payload))).toBeLessThan(4096);
  expect(JSON.parse(apnsBody(f.sent[0].payload)).aps.alert.body).toBe("Working: " + "🧪".repeat(500));
});

test("long source titles cannot overflow alerts and malformed Unicode never reaches a client", async () => {
  const f = fixture();
  f.options.sessions = async () => [{ sessionId: sid, title: "🧪".repeat(7000), lastUserAt: 100 }];
  const service = new SessionNotifications(f.file, f.options);
  await service.send(sid, { requestID: "long-title", status: "working", title: "🧪".repeat(80), message: "🧪".repeat(500) });
  expect(Buffer.byteLength(apnsBody({ ...f.sent[0].payload, hostId: "host-".repeat(20), seq: Number.MAX_SAFE_INTEGER }))).toBeLessThan(4096);
  expect([...f.sent[0].payload.session.title]).toHaveLength(80);
  for (const patch of [{ title: "\ud800".repeat(80) }, { message: "\ud800".repeat(500) }, { message: "\u0000".repeat(500) }]) {
    await expect(service.send(sid, { requestID: crypto.randomUUID(), status: "working", message: "Testing", ...patch })).rejects.toThrow("display text");
  }
  expect(f.sent).toHaveLength(2); expect(f.events).toHaveLength(1);
});

test("concurrent and restarted retries do not emit or resend; conflicting reuse fails", async () => {
  const f = fixture(), input = { requestID: "same", status: "reminder", message: "Review the build." };
  const results = await Promise.all([f.service.send(sid, input), f.service.send(sid, input)]);
  expect(results.map(r => r.duplicate)).toEqual([false, true]);
  const restarted = new SessionNotifications(f.file, f.options);
  expect((await restarted.send(sid, input)).duplicate).toBe(true);
  expect(f.events).toHaveLength(1); expect(f.sent).toHaveLength(2);
  await expect(restarted.send(sid, { ...input, message: "Different" })).rejects.toThrow("requestID");
});

test("one thrown transport cannot prevent other devices receiving text", async () => {
  const f = fixture();
  f.options.send = async (d: any, payload: any) => { f.sent.push({ device: d, payload }); if (d.token === "phone") throw Error("offline"); return { ok: true, status: 200 }; };
  const service = new SessionNotifications(f.file, f.options);
  expect((await service.send(sid, { requestID: "one", status: "blocked", message: "Build needs signing access." })).mobile.state).toBe("partial");
  expect(f.sent).toHaveLength(2);
});

test("rejects invalid data and unknown sessions before emitting", async () => {
  const f = fixture();
  for (const patch of [{ message: "  " }, { message: "x".repeat(501) }, { status: "done" }, { requestID: "" }, { title: "x".repeat(81) }]) {
    await expect(f.service.send(sid, { requestID: "bad", status: "working", message: "Testing", ...patch })).rejects.toThrow();
  }
  await expect(f.service.send("unknown", { requestID: "bad", status: "working", message: "Testing" })).rejects.toThrow("Session");
  expect(f.events).toHaveLength(0); expect(f.sent).toHaveLength(0);
});

test("HTTP enforces the contract and leaves unrelated routes untouched", async () => {
  const f = fixture(), route = sessionNotificationRoutes(f.service);
  const req = (body: unknown, origin?: string) => new Request(`http://test/api/sessions/${sid}/notify`, { method: "POST", headers: { "content-type": "application/json", ...(origin ? { origin } : {}) }, body: JSON.stringify(body) });
  expect((await route(req({ requestID: "http", status: "needs-input", message: "Approve the screenshots." })))?.status).toBe(200);
  expect((await route(req({}, "http://evil")))?.status).toBe(403);
  expect((await route(req(null)))?.status).toBe(400);
  expect((await route(new Request(`http://test/api/sessions/${sid}/notify`)))?.status).toBe(405);
  expect(await route(new Request("http://test/api/sessions"))).toBeUndefined();
});

test("automatic completion uses only the current assistant result", () => {
  const session = { sessionId: sid, title: "Fix alerts", lastUserAt: 100, last: { role: "assistant", kind: "text", text: "**Fixed** the alerts.", ts: 200 } };
  expect(buildPayload(session, "finished").body).toBe("Finished: Fixed the alerts.");
  expect(buildPayload({ ...session, last: { ...session.last, text: "Fixed `build_guard.py` and C# support." } }, "finished").body).toBe("Finished: Fixed build_guard.py and C# support.");
  expect(buildPayload({ ...session, lastUserAt: 300 }, "finished").body).toBe("The agent finished its turn.");
  expect(buildPayload({ ...session, last: { ...session.last, kind: "thinking" } }, "finished").body).toBe("The agent finished its turn.");
});

test("custom completion suppresses terminal generic stop but real questions still notify", async () => {
  const sent: any[] = [];
  let prompt = false;
  const prior = new Map<string, PriorState>([[sid, { busy: true, promptPresent: false, lastNotifiedAt: -Infinity }]]);
  const deps: TickDeps = {
    sessions: async () => [{ sessionId: sid, completionNotification: { id: "result", createdAt: 100 } }],
    observe: async () => ({ busy: false, promptPresent: prompt, promptQuestion: "Approve the build?" }),
    devices: async () => [{ token: "phone", env: "production" }], cfg: { key: "", keyId: "", teamId: "", topic: "" },
    send: async (_d, p) => { sent.push(p); return { ok: true, status: 200 }; },
  };
  await runPushTick(prior, deps); expect(sent).toHaveLength(0);
  prompt = true; await runPushTick(prior, deps);
  expect(sent.map(p => p.kind)).toEqual(["needs-input"]);
});

test("markerless completion suppresses once; the same receipt never rearms a later busy interval", async () => {
  const f = fixture();
  f.options.sessions = async () => [{ sessionId: sid, title: "Legacy session", lastUserAt: null as any }];
  const service = new SessionNotifications(f.file, f.options);
  await service.send(sid, { requestID: "markerless", status: "completed", message: "Verified the result." });
  expect(service.completedTurn(sid, { lastUserAt: null })).toBe(true);
  const sent: any[] = []; let busy = true;
  const prior = new Map<string, PriorState>([[sid, { busy: true, promptPresent: false, lastNotifiedAt: -Infinity }]]);
  const deps: TickDeps = {
    sessions: async () => [{ sessionId: sid }], completionNotification: id => service.latestCompletion(id),
    observe: async () => ({ busy, promptPresent: false }), devices: f.options.devices,
    cfg: { key: "", keyId: "", teamId: "", topic: "" }, send: async (_d, p) => { sent.push(p); return { ok: true, status: 200 }; },
  };
  await runPushTick(prior, deps);
  await service.send(sid, { requestID: "after-result", status: "reminder", message: "Review the result." });
  busy = false; await runPushTick(prior, deps); expect(sent).toHaveLength(0);
  busy = true; await runPushTick(prior, deps);
  busy = false; await runPushTick(prior, deps); expect(sent.map(p => p.kind)).toEqual(["finished", "finished"]);
});

test("CLI posts the shared contract to the real HTTP route and retries safely", async () => {
  const f = fixture(), route = sessionNotificationRoutes(f.service);
  // Ask the OS for an unused test port; never use LFG's reserved port.
  const server = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: async req => await route(req) ?? new Response("not found", { status: 404 }) });
  try {
    const args = [process.execPath, "src/cli.ts", "notify", "--session", sid, "--status", "reminder", "--message", "Review the test results.", "--request-id", "cli-result"];
    for (const duplicate of [false, true]) {
      const child = Bun.spawn(args, { cwd: process.cwd(), env: { ...process.env, LFG_NOTIFY_URL: server.url.href }, stdout: "pipe", stderr: "pipe" });
      const output = await new Response(child.stdout).text();
      expect(await child.exited).toBe(0);
      expect(JSON.parse(output).duplicate).toBe(duplicate);
    }
    expect(f.events).toHaveLength(1); expect(f.sent).toHaveLength(2);
  } finally { server.stop(true); }
});
