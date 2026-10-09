import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskStore, TaskScheduler, nextOccurrence, validateTask, type TaskInput } from "./scheduled-tasks.ts";

const now = Date.parse("2026-10-09T00:00:00Z");
const input = (schedule: TaskInput["schedule"]): TaskInput => ({ name: "Daily review", prompt: "Review the repository", cwd: tmpdir(), agent: "claude", schedule });
const interval = input({ kind: "interval", everyMinutes: 5, timezone: "Asia/Hong_Kong" });
const dirs: string[] = [];
async function store() { const dir = await mkdtemp(join(tmpdir(), "lfg-tasks-test-")); dirs.push(dir); return new TaskStore(join(dir, "tasks.json")); }
afterEach(async () => { await Promise.all(dirs.splice(0).map(d => rm(d, { recursive: true, force: true }))); });

describe("schedule semantics", () => {
  test("one-time dates require an explicit offset and a future instant", () => {
    expect(() => validateTask(input({ kind: "once", at: "2026-10-10T09:00:00", timezone: "Asia/Hong_Kong" }), now)).toThrow();
    expect(() => validateTask(input({ kind: "once", at: new Date(now - 1).toISOString(), timezone: "UTC" }), now)).toThrow();
    expect(nextOccurrence({ kind: "once", at: "2026-10-10T09:00:00+08:00", timezone: "Asia/Hong_Kong" }, now)).toBe(Date.parse("2026-10-10T01:00Z"));
  });
  test("cron uses the chosen timezone and standard day-of-month OR weekday semantics", () => {
    expect(nextOccurrence({ kind: "cron", expression: "0 9 * * *", timezone: "Asia/Hong_Kong" }, now)).toBe(now + 3600_000);
    expect(nextOccurrence({ kind: "cron", expression: "0 9 1 * MON", timezone: "UTC" }, now)).toBe(Date.parse("2026-10-12T09:00Z"));
  });
  test("reject malformed cron, seconds, invalid timezones and sub-minute intervals", () => {
    for (const expression of ["61 * * * *", "* * * * * *", "*/0 * * * *", "nonsense"]) {
      expect(() => validateTask(input({ kind: "cron", expression, timezone: "UTC" }), now)).toThrow();
    }
    expect(() => validateTask(input({ kind: "interval", everyMinutes: 0, timezone: "UTC" }), now)).toThrow();
    expect(() => validateTask(input({ kind: "interval", everyMinutes: 1, timezone: "wrong/zone" }), now)).toThrow();
  });
});

