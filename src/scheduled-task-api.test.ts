import { test, expect } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
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
    const response = await route(new Request("http://test/api/scheduled-tasks/chat", { method: "POST", body: JSON.stringify({ prompt: "Tomorrow, review my code", agent: "codex" }) }));
    expect(response!.status).toBe(200);
    expect(sent.agent).toBe("codex"); expect(sent.prompt).toContain("Tomorrow, review my code"); expect(sent.prompt).toContain("LFG_TASK_BASE=http://127.0.0.1:8897");
    expect((await store.read()).tasks).toHaveLength(0);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
