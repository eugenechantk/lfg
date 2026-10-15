import { test, expect } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskStore, TaskScheduler, nextOccurrence, nextOccurrences, lastOccurrence, validateSchedule, type TaskSchedule } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes, upcomingRuns, consecutiveFailures, previewSchedule, tagEditChats } from "./scheduled-task-api.ts";

const MIN = 60_000, HOUR = 60 * MIN, DAY = 24 * HOUR;
const withStore = async (fn: (store: TaskStore, dir: string) => Promise<void>) => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-a2-"));
  try { await fn(new TaskStore(join(dir, "tasks.json")), dir); } finally { await rm(dir, { recursive: true, force: true }); }
};
const base = (dir: string, schedule: TaskSchedule, extra: object = {}) =>
  ({ name: "Task", prompt: "Do it", cwd: dir, agent: "claude" as const, schedule, ...extra });

test("an interval with a start keeps an exact gap from that start", () => {
  const at = Date.parse("2026-10-16T09:00:00+08:00");
  const s: TaskSchedule = { kind: "interval", everyMinutes: 3 * 1440, at: new Date(at).toISOString(), timezone: "Asia/Hong_Kong" };
  expect(nextOccurrence(s, at - HOUR)).toBe(at);
  expect(nextOccurrence(s, at)).toBe(at + 3 * DAY);
  expect(nextOccurrence(s, at + 3 * DAY + MIN)).toBe(at + 6 * DAY);
  expect(nextOccurrences(s, at - 1, 3)).toEqual([at, at + 3 * DAY, at + 6 * DAY]);
});

test("an interval without a start still counts from the last run (older tasks)", () => {
  const s: TaskSchedule = { kind: "interval", everyMinutes: 60, timezone: "UTC" };
  expect(nextOccurrence(s, 1_000_000)).toBe(1_000_000 + HOUR);
});

test("cron maxRuns counts scheduled runs only and closes the task after the last one", async () => withStore(async (store, dir) => {
  const now = Date.parse("2026-10-15T10:12:00Z");
  const task = await store.save(base(dir, { kind: "cron", expression: "*/5 * * * *", maxRuns: 2, timezone: "UTC" }), now);
  expect(task.nextRunAt).toBe(Date.parse("2026-10-15T10:15:00Z"));
  expect(await store.claim(task.id, now + 3 * MIN)).not.toBeNull();
  let saved = (await store.read()).tasks[0]!;
  expect(saved.scheduledRunCount).toBe(1);
  expect(saved.nextRunAt).toBe(Date.parse("2026-10-15T10:20:00Z"));
  await store.record((await store.read()).runs[0]!.id, { status: "succeeded", finishedAt: now + 4 * MIN });
  // A manual run in between does not use one up.
  expect(await store.claim(task.id, now + 5 * MIN, true)).not.toBeNull();
  await store.record((await store.read()).runs[1]!.id, { status: "succeeded", finishedAt: now + 6 * MIN });
  expect((await store.read()).tasks[0]!.scheduledRunCount).toBe(1);
  expect(await store.claim(task.id, now + 8 * MIN)).not.toBeNull();
  saved = (await store.read()).tasks[0]!;
  expect(saved.scheduledRunCount).toBe(2);
  expect(saved.nextRunAt).toBeNull();
  expect(saved.enabled).toBe(false);
}));

test("cron and interval end dates stop the schedule", () => {
  const now = Date.parse("2026-10-15T10:00:00Z");
  const cron: TaskSchedule = { kind: "cron", expression: "0 9 * * *", endsAt: "2026-10-17T12:00:00Z", timezone: "UTC" };
  expect(nextOccurrences(cron, now, 5)).toEqual([Date.parse("2026-10-16T09:00:00Z"), Date.parse("2026-10-17T09:00:00Z")]);
  expect(lastOccurrence(cron, now)).toBe(Date.parse("2026-10-17T09:00:00Z"));
  const gap: TaskSchedule = { kind: "interval", everyMinutes: 1440, at: "2026-10-16T09:00:00Z", endsAt: "2026-10-18T10:00:00Z", timezone: "UTC" };
  expect(nextOccurrences(gap, now, 5)).toEqual([Date.parse("2026-10-16T09:00:00Z"), Date.parse("2026-10-17T09:00:00Z"), Date.parse("2026-10-18T09:00:00Z")]);
  expect(lastOccurrence(gap, now)).toBe(Date.parse("2026-10-18T09:00:00Z"));
});

