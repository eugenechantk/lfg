import { afterEach, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskError, TaskStore } from "./scheduled-tasks.ts";
import { scheduledTaskRoutes, taskRuntime, taskRunSystemPrompt } from "./scheduled-task-api.ts";

const dirs: string[] = [];
afterEach(async () => { await Promise.all(dirs.splice(0).map(path => rm(path, { recursive: true, force: true }))); });

async function fixture(agent: "claude" | "codex" = "codex") {
  const dir = await mkdtemp(join(tmpdir(), "lfg-task-verdict-")); dirs.push(dir);
  const store = new TaskStore(join(dir, "tasks.json"));
  let now = Date.now();
  const task = await store.save({ name: "Research", prompt: "Watch for 45 minutes and write a report.", cwd: dir, agent, enabled: false, schedule: { kind: "interval", everyMinutes: 60, timezone: "UTC" } }, now);
  const run = (await store.claim(task.id, now, true))!;
  await store.record(run.id, { status: "running", sessionId: "session" });
  let sessions: any[] = [{ sessionId: "session", busy: false }];
  let messages: any[] = [];
  let readError: Error | undefined;
  const calls: [string, any][] = [];
  const call = async (path: string, body?: any): Promise<any> => {
    calls.push([path, body]);
    if (path === "/api/sessions") return { sessions };
    if (path.includes("/messages")) { if (readError) throw readError; return { messages }; }
    return { sessionId: "launch-session" };
  };
  const runtime = taskRuntime(store, call, () => now);
  const route = scheduledTaskRoutes(store, runtime, call, { root: dir, port: 18981, defaultCwd: dir });
  return {
    store, task, run, runtime, route, calls,
    sessions: (value: any[]) => { sessions = value; }, messages: (value: any[]) => { messages = value; },
    readError: (value: Error) => { readError = value; },
    report: (status: string, summary = "Only 12 of 45 minutes completed.", runId = run.id) => [{ role: "assistant", kind: "text", text: `Human report.\n<lfg_task_result>${JSON.stringify({ run_id: runId, status, summary })}</lfg_task_result>` }],
    settle: async () => { await runtime.tick(); now += 6000; await runtime.tick(); },
    result: async () => (await store.read()).runs.find(r => r.id === run.id)!,
  };
}

test("the runtime records each verdict and exposes it through real task routes", async () => {
  for (const agent of ["claude", "codex"] as const) for (const [verdict, status] of [["completed", "succeeded"], ["incomplete", "incomplete"], ["error", "failed"]] as const) {
    const f = await fixture(agent);
    const reason = verdict === "completed" ? "All 45 minutes and the report were verified."
      : verdict === "error" ? "The research service failed before the work could finish." : "Only 12 of 45 minutes completed.";
    f.messages(f.report(verdict, reason)); await f.settle();
    expect((await f.result()).status).toBe(status!);
    const list = await (await f.route(new Request("http://test/api/scheduled-tasks")))!.json() as any;
    expect(list.tasks[0].lastRun.outcome.status).toBe(verdict!);
    expect(list.tasks[0].succeededCount).toBe(verdict === "completed" ? 1 : 0);
    expect(list.tasks[0].consecutiveFailures).toBe(verdict === "completed" ? 0 : 1);
    expect(list.tasks[0].currentRun).toBeUndefined();
    expect((await new TaskStore(f.store.path).read()).runs[0]!.status).toBe(status!);
  }
});

test("missing, invalid, wrong-run and quoted verdicts never earn completion", async () => {
  for (const message of ["I stopped because login failed.", "Done.", '<lfg_task_result>{"status":"completed"}</lfg_task_result>']) {
    const f = await fixture(); f.messages([{ role: "assistant", kind: "text", text: message }]); await f.settle();
    expect((await f.result()).status).toBe("incomplete"); expect((await f.result()).error).toContain("verdict");
  }
  const f = await fixture(); f.messages(f.report("completed", "Done", "wrong-run")); await f.settle();
  expect((await f.result()).status).toBe("incomplete");
});

