import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskStore } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes, taskRuntime } from "./scheduled-task-api.ts";
import { scheduledTaskTools } from "./scheduled-task-tools.ts";

const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map(dir => rm(dir, { recursive: true, force: true }))); });

async function fixture() {
  const dir = await mkdtemp(join(tmpdir(), "lfg-review-")); dirs.push(dir);
  const store = new TaskStore(join(dir, "tasks.json"));
  const task = await store.save({ name: "Warm-up", prompt: "Do useful work", cwd: dir, agent: "codex", enabled: false,
    schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } }, 1000);
  const run = (await store.claim(task.id, 2000, true))!;
  await store.record(run.id, { sessionId: "session", status: "incomplete", finishedAt: 3000,
    outcome: { status: "incomplete", summary: "Old checklist." }, summary: "Original report.", error: "Old checklist." });
  let busy = false, prompt: unknown, text: string;
  const report = (status = "completed", id = run.id) => `Reviewed report.\n<lfg_task_result>${JSON.stringify({ run_id: id, status, summary: "Substantial useful work verified." })}</lfg_task_result>`;
  text = report();
  const calls: string[] = [];
  const call = async (path: string): Promise<any> => {
    calls.push(path);
    if (path === "/api/sessions") return { sessions: [{ sessionId: "session", busy, prompt }] };
    if (path.includes("/messages")) return { messages: [{ role: "assistant", kind: "text", text }] };
    throw Error("Unexpected external call: " + path);
  };
  const runtime = taskRuntime(store, call, () => 4000);
  const route = scheduledTaskRoutes(store, runtime, call, { root: dir, port: 18981, defaultCwd: dir });
  const request = (reason: unknown = "Revised completion policy.", taskId = task.id, runId = run.id) =>
    route(new Request(`http://test/api/scheduled-tasks/${taskId}/runs/${runId}/review`, {
      method: "POST", body: JSON.stringify({ reason }) }));
  return { dir, store, task, run, runtime, route, calls, report, request,
    text: (value: string) => { text = value; }, busy: (value: boolean) => { busy = value; },
    prompt: (value: unknown) => { prompt = value; } };
}

test("review applies a late verdict, exposes it in the list, and preserves original history and scheduling", async () => {
  const f = await fixture();
  const before = await f.store.read();
  const response = (await f.request())!;
  expect(response.status).toBe(200);
  const body = await response.json() as any;
  expect(body.changed).toBe(true);
  const after = await new TaskStore(f.store.path).read();
  const run = after.runs[0]!;
  expect(run.status).toBe("succeeded"); expect(run.outcome?.status).toBe("completed"); expect(run.error).toBeUndefined();
  expect(run.summary).toBe("Reviewed report.");
  expect(run.outcomeReviews).toHaveLength(1);
  expect(run.outcomeReviews![0]).toMatchObject({ at: 4000, reason: "Revised completion policy.", sessionId: "session",
    previous: { status: "incomplete", outcome: before.runs[0]!.outcome, summary: "Original report.", error: "Old checklist." },
    outcome: run.outcome });
  const { status, outcome, summary, error, outcomeReviews, ...identity } = run;
  const { status: oldStatus, outcome: oldOutcome, summary: oldSummary, error: oldError, ...originalIdentity } = before.runs[0]!;
  expect(identity).toEqual(originalIdentity); expect(after.tasks).toEqual(before.tasks);
  expect(f.calls.some(path => path.endsWith("/new") || path.endsWith("/send"))).toBe(false);
  const list = await (await f.route(new Request("http://test/api/scheduled-tasks")))!.json() as any;
  expect(list.tasks[0].lastRun.status).toBe("succeeded"); expect(list.tasks[0].succeededCount).toBe(1);
});