test("schedule validation rejects ends that do not fit the kind", () => {
  const now = Date.parse("2026-10-15T10:00:00Z");
  const bad: [TaskSchedule, string][] = [
    [{ kind: "interval", everyMinutes: 60, maxRuns: 3, timezone: "UTC" }, "maxRuns is for cron"],
    [{ kind: "once", at: "2026-10-16T09:00:00Z", endsAt: "2026-10-20T00:00:00Z", timezone: "UTC" }, "Only cron and interval"],
    [{ kind: "cron", expression: "0 9 * * *", endsAt: "2026-10-14T00:00:00Z", timezone: "UTC" }, "ends before its next run"],
    [{ kind: "cron", expression: "0 9 * * *", maxRuns: 2, endsAt: "2026-10-20T00:00:00Z", timezone: "UTC" }, "not both"],
    [{ kind: "cron", expression: "0 9 * * *", maxRuns: 0, timezone: "UTC" }, "1 to 1,000 runs"],
    [{ kind: "interval", everyMinutes: 60, at: "tomorrow", timezone: "UTC" }, "ISO date"],
  ];
  for (const [s, message] of bad) expect(() => validateSchedule(s, now)).toThrow(message);
  // An interval may start in the past: it is an anchor, not a first run.
  expect(validateSchedule({ kind: "interval", everyMinutes: 60, at: "2026-10-01T09:00:00Z", timezone: "UTC" }, now).at).toBe("2026-10-01T09:00:00Z");
});

test("pausing records when, resuming clears it, and a schedule change resets the run count", async () => withStore(async (store, dir) => {
  const now = Date.parse("2026-10-15T10:00:00Z");
  const task = await store.save(base(dir, { kind: "cron", expression: "0 9 * * *", maxRuns: 5, timezone: "UTC" }), now);
  await store.claim(task.id, Date.parse("2026-10-16T09:00:30Z"));
  const paused = await store.update(task.id, { enabled: false }, now + DAY + HOUR);
  expect(paused.pausedAt).toBe(now + DAY + HOUR);
  expect(paused.scheduledRunCount).toBe(1);
  const resumed = await store.update(task.id, { enabled: true }, now + 2 * DAY);
  expect(resumed.pausedAt).toBeUndefined();
  expect(resumed.scheduledRunCount).toBe(1);
  const changed = await store.update(task.id, { schedule: { kind: "cron", expression: "0 10 * * *", maxRuns: 5, timezone: "UTC" } }, now + 2 * DAY);
  expect(changed.scheduledRunCount).toBe(0);
}));

test("upcoming runs: active, paused (as if resumed), passed one-time, cancelled", async () => withStore(async (store, dir) => {
  const now = Date.now();
  const active = await store.save(base(dir, { kind: "cron", expression: "0 9 * * *", timezone: "UTC" }), now);
  expect(upcomingRuns(active, now)).toHaveLength(3);
  expect(upcomingRuns(active, now)[0]).toBe(active.nextRunAt!);
  const paused = await store.update(active.id, { enabled: false }, now);
  const runs = upcomingRuns(paused, now);
  expect(runs).toHaveLength(3);
  expect(runs[0]).toBeGreaterThan(now);
  const once = await store.save(base(dir, { kind: "once", at: new Date(now + HOUR).toISOString(), timezone: "UTC" }, { enabled: false }), now);
  expect(upcomingRuns(once, now)).toEqual([now + HOUR]);
  expect(upcomingRuns(once, now + 2 * HOUR)).toEqual([]);
  const cancelled = await store.cancel(active.id, now);
  expect(upcomingRuns(cancelled, now)).toEqual([]);
}));

