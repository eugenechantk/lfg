// A stand-in lfg host for checking the Tasks screens against the A2 boards.
// It serves the REAL task routes (src/scheduled-task-api.ts) over a throwaway
// store seeded with the board's tasks, answers /api/sessions so the app treats
// the host as connected, and never launches an agent.
//   PORT=8932 bun run .claude/tasks-a2/fixture-host.ts
import { mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { TaskStore, TaskScheduler, nextOccurrence, type ScheduledTask, type TaskRun } from "../../src/scheduled-tasks.ts";
import { scheduledTaskRoutes } from "../../src/scheduled-task-api.ts";

const PORT = Number(process.env.PORT ?? 8932);
const CWD = process.env.TASK_CWD ?? join(import.meta.dir, "../..");
const TZ = "Asia/Hong_Kong";
const MIN = 60_000, HOUR = 60 * MIN, DAY = 24 * HOUR;
const now = Date.now();
// Midnight today in Hong Kong (UTC+8, no DST).
const today = Math.floor((now + 8 * HOUR) / DAY) * DAY - 8 * HOUR;
const at = (dayOffset: number, h: number, m = 0) => today + dayOffset * DAY + h * HOUR + m * MIN;
const iso = (t: number) => new Date(t).toISOString().replace(".000Z", "Z");
let n = 0;
const id = () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`;

const tasks: ScheduledTask[] = [];
const runs: TaskRun[] = [];
function task(fields: Partial<ScheduledTask> & Pick<ScheduledTask, "name" | "schedule">, history: Partial<TaskRun>[] = []) {
  const t: ScheduledTask = { id: id(), prompt: "Review yesterday’s changes in LFG. Summarize the important fixes, flag anything that looks like a regression, and suggest the next most useful task. Keep it under 200 words and link each commit you mention.",
    cwd: CWD, agent: "claude", enabled: true, createdAt: at(-20, 9), updatedAt: at(-20, 9), nextRunAt: null, scheduledRunCount: 0, ...fields } as ScheduledTask;
  if (t.nextRunAt === null && t.enabled && !t.cancelledAt) t.nextRunAt = nextOccurrence(t.schedule, now, t.scheduledRunCount ?? 0);
  tasks.push(t);
  for (const h of history) {
    const r = { id: id(), taskId: t.id, taskName: t.name, agent: t.agent, trigger: "scheduled", scheduledFor: h.startedAt!, status: "succeeded", ...h } as TaskRun;
    runs.push(r);
  }
  t.lastRunAt = runs.filter(r => r.taskId === t.id).at(-1)?.startedAt;
  return t;
}

const cron = (expression: string, extra = {}) => ({ kind: "cron" as const, expression, timezone: TZ, ...extra });

// Needs input
task({ name: "Release verification", agent: "claude", enabled: false, prompt: "Install today’s TestFlight build on the simulator, walk the fork, send and task flows, and report anything broken with screenshots.",
  schedule: { kind: "once", at: iso(at(0, 9, 58)), timezone: TZ } },
  [{ startedAt: at(0, 9, 58), scheduledFor: at(0, 9, 58), status: "needs_input", sessionId: "fx-question", needsInputAt: at(0, 10) }]);
task({ name: "Nightly dependency audit", model: "opus", schedule: cron("0 2 * * *"), scheduledRunCount: 31,
  prompt: "Audit dependencies in every repo under ~/dev/personal. List outdated and vulnerable packages, and open a PR for safe patch updates." },
  [{ startedAt: at(-2, 2), finishedAt: at(-2, 2, 9), summary: "Audited 214 packages; 2 outdated, none vulnerable", sessionId: "fx-a1" },
   { startedAt: at(-1, 2), finishedAt: at(-1, 2, 8), summary: "Audited 214 packages; 1 outdated, none vulnerable", sessionId: "fx-a2" },
   { startedAt: at(0, 2), finishedAt: at(0, 2), status: "failed", error: "Opus 5.5 was unavailable, so no session started." }]);
// Active
task({ name: "Readwise sync check", agent: "codex", schedule: cron("0 * * * *") },
  [{ startedAt: now - 72 * MIN, finishedAt: now - 70 * MIN, summary: "Synced 12 highlights", sessionId: "fx-r1" },
   { startedAt: now - 12 * MIN, status: "running", sessionId: "fx-running" }]);
task({ name: "Morning standup notes", schedule: { kind: "repeat", at: iso(at(-2, 8, 30)), everyMinutes: 1440, occurrences: 5, timezone: TZ }, scheduledRunCount: 3 },
  [0, 1, 2].map(d => ({ startedAt: at(-2 + d, 8, 30), finishedAt: at(-2 + d, 8, 34), summary: "Notes for 4 repos", sessionId: `fx-m${d}` })));
task({ name: "Daily repo review", schedule: cron("0 9 * * 1-5") },
  [{ startedAt: at(-3, 9), finishedAt: at(-3, 9, 5), status: "failed", error: "Model unavailable. No session started." },
   { startedAt: at(-1, 9), finishedAt: at(-1, 9, 5), summary: "Reviewed 9 commits; no regressions", sessionId: "fx-d1" },
   { startedAt: at(0, 9), finishedAt: at(0, 9, 6), summary: "Reviewed 14 commits, 1 regression", sessionId: "fx-d2" }]);
// Paused
task({ name: "Weekly app-review digest", enabled: false, pausedAt: at(-3, 11), schedule: cron("0 8 * * 1") },
  [{ startedAt: at(-10, 8), finishedAt: at(-10, 8, 4), summary: "14 new reviews, average 4.6", sessionId: "fx-w1" }]);
task({ name: "Dependency PR sweep", enabled: false, pausedAt: at(-9, 15), schedule: cron("0 17 * * 5") });
task({ name: "Tag release 1.3.2", enabled: false, pausedAt: at(-7, 10), schedule: { kind: "once", at: iso(at(-6, 9)), timezone: TZ } });
// Closed
task({ name: "GRDB schema check", enabled: false, schedule: { kind: "once", at: iso(at(-3, 10)), timezone: TZ } },
  [{ startedAt: at(-3, 10), finishedAt: at(-3, 10, 4), summary: "Schema matches; no migration needed", sessionId: "fx-g1" }]);
task({ name: "Sprint standup notes", enabled: false, schedule: { kind: "repeat", at: iso(at(-10, 9)), everyMinutes: 1440, occurrences: 5, timezone: TZ }, scheduledRunCount: 5 },
  [0, 1, 2, 3, 4].map(d => ({ startedAt: at(-10 + d, 9), finishedAt: at(-10 + d, 9, 3), summary: "Standup notes posted", sessionId: `fx-s${d}` })));
task({ name: "Competitor pricing scan", enabled: false, cancelledAt: at(-12, 18), schedule: cron("0 10 * * 2") },
  [{ startedAt: at(-20, 10), finishedAt: at(-20, 10, 7), summary: "No price changes", sessionId: "fx-c1" }]);
// FIXTURE_VARIANTS=1: one task per edit-form variant board, after the base tasks so their ids stay put.
if (process.env.FIXTURE_VARIANTS) {
  const rep = (everyMinutes: number, extra = {}) => ({ kind: "repeat" as const, at: iso(at(1, 9)), everyMinutes, timezone: TZ, ...extra });
  task({ name: "V once", schedule: { kind: "once", at: iso(at(1, 9)), timezone: TZ } });
  task({ name: "V 5min", schedule: cron("*/5 * * * *") });
  task({ name: "V 7min", schedule: { kind: "interval", at: iso(at(1, 9)), everyMinutes: 7, timezone: TZ } });
  task({ name: "V 5hours", schedule: { kind: "interval", at: iso(at(1, 9)), everyMinutes: 300, timezone: TZ } });
  task({ name: "V hourly", schedule: cron("30 * * * *") });
  task({ name: "V daily", schedule: cron("0 9 * * *") });
  task({ name: "V 3days", schedule: { kind: "interval", at: iso(at(1, 9)), everyMinutes: 4320, timezone: TZ } });
  task({ name: "V 3days after", schedule: rep(4320, { occurrences: 6 }) });
  task({ name: "V weekly", schedule: cron("0 9 * * 1,3") });
  task({ name: "V monthly", schedule: cron("0 9 16 * *") });
  task({ name: "V custom", schedule: cron("15 9 1-7 * 1") });
  task({ name: "V after n", schedule: cron("0 9 * * 1-5", { maxRuns: 10 }) });
  task({ name: "V on date", schedule: cron("0 9 * * 1-5", { endsAt: iso(at(77, 23, 59)) }) });
  // The runs boards (tA2d-runs-*): 23 past runs, the third newest failed, so both groups fold.
  task({ name: "V long history", schedule: cron("0 9 * * *") },
    Array.from({ length: 23 }, (_, i) => -22 + i).map(d => d === -2
      ? { startedAt: at(d, 9), finishedAt: at(d, 9), status: "failed" as const, error: "Model unavailable. No session started." }
      : { startedAt: at(d, 9), finishedAt: at(d, 9, 5), summary: `Reviewed ${5 + ((d + 30) % 9)} commits; no regressions`, sessionId: `fx-l${-d}` }));
}
for (const t of tasks) if (!t.enabled || t.cancelledAt) t.nextRunAt = t.cancelledAt ? null : (t.schedule.kind === "once" ? (Date.parse(t.schedule.at!) > now ? Date.parse(t.schedule.at!) : null) : t.nextRunAt ?? nextOccurrence(t.schedule, now));
for (const t of tasks) if (t.schedule.kind === "repeat" && t.scheduledRunCount === t.schedule.occurrences) t.nextRunAt = null;

const dir = await mkdtemp(join(tmpdir(), "lfg-task-fixture-"));
const storePath = join(dir, "scheduled-tasks.json");
await writeFile(storePath, JSON.stringify({ version: 1, tasks, runs }));
const store = new TaskStore(storePath);

const question = { question: "Which build should I verify?", context: "TestFlight has two builds from today. 1.3.1 has the fork fix. Testers are on 1.3.0.",
  options: [{ index: 1, label: "1.3.1 (205)", description: "Built last night · has the fork fix" }, { index: 2, label: "1.3.0 (202)", description: "What testers have now" }] };
const answered = new Set<string>();

// Edit chats: a scripted agent that replies and saves a change, like the chat board.
type ChatMessage = { id: string; role: "user" | "assistant"; kind: "text"; text: string; ts: number };
const chats = new Map<string, { taskId: string; messages: ChatMessage[] }>();
const say = (sid: string, role: ChatMessage["role"], text: string) =>
  chats.get(sid)!.messages.push({ id: `${sid}-${chats.get(sid)!.messages.length}`, role, kind: "text", text, ts: Date.now() });
function agentReplies(sid: string, request: string) {
  setTimeout(async () => {
    const chat = chats.get(sid); if (!chat) return;
    const r = request.toLowerCase();
    if (r.includes("monday") || r.includes(" 8") || r.includes("codex")) {
      const t = (await store.read()).tasks.find(t => t.id === chat.taskId)!;
      await store.update(chat.taskId, { schedule: { kind: "cron", expression: "0 8 * * 2-5", timezone: t.schedule.timezone },
        ...(r.includes("codex") ? { agent: "codex", model: "gpt-6-astra" } : {}) });
      say(sid, "assistant", r.includes("codex") ? "Done. Runs move to 8:00 AM, Tuesday to Friday, and Codex runs them with GPT-6 Astra."
        : "Done. Runs move to 8:00 AM, Tuesday to Friday.");
    } else if (r.includes("fail")) {
      say(sid, "assistant", "The last run failed because Opus 5.5 was unavailable. I switched the task to the default model so the next run can start.");
      await store.update(chat.taskId, { model: null });
    } else {
      say(sid, "assistant", "What would you like to change: the time, the days, the agent, or the instructions?");
    }
  }, 2500);
}
const sessions = () => [
  ...runs.filter(r => r.sessionId).map(r => ({ sessionId: r.sessionId, cwd: CWD, agent: r.agent, busy: r.sessionId === "fx-running",
    ...(r.sessionId === "fx-question" && !answered.has(r.sessionId) ? { prompt: question } : {}) })),
  ...[...chats.entries()].map(([sessionId, c]) => ({ sessionId, cwd: CWD, agent: "claude", title: "Change task", purpose: "task-edit", taskId: c.taskId })),
];
// The task routes' internal calls: list sessions, start an edit chat, send to it.
const call = async (path: string, body?: any) => {
  if (path === "/api/sessions") return { sessions: sessions() } as any;
  if (path === "/api/sessions/new") {
    const sid = crypto.randomUUID();
    chats.set(sid, { taskId: body?.taskId, messages: [] });
    console.log(`CHAT NEW ${sid} purpose=${body?.purpose} task=${body?.taskId}`);
    say(sid, "user", body?.prompt ?? "");
    agentReplies(sid, String(body?.prompt ?? "").split("The user's request follows:\n").pop()!);
    return { sessionId: sid } as any;
  }
  const send = path.match(/^\/api\/sessions\/([^/]+)\/send$/);
  if (send && chats.has(send[1]!)) {
    console.log(`CHAT SEND ${send[1]} ${JSON.stringify(body)}`);
    say(send[1]!, "user", body?.text ?? ""); agentReplies(send[1]!, body?.text ?? "");
    return { ok: true } as any;
  }
  return {} as any;
};
const scheduler = new TaskScheduler(store, {
  launch: async () => ({ sessionId: `fx-launch-${Date.now()}` }),
  inspect: async () => ({ state: "working" }),
});
const routes = scheduledTaskRoutes(store, scheduler, call, { root: CWD, port: PORT, defaultCwd: CWD });

Bun.serve({
  port: PORT, hostname: "127.0.0.1",
  async fetch(req) {
    const url = new URL(req.url);
    console.log(new Date().toISOString().slice(11, 19), req.method, url.pathname + url.search);
    const task = await routes(req);
    if (task) return task;
    if (url.pathname === "/api/sessions") return Response.json({ sessions: sessions() });
    if (url.pathname === "/api/ping") return Response.json({ ok: true, seq: 0, ts: Date.now() });
    const messages = url.pathname.match(/^\/api\/sessions\/([^/]+)\/messages$/);
    if (messages && chats.has(messages[1]!)) return Response.json({ id: messages[1], messages: chats.get(messages[1]!)!.messages });
    const chatSend = url.pathname.match(/^\/api\/sessions\/([^/]+)\/send$/);
    if (chatSend && req.method === "POST" && chats.has(chatSend[1]!)) return Response.json(await call(url.pathname, await req.json().catch(() => ({}))));
    // Answering the waiting run: log it, clear the question, and let the run carry on.
    const answer = url.pathname.match(/^\/api\/sessions\/([^/]+)\/(answer|send)$/);
    if (answer && req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      console.log(`ANSWER ${answer[1]} ${answer[2]} ${JSON.stringify(body)}`);
      answered.add(answer[1]!);
      const run = (await store.read()).runs.find(r => r.sessionId === answer[1]);
      // The real scheduler notices on its next tick; wait a little so the app shows the interim state.
      if (run) setTimeout(() => void store.record(run.id, { status: "running", needsInputAt: undefined }), 8000);
      return Response.json({ ok: true });
    }
    if (url.pathname === "/api/events") {
      // Heartbeats only (the real host's `: hb <head>` frames), so the app shows the host as connected.
      let timer: ReturnType<typeof setInterval>;
      return new Response(new ReadableStream({
        start(c) { const hb = () => { try { c.enqueue(": hb 0\n\n"); } catch { clearInterval(timer); } }; hb(); timer = setInterval(hb, 10_000); },
        cancel() { clearInterval(timer); },
      }), { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" } });
    }
    if (url.pathname === "/api/sessions/resumable") return Response.json({ sessions: [] });
    if (url.pathname === "/api/info") return Response.json({ hostId: "fixture-pro", hostname: "fixture", version: "fixture" });
    if (url.pathname === "/api/repos") return Response.json({ repos: [{ cwd: CWD, name: "lfg" }] });
    if (url.pathname === "/api/dirs") return Response.json({ root: CWD, inbox: CWD });
    return Response.json({ error: "fixture: not served" }, { status: 404 });
  },
});
console.log(`fixture host on http://127.0.0.1:${PORT} · store ${storePath} · ${tasks.length} tasks`);
