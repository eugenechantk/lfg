/** Isolated acceptance host. Uses production scheduling code; never starts an agent. */
import { appendFile, mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { TaskStore, TaskScheduler } from "../../src/scheduled-tasks.ts";
import { scheduledTaskRoutes } from "../../src/scheduled-task-api.ts";

const root = new URL("../evidence/automatic-task-retry/ui-fixture/", import.meta.url).pathname;
await mkdir(root, { recursive: true });
let store: TaskStore;
let runtime: TaskScheduler;
let routes: ReturnType<typeof scheduledTaskRoutes>;
async function seed() {
  store = new TaskStore(`${root}${randomUUID()}.json`);
  const now = Date.now(), start = now - 3600_000;
  for (const [name, count, paused] of [["Automatic retry demo", 3, false], ["Final occurrence retry", 1, false], ["Paused automatic retry", 3, true]] as const) {
    const task = await store.save({ name, prompt: "Complete this occurrence and verify the result.", cwd: process.cwd(), agent: "codex", schedule: { kind: "repeat", at: new Date(start).toISOString(), everyMinutes: 1440, occurrences: count, timezone: "Asia/Hong_Kong" } }, start - 60_000);
    const run = (await store.claim(task.id, start))!;
    await store.record(run.id, { status: "incomplete", finishedAt: now - 60_000, error: "The work is incomplete. Its occurrence is kept for the assigned retry." });
    if (paused) await store.update(task.id, { enabled: false });
  }
  runtime = new TaskScheduler(store, {
    launch: async (_task, run) => {
      await appendFile(`${root}launches.jsonl`, JSON.stringify({ at: Date.now(), run }) + "\n");
      return { sessionId: `fixture-${run.id}` };
    },
    inspect: async () => ({ state: "working" }),
  });
  routes = scheduledTaskRoutes(store, runtime, async () => ({ sessions: [] } as any), { root: process.cwd(), port: 18957, defaultCwd: process.cwd() });
}
await seed();
for (const port of [18957, 18958]) Bun.serve({ hostname: "127.0.0.1", port, idleTimeout: 0, async fetch(req) {
  const path = new URL(req.url).pathname;
  await appendFile(`${root}requests.jsonl`, JSON.stringify({ at: Date.now(), port, path, method: req.method, ...(req.method === "POST" ? { body: await req.clone().text() } : {}) }) + "\n");
  if (path === "/fixture/reset") { await seed(); return Response.json(await store.read()); }
  if (path === "/fixture/state") return Response.json(await store.read());
  if (path === "/fixture/tick") { await runtime.tick(); return Response.json(await store.read()); }
  if (path === "/api/events") return new Response(new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(": heartbeat\n\n")); } }), { headers: { "Content-Type": "text/event-stream" } });
  if (port === 18958 && path === "/api/scheduled-tasks") return Response.json({ tasks: [] });
  if (path.startsWith("/api/scheduled-tasks")) return (await routes(req)) ?? Response.json({});
  if (path === "/api/info") return Response.json({ hostId: `automatic-retry-${port}`, hostName: port === 18957 ? "Retry fixture" : "Empty fixture" });
  if (path === "/api/ping") return Response.json({ ok: true, seq: 0, ts: Date.now() });
  if (path.startsWith("/api/sessions")) return Response.json({ sessions: [], messages: [], total: 0, queue: [] });
  return Response.json({ ok: true, dirs: [], repos: [], users: [], requests: [], claude: [], codex: [] });
} });
console.log(JSON.stringify({ port: 18957, taskNames: (await store.read()).tasks.map(t => t.name) }));