test("consecutive failures count back from the newest finished run", () => {
  const run = (status: any) => ({ id: status, taskId: "t", taskName: "T", agent: "claude", trigger: "scheduled" as const, scheduledFor: 0, startedAt: 0, status });
  expect(consecutiveFailures([run("succeeded"), run("failed"), run("interrupted")])).toBe(2);
  expect(consecutiveFailures([run("failed"), run("succeeded")])).toBe(0);
  expect(consecutiveFailures([run("failed"), run("running")])).toBe(1);
  expect(consecutiveFailures([])).toBe(0);
});

test("preview returns next runs, the last run of a finite schedule, or the validation error", () => {
  const now = Date.parse("2026-10-15T10:12:00+08:00");
  const weekdays = previewSchedule({ kind: "cron", expression: "0 9 * * 1-5", maxRuns: 10, timezone: "Asia/Hong_Kong" }, now);
  expect(weekdays.nextRuns.map(t => new Date(t).toISOString())).toEqual([
    "2026-10-16T01:00:00.000Z", "2026-10-19T01:00:00.000Z", "2026-10-20T01:00:00.000Z", "2026-10-21T01:00:00.000Z", "2026-10-22T01:00:00.000Z"]);
  expect(new Date(weekdays.lastRun!).toISOString()).toBe("2026-10-29T01:00:00.000Z");
  const repeat = previewSchedule({ kind: "repeat", at: "2026-10-16T09:00:00+08:00", everyMinutes: 4320, occurrences: 5, timezone: "Asia/Hong_Kong" }, now);
  expect(new Date(repeat.lastRun!).toISOString()).toBe("2026-10-28T01:00:00.000Z");
  expect(previewSchedule({ kind: "cron", expression: "0 9 * * *", timezone: "Asia/Hong_Kong" }, now).lastRun).toBeNull();
  expect(() => previewSchedule({ kind: "cron", expression: "nope", timezone: "UTC" }, now)).toThrow();
  // A running series opened in the form: its start is in the past, and that is fine.
  const running = previewSchedule({ kind: "repeat", at: "2026-10-13T08:30:00+08:00", everyMinutes: 1440, occurrences: 5, timezone: "Asia/Hong_Kong" }, now);
  expect(running.nextRuns.map(t => new Date(t).toISOString())).toEqual(["2026-10-16T00:30:00.000Z", "2026-10-17T00:30:00.000Z"]);
  expect(() => previewSchedule({ kind: "once", at: "2026-10-13T08:30:00+08:00", timezone: "Asia/Hong_Kong" }, now)).toThrow("future");
});

test("a task keeps one edit chat: tagged when created, reused while alive, replaced once it ends", async () => withStore(async (store, dir) => {
  const task = await store.save(base(dir, { kind: "cron", expression: "0 9 * * *", timezone: "UTC" }));
  const scheduler = new TaskScheduler(store, { launch: async () => ({ sessionId: "x" }), inspect: async () => ({ state: "working" }) });
  const calls: [string, any][] = [];
  let alive = new Set<string>();
  let next = 1;
  const route = scheduledTaskRoutes(store, scheduler, async (path: string, body?: any) => {
    calls.push([path, body]);
    if (path === "/api/sessions") return { sessions: [...alive].map(sessionId => ({ sessionId })) } as any;
    if (path === "/api/sessions/new") { const sessionId = `chat-${next++}`; alive.add(sessionId); return { sessionId } as any; }
    return { ok: true } as any;
  }, { root: dir, port: 1, defaultCwd: dir });
  const chat = async (prompt: string) => (await route(new Request(`http://x/api/scheduled-tasks/${task.id}/chat`, { method: "POST", body: JSON.stringify({ prompt }) })))!.json() as any;

  expect((await chat("skip mondays")).sessionId).toBe("chat-1");
  const created = calls.find(([p]) => p === "/api/sessions/new")![1];
  expect(created.purpose).toBe("task-edit"); expect(created.taskId).toBe(task.id);
  expect((await store.read()).tasks[0]!.editSessionId).toBe("chat-1");

  calls.length = 0;
  const reused = await chat("and run at 8");
  expect(reused).toEqual({ sessionId: "chat-1", reused: true });
  expect(calls.find(([p]) => p === "/api/sessions/chat-1/send")![1]).toEqual({ text: "and run at 8" });
  expect(calls.some(([p]) => p === "/api/sessions/new")).toBe(false);

  alive = new Set();
  expect((await chat("use codex")).sessionId).toBe("chat-2");
  expect((await store.read()).tasks[0]!.editSessionId).toBe("chat-2");
}));