test("busy and waiting sessions stay active even with a success block", async () => {
  const f = await fixture(); f.messages(f.report("completed"));
  f.sessions([{ sessionId: "session", busy: true }]); await f.settle(); expect((await f.result()).status).toBe("running");
  f.sessions([{ sessionId: "session", busy: true, prompt: { question: "Sign in?" } }]); await f.settle();
  expect((await f.result()).status).toBe("needs_input");
  f.sessions([{ sessionId: "session", busy: false }]); f.messages(f.report("incomplete")); await f.settle();
  expect((await f.result()).status).toBe("incomplete");
});

test("a closed process is graded from its final transcript", async () => {
  const f = await fixture(); f.sessions([]); f.messages(f.report("completed")); await f.settle();
  expect((await f.result()).status).toBe("succeeded");
});

test("a vanished session with no transcript is interrupted", async () => {
  const f = await fixture(); f.sessions([]); f.readError(new TaskError("Transcript not found", 404)); await f.settle();
  expect((await f.result()).status).toBe("interrupted");
});

test("infrastructure errors override reported success, while transient reads remain active", async () => {
  const f = await fixture(); f.messages(f.report("completed"));
  f.sessions([{ sessionId: "session", status: "blocked", statusDetail: "Credits exhausted" }]); await f.settle();
  expect((await f.result()).status).toBe("failed"); expect((await f.result()).error).toBe("Credits exhausted");
  const apiError = await fixture(); apiError.messages([{ ...apiError.report("completed")[0], apiError: true }]); await apiError.settle();
  expect((await apiError.result()).status).toBe("failed");
  const transient = await fixture(); transient.readError(Error("temporary read error")); await transient.settle();
  expect((await transient.result()).status).toBe("running");
});

test("the runtime accepts only the latest assistant response, ignoring tool and user text", async () => {
  for (const role of ["user", "tool"]) {
    const f = await fixture(); f.messages([{ ...f.report("completed")[0], role, kind: role === "tool" ? "tool_result" : "text" }]);
    await f.settle(); expect((await f.result()).status).not.toBe("succeeded");
  }
  const f = await fixture(); f.messages([...f.report("completed"), { role: "assistant", kind: "text", text: "Actually, verification failed." }]); await f.settle();
  expect((await f.result()).status).toBe("incomplete");
});

test("every execution launch supplies a separate policy with this run's ID", async () => {
  for (const agent of ["claude", "codex"] as const) {
    const f = await fixture(agent);
    await f.store.record(f.run.id, { status: "incomplete" });
    const run = await f.runtime.runNow(f.task.id);
    for (let i = 0; i < 20 && !f.calls.some(([path]) => path === "/api/sessions/new"); i++) await Bun.sleep(5);
    const sent = f.calls.find(([path]) => path === "/api/sessions/new")![1];
    expect(sent.systemPrompt).toContain(run.id); expect(sent.systemPrompt).toContain("saved instructions");
    expect(sent.prompt).toContain(f.task.prompt); expect(sent.cwd).toBe(f.task.cwd); expect(sent.agent).toBe(agent);
    // Wait for the asynchronous launch transaction before fixture cleanup.
    for (let i = 0; i < 20 && (await f.store.read()).runs.at(-1)!.status === "starting"; i++) await Bun.sleep(5);
  }
});

test("a model or effort respawn recovers the exact run policy from durable history", async () => {
  const f = await fixture();
  const policy = await taskRunSystemPrompt(new TaskStore(f.store.path), "session");
  expect(policy).toContain(f.run.id);
  expect(policy).toContain("saved instructions");
  expect(await taskRunSystemPrompt(f.store, "ordinary-session")).toBeUndefined();
  // A later edit of the saved task cannot replace this run's identity.
  await f.store.update(f.task.id, { prompt: "Different instructions for a future run." });
  expect(await taskRunSystemPrompt(f.store, "session")).toBe(policy);
});
