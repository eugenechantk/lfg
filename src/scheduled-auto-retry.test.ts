import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskScheduler, TaskStore, type TaskInput } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes, upcomingRuns, taskRuntime } from "./scheduled-task-api.ts";

const start = Date.parse("2026-10-21T01:00:00Z"), step = 86400_000;
const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map(d => rm(d, { recursive: true, force: true }))); });
async function fixture(kind: "repeat" | "interval" = "repeat", occurrences = 3) {
  const dir = await mkdtemp(join(tmpdir(), "lfg-auto-retry-")); dirs.push(dir);
  const store = new TaskStore(join(dir, "tasks.json"));
  const schedule: TaskInput["schedule"] = { kind, at: new Date(start).toISOString(), everyMinutes: 1440, timezone: "Asia/Hong_Kong", ...(kind === "repeat" ? { occurrences } : {}) };
  const task = await store.save({ name: "Daily work", prompt: "Finish the work", cwd: dir, agent: "codex", schedule }, start - step);
  return { store, task, read: async () => (await store.read()).tasks[0]! };
}
const incomplete = (store: TaskStore, id: string, at: number) => store.record(id, { status: "incomplete", finishedAt: at, error: "More work remains" });

test.each(["repeat", "interval"] as const)("%s assigns a retry and defers later runs without changing saved settings", async kind => {
  const { store, task, read } = await fixture(kind);
  const run = (await store.claim(task.id, start))!;
  await incomplete(store, run.id, start + 60_000);
  expect(await read()).toMatchObject({ retryAt: start + step, retryOfRunId: run.id, nextRunAt: start + 2 * step, scheduledRunCount: 1, schedule: task.schedule });
  expect(upcomingRuns(await read(), start)).toEqual(kind === "repeat" ? [start + 2 * step, start + 3 * step] : Array.from({ length: 10 }, (_, i) => start + (i + 2) * step));
  await incomplete(store, run.id, start + 120_000);
  expect((await read()).nextRunAt).toBe(start + 2 * step);
});

test("three logical occurrences finish despite two incomplete attempts and a last-occurrence retry", async () => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  const retry = (await store.claim(task.id, start + step, "retry"))!;
  expect(retry).toMatchObject({ trigger: "manual", retryOfRunId: first.id, occurrence: 1 });
  await incomplete(store, retry.id, start + step + 60_000);
  expect(await read()).toMatchObject({ retryAt: start + 2 * step, nextRunAt: start + 3 * step, scheduledRunCount: 1 });
  const retry2 = (await store.claim(task.id, start + 2 * step, "retry"))!;
  await store.record(retry2.id, { status: "succeeded", finishedAt: start + 2 * step + 60_000 });
  const second = (await store.claim(task.id, start + 3 * step))!;
  expect(second).toMatchObject({ occurrence: 2 });
  await store.record(second.id, { status: "succeeded" });
  const third = (await store.claim(task.id, start + 4 * step))!;
  expect(third).toMatchObject({ occurrence: 3 });
  await incomplete(store, third.id, start + 4 * step + 60_000);
  expect(await read()).toMatchObject({ retryAt: start + 5 * step, nextRunAt: null, enabled: false });
  const last = (await store.claim(task.id, start + 5 * step, "retry"))!;
  await store.record(last.id, { status: "succeeded" });
  expect((await store.read()).runs.filter(r => r.status === "succeeded")).toHaveLength(3);
  expect(await read()).toMatchObject({ scheduledRunCount: 3, enabled: false, nextRunAt: null });
  expect((await read()).retryAt).toBeUndefined();
  expect(await store.claim(task.id, start + 6 * step)).toBeNull();
});

test("retry now uses the original occurrence and leaves no duplicate retry", async () => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!; await incomplete(store, first.id, start + 60_000);
  const retry = (await store.claim(task.id, start + 120_000, true))!;
  expect(retry).toMatchObject({ retryOfRunId: first.id, occurrence: 1 });
  await store.record(retry.id, { status: "succeeded", finishedAt: start + 180_000 });
  expect((await read()).nextRunAt).toBe(start + 2 * step);
  expect(await store.claim(task.id, start + step, "retry")).toBeNull();
  expect((await read()).scheduledRunCount).toBe(1);
});

test.each(["incomplete", "failed", "interrupted"] as const)("Retry now %s restores the original future retry without shifting later runs again", async status => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  for (let attempt = 0; attempt < 2; attempt++) {
    const at = start + (attempt + 2) * 60_000;
    const retry = (await store.claim(task.id, at, true))!;
    expect((await read()).retryAt).toBeUndefined();
    // The fallback must survive a host restart while the immediate attempt is active.
    await new TaskStore(store.path).record(retry.id, { status, finishedAt: at + 30_000 });
    expect(await read()).toMatchObject({ retryAt: start + step, retryOfRunId: first.id, nextRunAt: start + 2 * step, scheduledRunCount: 1 });
  }
});