test("the list carries the new fields and embeds a waiting run's question; preview route answers errors as data", async () => withStore(async (store, dir) => {
  const now = Date.now();
  const task = await store.save(base(dir, { kind: "cron", expression: "0 9 * * *", timezone: "UTC" }), now);
  const run = (await store.claim(task.id, now, true))!;
  await store.record(run.id, { status: "needs_input", sessionId: "s1", needsInputAt: now });
  const scheduler = new TaskScheduler(store, { launch: async () => ({ sessionId: "x" }), inspect: async () => ({ state: "working" }) });
  const prompt = { question: "Which build?", options: [{ index: 1, label: "1.3.1" }, { index: 2, label: "1.3.0" }], context: "Two builds." };
  const route = scheduledTaskRoutes(store, scheduler, async (path: string) => path === "/api/sessions" ? { sessions: [{ sessionId: "s1", prompt }] } as any : {} as any, { root: dir, port: 1, defaultCwd: dir });
  const list = await (await route(new Request("http://x/api/scheduled-tasks")))!.json() as any;
  const t = list.tasks[0];
  expect(t.upcomingRuns).toHaveLength(3);
  expect(t.consecutiveFailures).toBe(0);
  expect(t.succeededCount).toBe(0);
  expect(t.currentRun.prompt).toEqual(prompt);
  expect(t.currentRun.needsInputAt).toBe(now);
  const bad = await (await route(new Request("http://x/api/scheduled-tasks/preview", { method: "POST", body: JSON.stringify({ schedule: { kind: "cron", expression: "0 9 * * 1-5", maxRuns: 0, timezone: "UTC" } }) })))!.json() as any;
  expect(bad.error).toContain("1 to 1,000 runs");
  expect(bad.nextRuns).toEqual([]);
  const good = await (await route(new Request("http://x/api/scheduled-tasks/preview", { method: "POST", body: JSON.stringify({ schedule: { kind: "interval", everyMinutes: 7, at: new Date(now + HOUR).toISOString(), timezone: "UTC" } }) })))!.json() as any;
  expect(good.nextRuns).toHaveLength(5);
  expect(good.nextRuns[1] - good.nextRuns[0]).toBe(7 * MIN);
}));

test("closed edit chats stay tagged: the store keeps each task's chat ids and listings mark them", async () => withStore(async (store) => {
  const t = await store.save({ name: "T", prompt: "p", cwd: "/tmp", agent: "claude",
    schedule: { kind: "cron", expression: "0 9 * * *", timezone: "UTC" } }, Date.parse("2026-10-15T00:00:00Z"));
  await store.setEditSession(t.id, "chat-1");
  await store.setEditSession(t.id, "chat-2");
  await store.setEditSession(t.id, "chat-1");
  expect((await store.read()).tasks[0]!.editSessionIds).toEqual(["chat-2", "chat-1"]);
  const ids = await store.editSessionIds();
  expect([...ids].sort()).toEqual(["chat-1", "chat-2"]);
  const page = tagEditChats({ sessions: [{ sessionId: "chat-2", title: "Change task" }, { sessionId: "work" }], nextBefore: null }, ids);
  expect(page.sessions[0]).toMatchObject({ sessionId: "chat-2", purpose: "task-edit" });
  expect((page.sessions[1] as { purpose?: string }).purpose).toBeUndefined();
  expect(page.nextBefore).toBeNull();
}));