describe("durable task lifecycle", () => {
  test("atomic claims prevent concurrent duplicates and persist across restart", async () => {
    const s = await store(); const task = await s.save(interval, now);
    const claims = await Promise.all([s.claim(task.id, now + 300_000), s.claim(task.id, now + 300_000)]);
    expect(claims.filter(Boolean)).toHaveLength(1);
    const reload = new TaskStore(s.path);
    expect((await reload.read()).runs).toHaveLength(1);
    expect(await reload.claim(task.id, now + 600_000)).toBeNull();
  });
  test("missed recurring runs coalesce; one-time tasks disable after their claim", async () => {
    const s = await store(); const a = await s.save(interval, now);
    await s.claim(a.id, now + 86400_000);
    expect((await s.read()).tasks[0]!.nextRunAt).toBeGreaterThan(now + 86400_000);
    const b = await s.save(input({ kind: "once", at: new Date(now + 60_000).toISOString(), timezone: "UTC" }), now);
    expect(await s.claim(b.id, now + 86400_000)).not.toBeNull();
    expect((await s.read()).tasks.find(t => t.id === b.id)!.enabled).toBe(false);
    expect(await s.claim(b.id, now + 86460_000)).toBeNull();
  });
  test("paused tasks do not fire and editing replaces their next due time", async () => {
    const s = await store(); const a = await s.save(interval, now);
    await s.update(a.id, { enabled: false }, now + 100);
    expect(await s.claim(a.id, now + 600_000)).toBeNull();
    await s.update(a.id, { schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" }, enabled: true }, now + 600_000);
    expect((await s.read()).tasks[0]!.nextRunAt).toBe(now + 4200_000);
  });
  test("run now does not shift recurring cadence; cancellation retains history", async () => {
    const s = await store(); const a = await s.save(interval, now);
    const r = await s.claim(a.id, now + 100, true);
    expect(r!.trigger).toBe("manual");
    expect((await s.read()).tasks[0]!.nextRunAt).toBe(now + 300_000);
    await s.cancel(a.id, now + 200);
    expect((await s.read()).runs).toHaveLength(1);
    expect(await s.claim(a.id, now + 300_000, true)).toBeNull();
  });
  test("editing can preserve or clear an explicit model", async () => {
    const s = await store(); const task = await s.save({ ...interval, model: "opus" }, now);
    expect((await s.update(task.id, { name: "Renamed" }, now + 1)).model).toBe("opus");
    expect((await s.update(task.id, { model: null }, now + 2)).model).toBeUndefined();
    expect((await new TaskStore(s.path).read()).tasks[0]!.model).toBeUndefined();
  });
  test("native editor serialization does not change a schedule's meaning", async () => {
    const s = await store(); const task = await s.save(interval, now);
    const edited = await s.update(task.id, { name: "Renamed", schedule: { timezone: "Asia/Hong_Kong", everyMinutes: 5, kind: "interval" } }, now + 30_000);
    expect(edited.nextRunAt).toBe(task.nextRunAt);
    const once = await s.save(input({ kind: "once", at: new Date(now + 60_000).toISOString(), timezone: "UTC" }), now);
    await s.claim(once.id, now + 60_000);
    const completed = await s.update(once.id, { name: "Reviewed", schedule: { timezone: "UTC", kind: "once", at: new Date(now + 60_000).toISOString().replace(".000Z", "Z") } }, now + 120_000);
    expect(completed.enabled).toBe(false);
    expect(completed.nextRunAt).toBeNull();
  });
  test("scheduler records launch failure and does not mark an early idle session successful", async () => {
    const s = await store(); const a = await s.save(interval, now); let time = now + 300_000;
    let snapshot: any = { state: "working" };
    const runtime = new TaskScheduler(s, { launch: async () => ({ sessionId: "test-session" }), inspect: async () => snapshot }, () => time);
    await runtime.tick();
    expect((await s.read()).runs[0]!.status).toBe("running");
    snapshot = { state: "idle" }; time += 30_000; await runtime.tick();
    expect((await s.read()).runs[0]!.status).toBe("running");
    snapshot = { state: "idle", summary: "Review complete." }; time += 10_000; await runtime.tick(); time += 10_000; await runtime.tick();
    expect((await s.read()).runs[0]!.status).toBe("succeeded");
    const broken = new TaskScheduler(s, { launch: async () => { throw Error("agent unavailable"); }, inspect: async () => ({ state: "working" }) }, () => now + 600_000);
    await broken.tick();
    expect((await s.read()).runs.at(-1)!.error).toBe("agent unavailable");
  });
  test("uncertain launch after restart is interrupted rather than duplicated", async () => {
    const s = await store(); const a = await s.save(interval, now); await s.claim(a.id, now + 300_000);
    let launches = 0;
    const runtime = new TaskScheduler(s, { launch: async () => { launches++; return { sessionId: "new" }; }, inspect: async () => ({ state: "working" }) }, () => now + 310_000);
    await runtime.recover(); await runtime.tick();
    expect(launches).toBe(0); expect((await s.read()).runs[0]!.status).toBe("interrupted");
  });
  test("a transient inspection failure cannot block another due task", async () => {
    const s = await store(); const first = await s.save(interval, now);
    const running = await s.claim(first.id, now + 300_000);
    await s.record(running!.id, { sessionId: "unavailable", status: "running" });
    const second = await s.save(interval, now); let launches = 0;
    const runtime = new TaskScheduler(s, {
      launch: async () => { launches++; return { sessionId: "healthy" }; },
      inspect: async () => { throw Error("transient API failure"); },
    }, () => now + 300_000);
    await runtime.tick();
    expect(launches).toBe(1);
    expect((await s.read()).runs.find(r => r.taskId === second.id)?.status).toBe("running");
    expect((await s.read()).runs.find(r => r.taskId === first.id)?.status).toBe("running");
  });
});