test("Retry now failure after the original retry time uses the next future interval", async () => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  const retry = (await store.claim(task.id, start + 120_000, true))!;
  await store.record(retry.id, { status: "failed", finishedAt: start + step + 60_000 });
  expect(await read()).toMatchObject({ retryAt: start + 2 * step, nextRunAt: start + 3 * step, scheduledRunCount: 1 });
});

test("Retry now failure preserves an explicitly changed pending retry time", async () => {
  const { store, task, read } = await fixture("repeat", 1);
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  const chosen = start + step / 2;
  await store.scheduleRetry(task.id, new Date(chosen).toISOString(), start + 60_000);
  const retry = (await store.claim(task.id, start + 120_000, true))!;
  await store.record(retry.id, { status: "incomplete", finishedAt: start + 180_000 });
  expect(await read()).toMatchObject({ retryAt: chosen, retryOfRunId: first.id, nextRunAt: null, scheduledRunCount: 1 });
});

test("host recovery restores the original retry after an interrupted immediate launch", async () => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  const immediate = (await store.claim(task.id, start + 120_000, true))!;
  const restarted = new TaskScheduler(new TaskStore(store.path), {
    launch: async () => { throw Error("Recovery must not relaunch an uncertain attempt"); },
    inspect: async () => ({ state: "working" }),
  }, () => start + 180_000);
  await restarted.recover();
  expect((await store.read()).runs.find(r => r.id === immediate.id)?.status).toBe("interrupted");
  expect(await read()).toMatchObject({ retryAt: start + step, retryOfRunId: first.id, nextRunAt: start + 2 * step, scheduledRunCount: 1 });
});

test.each([false, true])("restored retry retains its pause behavior when explicitly chosen: %s", async explicit => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await incomplete(store, first.id, start + 60_000);
  await store.update(task.id, { enabled: false }, start + 90_000);
  const at = explicit ? start + step / 2 : start + step;
  if (explicit) await store.scheduleRetry(task.id, new Date(at).toISOString(), start + 100_000);
  const immediate = (await store.claim(task.id, start + 120_000, true))!;
  await store.record(immediate.id, { status: "failed", finishedAt: start + 180_000 });
  expect((await read()).retryAt).toBe(at);
  const due = await new TaskStore(store.path).claim(task.id, at, "retry");
  expect(due != null).toBe(explicit);
  if (explicit) expect(due?.retryOfRunId).toBe(first.id);
});

test("moving recovery earlier keeps deferred runs; moving later moves the remaining cadence", async () => {
  const { store, task, read } = await fixture();
  const first = (await store.claim(task.id, start))!; await incomplete(store, first.id, start + 60_000);
  await store.scheduleRetry(task.id, new Date(start + step / 2).toISOString(), start + 60_000);
  expect((await read()).nextRunAt).toBe(start + 2 * step);
  await store.scheduleRetry(task.id, new Date(start + 3.5 * step).toISOString(), start + 60_000);
  expect((await read()).nextRunAt).toBe(start + 4 * step);
  expect(upcomingRuns(await read(), start)).toEqual([start + 4 * step, start + 5 * step]);
  expect(await store.claim(task.id, start + 3 * step)).toBeNull();
  const retry = (await store.claim(task.id, start + 3.5 * step, "retry"))!;
  await store.record(retry.id, { status: "succeeded", finishedAt: start + 3.5 * step + 60_000 });
  const next = (await store.claim(task.id, start + 4 * step))!;
  expect(next).toMatchObject({ occurrence: 2 });
});

test("recovery survives reload and concurrent claims; paused automatic retries wait", async () => {
  const { store, task } = await fixture();
  const first = (await store.claim(task.id, start))!; await incomplete(store, first.id, start + 60_000);
  const reloaded = new TaskStore(store.path);
  await reloaded.update(task.id, { enabled: false }, start + 120_000);
  expect(await reloaded.claim(task.id, start + step, "retry")).toBeNull();
  // A user can explicitly request a retry while the schedule stays paused.
  await reloaded.scheduleRetry(task.id, new Date(start + step + 60_000).toISOString(), start + step);
  const claims = await Promise.all([reloaded.claim(task.id, start + step + 60_000, "retry"), reloaded.claim(task.id, start + step + 60_000, "retry")]);
  expect(claims.filter(Boolean)).toHaveLength(1);
  expect(claims.find(Boolean)).toMatchObject({ retryOfRunId: first.id });
});

