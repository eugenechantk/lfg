import { test, expect } from "bun:test";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskStore, TaskScheduler } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes } from "./scheduled-task-api.ts";
import { scheduledTaskTools } from "./scheduled-task-tools.ts";
import { lfgApi } from "./mcp-lfg-tools.ts";

test("task list includes three newest runs and total without mixing task histories", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-rows-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const task = await store.save({ name: "Daily", prompt: "Review", cwd: dir, agent: "claude", enabled: false,
      schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } });
    const other = await store.save({ name: "Other", prompt: "Review", cwd: dir, agent: "codex", enabled: false,
      schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } });
    for (let i = 0; i < 5; i++) {
      const run = await store.claim(task.id, Date.now() + i, true);
      await store.record(run!.id, { status: "succeeded", sessionId: `session-${i}` });
    }
    const otherRun = await store.claim(other.id, Date.now(), true);
    await store.record(otherRun!.id, { status: "failed" });
    const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "a" }), inspect: async () => ({ state: "working" }) });
    const route = scheduledTaskRoutes(store, runtime, async () => ({} as any), { root: dir, port: 8897, defaultCwd: dir });
    const response = await route(new Request("http://test/api/scheduled-tasks"));
    const body = await response!.json() as any;
    expect(body.tasks[0].runCount).toBe(5);
    expect(body.tasks[0].recentRuns.map((r: any) => r.sessionId)).toEqual(["session-4", "session-3", "session-2"]);
    expect(body.tasks[0].lastRun.sessionId).toBe("session-4");
    expect(body.tasks[1].recentRuns.map((r: any) => r.id)).toEqual([otherRun!.id]);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("MCP tools use real task routes for creation, edits, runs and history", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-api-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "session-a" }), inspect: async () => ({ state: "working" }) });
    const route = scheduledTaskRoutes(store, runtime, async () => ({} as any), { root: dir, port: 8897, defaultCwd: dir });
    const api = lfgApi("http://test", (async (url: any, init: any) => route(new Request(url, init))) as any);
    const tools = scheduledTaskTools(api);
    async function invoke(name: string, args: any = {}) { const response = await tools.find(t => t.name === name)!.run(args); return JSON.parse((response.content[0] as any).text); }
    const { task } = await invoke("create_scheduled_task", { name: "Check", prompt: "Say hello", cwd: dir, agent: "codex", schedule: { kind: "interval", everyMinutes: 30, timezone: "UTC" } });
    expect((await invoke("list_scheduled_tasks")).tasks[0].id).toBe(task.id);
    await invoke("update_scheduled_task", { task_id: task.id, enabled: false });
    expect((await store.read()).tasks[0]!.enabled).toBe(false);
    await invoke("run_scheduled_task", { task_id: task.id });
    await new Promise(r => setTimeout(r, 20));
    expect((await invoke("scheduled_task_runs", { task_id: task.id })).runs[0].sessionId).toBe("session-a");
    await invoke("cancel_scheduled_task", { task_id: task.id });
    expect((await invoke("list_scheduled_tasks")).tasks[0].cancelledAt).toBeNumber();
    const invalid = await route(new Request("http://test/api/scheduled-tasks", { method: "POST", body: "{}" }));
    expect(invalid!.status).toBe(400);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("chat creation delegates to a normal session with local task tool instructions", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-chat-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "a" }), inspect: async () => ({ state: "working" }) });
    let sent: any;
    const route = scheduledTaskRoutes(store, runtime, async (_path, body) => { sent = body; return { sessionId: "chat-a" } as any; }, { root: dir, port: 8897, defaultCwd: dir });
    const response = await route(new Request("http://test/api/scheduled-tasks/chat", { method: "POST", body: JSON.stringify({ prompt: "Tomorrow, review my code", agent: "codex", cwd: dir, model: "gpt-6.1-sol", user: "Eugene", timezone: "Europe/London" }) }));
    expect(response!.status).toBe(200);
    expect(sent.cwd).toBe(dir); expect(sent.model).toBe("gpt-6.1-sol"); expect(sent.user).toBe("Eugene");
    expect(sent.prompt).toContain("Europe/London");
    expect(sent.prompt).toContain('"model":"gpt-6.1-sol"');
    expect(sent.agent).toBe("codex"); expect(sent.prompt).toContain("Tomorrow, review my code"); expect(sent.prompt).toContain("LFG_TASK_BASE=http://127.0.0.1:8897");
    expect((await store.read()).tasks).toHaveLength(0);
    // The setup conversation and the eventual execution can use different repos.
    const executionDir = join(dir, "another-project");
    await mkdir(executionDir);
    const savedResponse = await route(new Request("http://test/api/scheduled-tasks", { method: "POST", body: JSON.stringify({
      name: "Other project review", prompt: "Review changes", cwd: executionDir, agent: "codex", model: "gpt-6.1-sol",
      enabled: false, schedule: { kind: "interval", everyMinutes: 60, timezone: "Europe/London" }
    }) }));
    expect(savedResponse!.status).toBe(201);
    expect((await store.read()).tasks[0]!.cwd).toBe(executionDir);
    expect(sent.cwd).toBe(dir);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("edit chat targets the saved task with current settings and leaves task and history unchanged", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-edit-chat-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const task = await store.save({ name: "Daily review", prompt: "Review changes", cwd: dir, agent: "codex", model: "gpt-6.1-sol", enabled: false,
      schedule: { kind: "cron", expression: "0 9 * * 1-5", timezone: "Asia/Hong_Kong" } });
    const run = await store.claim(task.id, Date.now(), true);
    await store.record(run!.id, { status: "succeeded", sessionId: "history-session" });
    await store.update(task.id, { prompt: "Review changes and tests" });
    const before = await store.read();
    let sent: any; let calledPath = "";
    const runtime = new TaskScheduler(store, { launch: async () => { throw Error("Must not run task"); }, inspect: async () => ({ state: "working" }) });
    const route = scheduledTaskRoutes(store, runtime, async (path, body) => { calledPath = path; sent = body; return { sessionId: "edit-chat" } as any; }, { root: dir, port: 8897, defaultCwd: "/wrong-default" });
    const response = await route(new Request(`http://test/api/scheduled-tasks/${task.id}/chat`, { method: "POST", body: JSON.stringify({ prompt: "Move it to 10 AM", cwd: "/wrong-directory", agent: "codex", model: "wrong-model", timezone: "UTC" }) }));
    expect(response!.status).toBe(200);
    expect(await response!.json()).toEqual({ sessionId: "edit-chat" });
    expect(calledPath).toBe("/api/sessions/new");
    expect(sent.cwd).toBe(dir);
    expect(sent.agent).toBe("claude");
    expect(sent.model).toBeUndefined();
    expect(sent.prompt).toContain(`update ${task.id}`);
    expect(sent.prompt).toContain("Review changes and tests");
    expect(sent.prompt).toContain('"agent":"codex"');
    expect(sent.prompt).toContain('"model":"gpt-6.1-sol"');
    expect(sent.prompt).toContain('"enabled":false');
    expect(sent.prompt).toContain("Asia/Hong_Kong");
    expect(sent.prompt).toContain("LFG_TASK_BASE=http://127.0.0.1:8897");
    expect(sent.prompt).toContain("Do not create a replacement task");
    expect(sent.prompt).toContain("Move it to 10 AM");
    expect(await store.read()).toEqual(before);
    const edited = await route(new Request(`http://test/api/scheduled-tasks/${task.id}`, { method: "POST", body: JSON.stringify({
      schedule: { ...task.schedule, expression: "0 10 * * 1-5" }
    }) }));
    expect(edited!.status).toBe(200);
    const after = await store.read();
    expect(after.tasks).toHaveLength(1);
    expect(after.tasks[0]!.id).toBe(task.id);
    expect(after.tasks[0]!.schedule.expression).toBe("0 10 * * 1-5");
    expect(after.tasks[0]!.agent).toBe("codex");
    expect(after.tasks[0]!.enabled).toBe(false);
    expect(after.runs).toEqual(before.runs);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("edit chat rejects missing tasks, cancelled tasks, and invalid requests before launching", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-edit-errors-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const task = await store.save({ name: "Review", prompt: "Review", cwd: dir, agent: "claude", enabled: false,
      schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } });
    let launches = 0;
    const runtime = new TaskScheduler(store, { launch: async () => ({ sessionId: "run" }), inspect: async () => ({ state: "working" }) });
    const route = scheduledTaskRoutes(store, runtime, async () => { launches++; return {} as any; }, { root: dir, port: 8897, defaultCwd: dir });
    const request = (id: string, body: unknown) => route(new Request(`http://test/api/scheduled-tasks/${id}/chat`, { method: "POST", body: JSON.stringify(body) }));
    expect((await request("00000000-0000-4000-8000-000000000000", { prompt: "Edit" }))!.status).toBe(404);
    for (const body of [null, {}, { prompt: " " }, { prompt: 42 }, { prompt: "x".repeat(50_001) }]) {
      expect((await request(task.id, body))!.status).toBe(400);
    }
    await store.cancel(task.id);
    expect((await request(task.id, { prompt: "Edit" }))!.status).toBe(409);
    expect(launches).toBe(0);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