test("identical review is idempotent, while a later valid correction appends another assessment", async () => {
  const f = await fixture(); await f.request();
  expect(await (await f.request())!.json()).toMatchObject({ changed: false });
  expect((await f.store.read()).runs[0]!.outcomeReviews).toHaveLength(1);
  f.text(f.report("incomplete"));
  expect((await f.request("New evidence found."))!.status).toBe(200);
  const run = (await f.store.read()).runs[0]!;
  expect(run.status).toBe("incomplete"); expect(run.outcomeReviews).toHaveLength(2);
  expect(run.outcomeReviews![0]!.previous.status).toBe("incomplete");
  expect(run.outcomeReviews![1]!.previous.status).toBe("succeeded");
});

test("invalid, missing and wrong-run verdicts or reasons leave the entire state untouched", async () => {
  const f = await fixture();
  for (const text of ["Completed", f.report("completed", "wrong-run"), f.report("success"), f.report() + "\nStill working."]) {
    f.text(text); const before = await f.store.read();
    expect((await f.request())!.status).toBe(409); expect(await f.store.read()).toEqual(before);
  }
  f.text(f.report());
  for (const reason of ["", " ", 123, "x".repeat(2001)]) {
    const before = await f.store.read(); expect((await f.request(reason))!.status).toBe(400);
    expect(await f.store.read()).toEqual(before);
  }
});

test("busy, waiting and active runs cannot be reviewed", async () => {
  const f = await fixture(); const before = await f.store.read();
  f.busy(true); expect((await f.request())!.status).toBe(409);
  f.busy(false); f.prompt({ question: "Continue?" }); expect((await f.request())!.status).toBe(409);
  f.prompt(undefined); expect(await f.store.read()).toEqual(before);
  await f.store.record(f.run.id, { status: "running" });
  const active = await f.store.read(); expect((await f.request())!.status).toBe(409);
  expect(await f.store.read()).toEqual(active);
});

test("task/run mismatches are rejected and the MCP review tool uses the same validated route", async () => {
  const f = await fixture(); const before = await f.store.read();
  expect((await f.request("Review", crypto.randomUUID()))!.status).toBe(404);
  expect((await f.request("Review", f.task.id, crypto.randomUUID()))!.status).toBe(404);
  expect(await f.store.read()).toEqual(before);
  const tools = scheduledTaskTools({ get: async () => ({} as any), post: async (path, body) =>
    (await f.route(new Request("http://test" + path, { method: "POST", body: JSON.stringify(body) })))!.json() as any });
  const tool = tools.find(tool => tool.name === "review_scheduled_task_run")!;
  expect(tool).toBeDefined();
  const response = await tool.run({ task_id: f.task.id, run_id: f.run.id, reason: "User reviewed the completion policy." });
  expect(JSON.parse((response.content[0] as any).text).run.status).toBe("succeeded");
});

test("concurrent identical reviews append once and a stale conflicting review cannot overwrite history", async () => {
  const f = await fixture(); const original = (await f.store.read()).runs[0]!;
  const responses = await Promise.all([f.request(), f.request()]);
  const results = await Promise.all(responses.map(response => response!.json())) as any[];
  expect(results.filter(result => result.changed)).toHaveLength(1);
  expect((await f.store.read()).runs[0]!.outcomeReviews).toHaveLength(1);
  const before = await f.store.read();
  await expect(f.store.reviewOutcome(f.task.id, f.run.id, original,
    { status: "error", summary: "A stale correction." }, "Stale report.", "Old review.", 5000)).rejects.toThrow("changed during review");
  expect(await f.store.read()).toEqual(before);
});

test("review leaves pending bookings and unrelated run history untouched", async () => {
  const f = await fixture();
  await f.store.scheduleRetry(f.task.id, new Date(Date.now() + 3600_000).toISOString());
  const other = await f.store.save({ ...f.task, name: "Other task", enabled: false });
  const otherRun = (await f.store.claim(other.id, Date.now(), true))!;
  await f.store.record(otherRun.id, { status: "failed", error: "Unrelated failure." });
  const before = await f.store.read();
  expect((await f.request())!.status).toBe(200);
  const after = await f.store.read();
  expect(after.tasks).toEqual(before.tasks);
  expect(after.runs.filter(run => run.id !== f.run.id)).toEqual(before.runs.filter(run => run.id !== f.run.id));
});
