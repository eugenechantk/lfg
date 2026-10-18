import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskScheduler, TaskStore, type TaskInput } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes } from "./scheduled-task-api.ts";

const now = Date.parse("2026-10-18T01:00:00Z");
const dirs: string[] = [];
async function setup(schedule: TaskInput["schedule"] = { kind: "interval", everyMinutes: 1440, timezone: "UTC" }) {
  const dir = await mkdtemp(join(tmpdir(), "lfg-retry-")); dirs.push(dir);
  const store = new TaskStore(join(dir, "tasks.json"));
  const task = await store.save({ name: "Retry test", prompt: "Review", cwd: dir, agent: "codex", schedule }, now);
  return { store, task };
}
afterEach(async () => { await Promise.all(dirs.splice(0).map(d => rm(d, { recursive: true, force: true }))); });

test("retry persists, never launches early, and launches once after restart", async () => {
  const { store, task } = await setup(); const at = now + 35 * 60_000;
  await store.scheduleRetry(task.id, new Date(at).toISOString(), now);
  const reloaded = new TaskStore(store.path); let time = at - 1; let launches = 0;
  const runtime = new TaskScheduler(reloaded, { launch: async () => ({ sessionId: `retry-${++launches}` }), inspect: async () => ({ state: "working" }) }, () => time);
  await runtime.recover(); await runtime.tick(); expect(launches).toBe(0);
  time = at + 60_000; await Promise.all([runtime.tick(), runtime.tick()]); await runtime.tick();
  const state = await reloaded.read();
  expect(launches).toBe(1); expect(state.runs).toHaveLength(1);
  expect(state.runs[0]).toMatchObject({ trigger: "manual", scheduledFor: at });
  expect(state.tasks[0]!.retryAt).toBeUndefined();
  expect(state.tasks[0]!.nextRunAt).toBe(task.nextRunAt);
});

test("retrying finished once and finite-repeat tasks preserves their schedule and budget", async () => {
  for (const schedule of [
    { kind: "once", at: new Date(now + 60_000).toISOString(), timezone: "UTC" },
    { kind: "repeat", at: new Date(now + 60_000).toISOString(), everyMinutes: 60, occurrences: 1, timezone: "UTC" },
  ] as TaskInput["schedule"][]) {
    const { store, task } = await setup(schedule);
    const first = await store.claim(task.id, now + 60_000);
    await store.record(first!.id, { status: "failed" });
    const before = (await store.read()).tasks[0]!;
    await store.scheduleRetry(task.id, new Date(now + 120_000).toISOString(), now + 60_000);
    const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "retried" }), inspect: async () => ({ state: "working" }) }, () => now + 120_000);
    await runtime.tick(); const after = (await store.read()).tasks[0]!;
    expect((await store.read()).runs).toHaveLength(2);
    expect(after.enabled).toBe(false); expect(after.schedule).toEqual(before.schedule);
    expect(after.nextRunAt).toBe(before.nextRunAt); expect(after.scheduledRunCount).toBe(before.scheduledRunCount);
  }
});

test("paused tasks retry without resuming, replacing and cancelling are durable", async () => {
  const { store, task } = await setup(); await store.update(task.id, { enabled: false }, now);
  await store.scheduleRetry(task.id, new Date(now + 45 * 60_000).toISOString(), now);
  await store.scheduleRetry(task.id, new Date(now + 60 * 60_000).toISOString(), now);
  expect((await store.read()).tasks[0]!.retryAt).toBe(now + 60 * 60_000);
  await store.scheduleRetry(task.id, null, now);
  expect((await new TaskStore(store.path).read()).tasks[0]!.retryAt).toBeUndefined();
  await store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now);
  const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "paused-retry" }), inspect: async () => ({ state: "working" }) }, () => now + 60_000);
  await runtime.tick(); expect((await store.read()).runs).toHaveLength(1);
  expect((await store.read()).tasks[0]!.enabled).toBe(false);
});

