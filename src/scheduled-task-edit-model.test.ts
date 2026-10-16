import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TaskScheduler, TaskStore, type TaskInput } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes } from "./scheduled-task-api.ts";

type Config = Pick<TaskInput, "agent" | "model">;
async function withChat(config: Config, run: (f: Awaited<ReturnType<typeof fixture>>) => Promise<void>) {
  const dir = await mkdtemp(join(tmpdir(), "lfg-edit-model-"));
  try { await run(await fixture(dir, config)); }
  finally { await rm(dir, { recursive: true, force: true }); }
}
async function fixture(dir: string, config: Config) {
  const store = new TaskStore(join(dir, "tasks.json"));
  const task = await store.save({ name: "Edit model probe", prompt: "Do nothing", cwd: dir, ...config,
    enabled: false, schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } });
  const calls: { path: string; body: any }[] = [];
  const alive = new Set<string>();
  const faults = { launch: false };
  let next = 0;
  const scheduler = new TaskScheduler(store, { launch: async () => { throw Error("Do not run task"); }, inspect: async () => ({ state: "idle" }) });
  const route = scheduledTaskRoutes(store, scheduler, async (path, body: any) => {
    calls.push({ path, body });
    if (path === "/api/sessions") return { sessions: [...alive].map(sessionId => ({ sessionId })) } as any;
    if (path === "/api/sessions/new") {
      if (faults.launch) throw Error("Provider unavailable");
      const sessionId = `chat-${++next}`;
      alive.add(sessionId);
      return { sessionId, agent: body.agent } as any;
    }
    return { ok: true } as any;
  }, { root: dir, port: 8897, defaultCwd: "/wrong-default" });
  const chat = async () => {
    const response = (await route(new Request(`http://test/api/scheduled-tasks/${task.id}/chat`, {
      method: "POST", body: JSON.stringify({ prompt: "What are the current instructions?", agent: "wrong-agent", model: "wrong-model" }),
    })))!;
    return { status: response.status, body: await response.json() as any };
  };
  return { store, task, calls, alive, faults, chat };
}

for (const config of [
  { agent: "claude", model: "opus" }, { agent: "codex", model: "gpt-6.1-sol" },
  { agent: "claude" }, { agent: "codex" },
] satisfies Config[]) {
  test(`edit chat uses saved ${config.agent} / ${config.model ?? "default"} and reuses the matching chat`, async () => withChat(config, async f => {
    expect((await f.chat()).status).toBe(200);
    const launch = f.calls.find(c => c.path === "/api/sessions/new")!.body;
    expect(launch.agent).toBe(config.agent);
    expect(launch.model).toBe(config.model);
    expect(launch.purpose).toBe("task-edit");
    expect(launch.taskId).toBe(f.task.id);
    f.calls.length = 0;
    expect((await f.chat()).body).toEqual({ sessionId: "chat-1", reused: true });
    expect(f.calls.map(c => c.path)).toEqual(["/api/sessions", "/api/sessions/chat-1/send"]);
  }));
}

for (const patch of [
  { agent: "codex", model: "gpt-6.1-sol" }, { model: "sonnet" }, { model: null },
] satisfies Partial<Config>[]) {
  test(`edit chat replaces the live chat after task settings change: ${JSON.stringify(patch)}`, async () => withChat({ agent: "claude", model: "opus" }, async f => {
    await f.chat();
    await f.store.update(f.task.id, patch);
    f.calls.length = 0;
    expect((await f.chat()).body.sessionId).toBe("chat-2");
    expect(f.calls.some(c => c.path.endsWith("/send"))).toBe(false);
    const launch = f.calls.find(c => c.path === "/api/sessions/new")!.body;
    expect(launch.agent).toBe(patch.agent ?? "claude");
    expect(launch.model).toBe(patch.model ?? undefined);
    const saved = (await f.store.read()).tasks[0]!;
    expect(saved.editSessionIds).toEqual(["chat-1", "chat-2"]);
    expect(saved.editSessionId).toBe("chat-2");
    expect(f.alive.has("chat-1")).toBe(true);
  }));
}

test("legacy Claude editor is replaced for a Codex task while keeping edit history", async () => withChat({ agent: "codex", model: "gpt-6.1-sol" }, async f => {
  await f.store.setEditSession(f.task.id, "legacy-claude");
  f.alive.add("legacy-claude");
  expect((await f.chat()).body.sessionId).toBe("chat-1");
  expect(f.calls.some(c => c.path.endsWith("/send"))).toBe(false);
  expect((await f.store.read()).tasks[0]!.editSessionIds).toEqual(["legacy-claude", "chat-1"]);
}));

test("failed replacement preserves the old chat reference and history", async () => withChat({ agent: "claude", model: "opus" }, async f => {
  await f.chat();
  await f.store.update(f.task.id, { agent: "codex", model: "gpt-6.1-sol" });
  const before = await f.store.read();
  f.faults.launch = true;
  expect(await f.chat()).toEqual({ status: 500, body: { error: "Provider unavailable" } });
  expect(await f.store.read()).toEqual(before);
}));

test("unrelated task edits keep the matching conversation", async () => withChat({ agent: "codex", model: "gpt-6.1-sol" }, async f => {
  await f.chat();
  await f.store.update(f.task.id, { name: "Renamed", prompt: "Updated instructions" });
  expect((await f.chat()).body).toEqual({ sessionId: "chat-1", reused: true });
}));