test("stopping or editing a schedule prevents old runs from assigning recovery", async () => {
  for (const edit of [false, true]) {
    const { store, task, read } = await fixture(); const run = (await store.claim(task.id, start))!;
    if (edit) await store.update(task.id, { schedule: { ...task.schedule, at: new Date(start + step).toISOString() } }, start + 100);
    else await store.cancel(task.id, start + 100);
    await incomplete(store, run.id, start + 60_000);
    expect((await read()).retryAt).toBeUndefined();
    if (edit) expect((await read()).nextRunAt).toBe(start + step);
  }
});

test("unrelated manual incomplete runs and initial infrastructure failures do not create automatic retries", async () => {
  const { store, task, read } = await fixture();
  const manual = (await store.claim(task.id, start - 60_000, true))!;
  await incomplete(store, manual.id, start - 30_000);
  expect((await read()).retryAt).toBeUndefined();
  const scheduled = (await store.claim(task.id, start))!;
  await store.record(scheduled.id, { status: "failed", finishedAt: start + 60_000 });
  expect((await read()).retryAt).toBeUndefined();
});

test("scheduler completion uses fresh task state and never launches a displaced occurrence", async () => {
  const { store, task } = await fixture(); let time = start;
  const runtime = new TaskScheduler(store, { launch: async (_, run) => ({ sessionId: run.id }), inspect: async () => ({ state: "idle", summary: "Incomplete", outcome: { status: "incomplete", summary: "More remains" } }) }, () => time);
  await runtime.tick(); time += 60_000; await runtime.tick(); time += 6000; await runtime.tick(); time = start + step; await runtime.tick();
  const state = await store.read();
  expect(state.runs).toHaveLength(2);
  expect(state.runs[1]).toMatchObject({ retryOfRunId: state.runs[0]!.id });
  expect(state.tasks[0]!.nextRunAt).toBe(start + 2 * step);
});

test("HTTP lists assigned retry and deferred dates; runtime tells retry the original occurrence", async () => {
  const { store, task } = await fixture();
  const first = (await store.claim(task.id, start))!; await incomplete(store, first.id, start + 60_000);
  let payload: any;
  const runtime = taskRuntime(store, async (_path, body) => { payload = body; return { sessionId: "probe" } as any; }, () => start + step);
  const routes = scheduledTaskRoutes(store, runtime, async () => ({} as any), { root: process.cwd(), port: 18957, defaultCwd: tmpdir() });
  const response = await routes(new Request("http://test/api/scheduled-tasks"));
  const listed = (await response!.json() as any).tasks[0];
  expect(listed).toMatchObject({ retryAt: start + step, retryOfRunId: first.id, upcomingRuns: [start + 2 * step, start + 3 * step] });
  await runtime.tick();
  expect(payload.prompt).toContain("Occurrence 1 of 3");
  expect(payload.prompt).toContain("Retry");
});

test("legacy active runs retain their occurrence when their retry moves earlier", async () => {
  const { store, task } = await fixture();
  const first = (await store.claim(task.id, start))!;
  await store.record(first.id, { status: "succeeded" });
  const second = (await store.claim(task.id, start + step))!;
  const old = await store.read();
  delete old.runs[1]!.occurrence; delete old.runs[1]!.scheduleRevision;
  await writeFile(store.path, JSON.stringify(old));
  const reloaded = new TaskStore(store.path);
  await incomplete(reloaded, second.id, start + step + 60_000);
  await reloaded.scheduleRetry(task.id, new Date(start + 1.5 * step).toISOString(), start + step + 60_000);
  let prompt = "";
  const runtime = taskRuntime(reloaded, async (_path, body: any) => { prompt = body.prompt; return { sessionId: "legacy" } as any; }, () => start + 1.5 * step);
  await runtime.tick();
  expect(prompt).toContain("Occurrence 2 of 3");
});

test("pausing an active final recovery also pauses any later automatic attempt", async () => {
  const { store, task, read } = await fixture("repeat", 1);
  const first = (await store.claim(task.id, start))!; await incomplete(store, first.id, start + 60_000);
  const retry = (await store.claim(task.id, start + step, "retry"))!;
  await store.update(task.id, { enabled: false }, start + step + 60_000);
  await incomplete(store, retry.id, start + step + 120_000);
  expect(await store.claim(task.id, start + 2 * step, "retry")).toBeNull();
  await store.update(task.id, { enabled: true }, start + 2 * step);
  const resumed = (await store.claim(task.id, start + 2 * step, "retry"))!;
  expect(resumed.retryOfRunId).toBe(first.id);
  await store.record(resumed.id, { status: "succeeded" });
  expect(await read()).toMatchObject({ enabled: false, nextRunAt: null, scheduledRunCount: 1 });
});
