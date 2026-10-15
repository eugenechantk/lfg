import { test, expect } from "bun:test";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskStore, TaskScheduler } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes, taskAuthoringPrompt, taskEditingPrompt, taskRuntime } from "./scheduled-task-api.ts";
import { scheduledTaskTools } from "./scheduled-task-tools.ts";
import { lfgApi } from "./mcp-lfg-tools.ts";

test("finite repeat setup is exposed by chat and MCP and round-trips through the API", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-repeat-api-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const runtime = new TaskScheduler(store, { launch: async () => { throw Error("Do not execute setup"); }, inspect: async () => ({ state: "working" }) });
    const route = scheduledTaskRoutes(store, runtime, async () => ({} as any), { root: dir, port: 8897, defaultCwd: dir });
    const tools = scheduledTaskTools(lfgApi("http://test", (async (url: any, init: any) => route(new Request(url, init))) as any));
    const create = tools.find(t => t.name === "create_scheduled_task")!;
    const schema = create.inputSchema as any;
    expect(schema.properties.schedule.properties.kind.enum).toContain("repeat");
    expect(schema.properties.schedule.properties.occurrences.maximum).toBe(1000);
    const schedule = { kind: "repeat", at: new Date(Date.now() + 86400_000).toISOString(), everyMinutes: 1440, occurrences: 3, timezone: "Asia/Hong_Kong" };
    const result = await create.run({ name: "Repeat", prompt: "Do the work", cwd: dir, agent: "codex", schedule });
    const task = JSON.parse((result.content[0] as any).text).task;
    expect(task.schedule).toEqual(schedule);
    expect((await store.read()).runs).toHaveLength(0);
    for (const prompt of [taskAuthoringPrompt({ prompt: "3 occurrences, every day", cwd: dir, agent: "codex", timezone: "UTC", root: dir, port: 8897 }), taskEditingPrompt(task, "Repeat three times", { root: dir, port: 8897 })]) {
      expect(prompt).toContain('"kind":"repeat"');
      expect(prompt).toContain('"occurrences":3');
      expect(prompt).toContain("including the first");
      expect(prompt).toContain("Do not ask the execution agent to reschedule");
    }
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test("repeat execution gives the agent host-owned recurrence instructions", async () => {
  const dir = await mkdtemp(join(tmpdir(), "lfg-repeat-runtime-"));
  try {
    const store = new TaskStore(join(dir, "tasks.json"));
    const now = Date.now();
    const task = await store.save({ name: "Repeat", prompt: "Review changes", cwd: dir, agent: "codex",
      schedule: { kind: "repeat", at: new Date(now - 1000).toISOString(), everyMinutes: 1440, occurrences: 3, timezone: "UTC" } }, now - 2000);
    let sent: any;
    const runtime = taskRuntime(store, async (path, body) => {
      if (path === "/api/sessions/new") { sent = body; return { sessionId: "repeat-run" } as any; }
      return { sessions: [] } as any;
    });
    await runtime.tick();
    expect(sent.prompt).toContain("Occurrence 1 of 3.");
    expect(sent.prompt).toContain("The host manages this finite repeat.");
    expect(sent.prompt).toContain("Do not create, re-arm, or modify this task's schedule.");
    expect((await store.read()).tasks.find(t => t.id === task.id)!.nextRunAt).toBe(now - 1000 + 86400_000);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

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
    // The task remembers its edit chat (so the next request reuses it); nothing else changes.
    const afterChat = await store.read();
    expect(afterChat.tasks.find(t => t.id === task.id)!.editSessionId).toBe("edit-chat");
    expect(afterChat.tasks.find(t => t.id === task.id)!.editSessionIds).toEqual(["edit-chat"]);
    for (const t of afterChat.tasks) { delete t.editSessionId; delete t.editSessionIds; }
    expect(afterChat).toEqual(before);
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
