import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskStore, TaskScheduler, nextOccurrence, validateTask, type TaskInput } from "./scheduled-tasks.ts";

const now = Date.parse("2026-10-14T15:00:00Z"), day = 86400_000, start = now + 3600_000;
const input = (overrides = {}): TaskInput => ({ name: "Three daily sessions", prompt: "Do the work once", cwd: tmpdir(), agent: "codex",
  schedule: { kind: "repeat", at: new Date(start).toISOString(), everyMinutes: 1440, occurrences: 3, timezone: "Asia/Hong_Kong", ...overrides } });
const dirs: string[] = [];
async function store() { const dir = await mkdtemp(join(tmpdir(), "lfg-repeat-test-")); dirs.push(dir); return new TaskStore(join(dir, "tasks.json")); }
afterEach(async () => { await Promise.all(dirs.splice(0).map(d => rm(d, { recursive: true, force: true }))); });

test("finite repeat validates the count, interval, offset and future start", () => {
  expect(validateTask(input(), now).schedule.occurrences).toBe(3);
  for (const occurrences of [undefined, 0, -1, 1.5, 1001, "3"]) expect(() => validateTask(input({ occurrences }), now)).toThrow();
  for (const everyMinutes of [undefined, 0, 1.5, 525601]) expect(() => validateTask(input({ everyMinutes }), now)).toThrow();
  for (const at of [undefined, "bad", "2026-10-15T09:00:00", new Date(now).toISOString()]) expect(() => validateTask(input({ at }), now)).toThrow();
});

test("three anchored daily occurrences include the first and stop at the end", () => {
  const s = input().schedule;
  expect(nextOccurrence(s, now)).toBe(start);
  expect(nextOccurrence(s, start)).toBe(start + day);
  expect(nextOccurrence(s, start + day + 60_000)).toBe(start + 2 * day);
  expect(nextOccurrence(s, start + 2 * day)).toBeNull();
  expect(nextOccurrence(input({ occurrences: 1 }).schedule, start)).toBeNull();
});

test("the host advances despite failed agents and persists the finite end", async () => {
  const s = await store(); const task = await s.save(input(), now);
  let time = start, launches = 0;
  const runtime = new TaskScheduler(s, { launch: async () => { launches++; throw Error("agent unavailable"); }, inspect: async () => ({ state: "working" }) }, () => time);
  for (let i = 0; i < 3; i++) {
    time = start + i * day; await runtime.tick();
    const t = (await new TaskStore(s.path).read()).tasks[0]!;
    expect(t.nextRunAt).toBe(i === 2 ? null : start + (i + 1) * day);
    expect(t.enabled).toBe(i !== 2);
  }
  time += day; await runtime.tick();
  expect(launches).toBe(3);
  expect((await s.read()).runs.map(r => r.scheduledFor)).toEqual([start, start + day, start + 2 * day]);
  expect(await s.claim(task.id, time)).toBeNull();
});

test("late claims coalesce without extending the original end", async () => {
  const s = await store(); const t = await s.save(input(), now);
  const r = await s.claim(t.id, start + day + 60_000);
  expect(r?.scheduledFor).toBe(start);
  expect((await s.read()).tasks[0]!.nextRunAt).toBe(start + 2 * day);
  await s.record(r!.id, { status: "failed" });
  await s.claim(t.id, start + 4 * day);
  expect((await s.read()).tasks[0]!.enabled).toBe(false);
  expect((await s.read()).runs).toHaveLength(2);
});

test("manual runs do not consume finite occurrences; paused resumes keep the anchor", async () => {
  const s = await store(); const t = await s.save(input(), now);
  const manual = await s.claim(t.id, now + 100, true);
  expect((await s.read()).tasks[0]!.nextRunAt).toBe(start);
  await s.record(manual!.id, { status: "succeeded" });
  await s.update(t.id, { enabled: false }, now + 200);
  expect(await s.claim(t.id, start)).toBeNull();
  const resumed = await s.update(t.id, { enabled: true }, start + 100);
  expect(resumed.nextRunAt).toBe(start + day);
  await s.update(t.id, { enabled: false }, start + day);
  await expect(s.update(t.id, { enabled: true }, start + 3 * day)).rejects.toThrow();
});

test("metadata round trips do not reset an active or completed repeat", async () => {
  const s = await store(); const t = await s.save(input(), now);
  const run = await s.claim(t.id, start);
  const renamed = await s.update(t.id, { name: "Renamed", schedule: { ...t.schedule, at: t.schedule.at!.replace(".000Z", "Z") } }, start + 100);
  expect(renamed.nextRunAt).toBe(start + day);
  await s.record(run!.id, { status: "succeeded" });
  const last = await s.claim(t.id, start + 2 * day);
  await s.record(last!.id, { status: "succeeded" });
  const completed = await s.update(t.id, { name: "Done" }, start + 3 * day);
  expect(completed.nextRunAt).toBeNull(); expect(completed.enabled).toBe(false);
});

test("completed repeats cannot resume unchanged even if the clock moves back", async () => {
  const s = await store(); const t = await s.save(input({ occurrences: 1 }), now);
  const run = await s.claim(t.id, start);
  await s.record(run!.id, { status: "succeeded" });
  await expect(s.update(t.id, { enabled: true }, now)).rejects.toThrow("finished");
  expect((await s.read()).tasks[0]!.enabled).toBe(false);
  const restarted = await s.update(t.id, { enabled: true, schedule: { ...t.schedule, at: new Date(start + day).toISOString() } }, now);
  expect(restarted.nextRunAt).toBe(start + day);
});

test("editing a repeat interval or count with the same anchor preserves history", async () => {
  const s = await store(); const t = await s.save(input(), now);
  const r = await s.claim(t.id, start); await s.record(r!.id, { status: "succeeded" });
  const updated = await s.update(t.id, { schedule: { ...t.schedule, occurrences: 4, everyMinutes: 2880 } }, start + 100);
  expect(updated.nextRunAt).toBe(start + 2 * day);
  expect((await s.read()).runs).toHaveLength(1);
});