test("reject invalid, past, active, missing, and cancelled retry requests", async () => {
  const { store, task } = await setup();
  for (const at of [undefined, 123, "tomorrow", "2026-10-19T10:00:00", new Date(now).toISOString(), new Date(now - 1).toISOString()]) {
    await expect(store.scheduleRetry(task.id, at as any, now)).rejects.toThrow();
  }
  await expect(store.scheduleRetry("missing", new Date(now + 60_000).toISOString(), now)).rejects.toThrow();
  const run = await store.claim(task.id, now, true);
  await expect(store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now)).rejects.toThrow("already running");
  await store.record(run!.id, { status: "failed" }); await store.cancel(task.id, now);
  await expect(store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now)).rejects.toThrow("cancelled");
});

test("run now and stop future runs clear pending retries", async () => {
  const { store, task } = await setup();
  await store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now);
  const run = await store.claim(task.id, now, true);
  expect((await store.read()).tasks[0]!.retryAt).toBeUndefined();
  await store.record(run!.id, { status: "failed" });
  await store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now);
  await store.cancel(task.id, now); expect((await store.read()).tasks[0]!.retryAt).toBeUndefined();
});

test("due retries wait for a live run and concurrent claims cannot duplicate them", async () => {
  const { store, task } = await setup(); const at = now + 120_000;
  await store.scheduleRetry(task.id, new Date(at).toISOString(), now);
  // A regular occurrence can start while an extra retry is pending.
  const running = await store.claim(task.id, now + 86400_000);
  expect(await store.claim(task.id, now + 86400_000, "retry")).toBeNull();
  expect((await store.read()).tasks[0]!.retryAt).toBe(at);
  await store.record(running!.id, { status: "succeeded" });
  const claims = await Promise.all([store.claim(task.id, now + 86400_000, "retry"), store.claim(task.id, now + 86400_000, "retry")]);
  expect(claims.filter(Boolean)).toHaveLength(1);
  expect(claims.find(Boolean)!.scheduledFor).toBe(at);
});

test("an extra retry does not consume an unrun one-time task", async () => {
  const { store, task } = await setup({ kind: "once", at: new Date(now + 3600_000).toISOString(), timezone: "UTC" });
  await store.scheduleRetry(task.id, new Date(now + 60_000).toISOString(), now);
  const retry = await store.claim(task.id, now + 60_000, "retry");
  expect(retry).not.toBeNull();
  expect((await store.read()).tasks[0]).toMatchObject({ enabled: true, nextRunAt: task.nextRunAt });
  await store.record(retry!.id, { status: "succeeded" });
  expect(await store.claim(task.id, now + 3600_000)).not.toBeNull();
});

test("API schedules and clears retries, lists saved time, and rejects invalid requests", async () => {
  const { store, task } = await setup();
  const runtime = new TaskScheduler(store, { launch: async () => { throw Error("must not run during configuration"); }, inspect: async () => ({ state: "working" }) });
  const route = scheduledTaskRoutes(store, runtime, async () => ({} as any), { root: tmpdir(), port: 18953, defaultCwd: tmpdir() });
  const request = (body: unknown) => route(new Request(`http://test/api/scheduled-tasks/${task.id}/retry`, { method: "POST", body: JSON.stringify(body) }));
  const at = new Date(Date.now() + 3600_000).toISOString();
  const saved = await request({ at }); expect(saved!.status).toBe(200);
  expect((await saved!.json() as any).task.retryAt).toBe(Date.parse(at));
  const listed = await route(new Request("http://test/api/scheduled-tasks"));
  expect((await listed!.json() as any).tasks[0].retryAt).toBe(Date.parse(at));
  expect((await request({}))!.status).toBe(400); expect((await request({ at: "bad" }))!.status).toBe(400);
  expect((await request({ at: null }))!.status).toBe(200);
  expect((await store.read()).tasks[0]!.retryAt).toBeUndefined(); expect((await store.read()).runs).toHaveLength(0);
});
