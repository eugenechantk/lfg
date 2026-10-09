import { join } from "node:path";
import { TaskError, TaskScheduler, TaskStore, activeRun, type TaskInput, type TaskRun, type RunSnapshot } from "./scheduled-tasks.ts";

export type TaskApiCall = <T = any>(path: string, body?: unknown) => Promise<T>;
export function taskRuntime(store: TaskStore, call: TaskApiCall) {
  return new TaskScheduler(store, {
    launch: async (task, run) => {
      const result = await call("/api/sessions/new", { cwd: task.cwd, agent: task.agent, model: task.model,
        prompt: `Scheduled task: ${task.name}\nRun ID: ${run.id}\nScheduled for: ${new Date(run.scheduledFor).toISOString()}\n\nCarry out these saved instructions. This is one execution; do not create another schedule. Follow the project's existing permissions and report the outcome.\n\n${task.prompt}` });
      return result;
    },
    inspect: async (run): Promise<RunSnapshot> => {
      const { sessions } = await call("/api/sessions");
      const session = sessions?.find((s: any) => s.sessionId === run.sessionId);
      if (!session) return { state: "missing" };
      if (session.prompt) return { state: "needs_input" };
      if (session.status === "blocked") return { state: "failed", error: session.statusDetail ?? "The agent reported an error." };
      if (session.busy) return { state: "working" };
      const { messages } = await call(`/api/sessions/${run.sessionId}/messages?limit=20`);
      const meaningful = (messages ?? []).filter((m: any) => (m.role === "user" || m.role === "assistant") && m.kind === "text");
      const last = meaningful.at(-1);
      if (last?.apiError) return { state: "failed", error: last.text };
      return { state: "idle", ...(last?.role === "assistant" && last.text ? { summary: last.text } : {}) };
    },
  });
}

export function taskAuthoringPrompt(options: { prompt: string; cwd: string; agent: string; timezone: string; port: number; root: string }) {
  const tool = `${JSON.stringify(process.execPath)} ${JSON.stringify(join(options.root, "scripts/lfg-task-tool.ts"))}`;
  return `Help the user create an LFG scheduled task through a short conversation. Do not execute the proposed task now. This is task configuration, not project development: do not edit project files, create workflow logs, pull, commit, or push. Only use the task API and any read-only checks needed to clarify the schedule.
Current time: ${new Date().toISOString()}. Default timezone: ${options.timezone}. This host's default directory: ${options.cwd}. Execution agent: ${options.agent}.
Clarify only missing details about the work, timing, repository, or agent. Distinguish one-time (including relative delays), repeating intervals, and cron. Use ordinary conversational questions, not interactive question tools, so this chat can answer in text.
Once the user has supplied or confirmed the details, save through the scheduled task tool. Never claim a schedule exists before the tool succeeds. Summarize the exact local time, timezone, host directory, and recurrence. Each run will be a separate LFG session. The host must be awake; missed runs coalesce into one catch-up run.
Use the local CLI below to save on the exact host selected by the user. Do not use a remote MCP connection unless its host matches this host:
LFG_TASK_BASE=http://127.0.0.1:${options.port} ${tool} create <<'LFG_TASK_JSON'
{"name":"Task name","prompt":"Instructions for each execution","cwd":${JSON.stringify(options.cwd)},"agent":${JSON.stringify(options.agent)},"schedule":{"kind":"once","at":"ISO timestamp with offset","timezone":${JSON.stringify(options.timezone)}}}
LFG_TASK_JSON
For intervals use {"kind":"interval","everyMinutes":60,"timezone":"Asia/Hong_Kong"}; for cron use {"kind":"cron","expression":"0 9 * * 1-5","timezone":"Asia/Hong_Kong"}. The CLI also supports list, update TASK_ID (JSON on stdin), and runs TASK_ID. Validate all tool results. Do not create OS cron jobs or provider-native schedules.
The user's request follows:
${options.prompt}`;
}

export function scheduledTaskRoutes(store: TaskStore, scheduler: TaskScheduler, call: TaskApiCall, context: { root: string; port: number; defaultCwd: string }) {
  return async (req: Request): Promise<Response | null> => {
    const url = new URL(req.url); const path = url.pathname; const base = "/api/scheduled-tasks";
    if (!path.startsWith(base)) return null;
    const reply = (data: unknown, status = 200) => Response.json(data, { status });
    try {
      if (path === `${base}/chat` && req.method === "POST") {
        const body = await req.json() as any;
        if (typeof body.prompt !== "string" || !body.prompt.trim()) throw new TaskError("Describe the task you want to schedule.");
        const agent = body.agent === "codex" ? "codex" : "claude";
        const cwd = body.cwd || context.defaultCwd;
        const prompt = taskAuthoringPrompt({ prompt: body.prompt, cwd, agent, timezone: body.timezone || "Asia/Hong_Kong", ...context });
        return reply(await call("/api/sessions/new", { cwd, agent, model: body.model || undefined, prompt }));
      }
      if (path === base) {
        if (req.method === "GET") {
          const s = await store.read();
          const byTask = new Map<string, typeof s.runs>();
          for (const run of s.runs) {
            const runs = byTask.get(run.taskId) ?? [];
            runs.push(run); byTask.set(run.taskId, runs);
          }
          return reply({ tasks: s.tasks.map(t => {
            const runs = byTask.get(t.id) ?? [];
            return { ...t, currentRun: runs.find(activeRun), lastRun: runs.at(-1),
              recentRuns: runs.slice(-3).reverse(), runCount: runs.length };
          }), timezone: process.env.LFG_SCHED_TZ ?? "Asia/Hong_Kong" });
        }
        if (req.method === "POST") return reply({ task: await store.save(await req.json() as TaskInput) }, 201);
      }
      const match = path.match(/^\/api\/scheduled-tasks\/([0-9a-f-]{36})(?:\/(runs|run|cancel))?$/);
      if (!match) return reply({ error: "Unknown scheduled task endpoint." }, 404);
      const [, id, action] = match;
      if (action === "run" && req.method === "POST") return reply({ run: await scheduler.runNow(id!) }, 202);
      if (action === "cancel" && req.method === "POST") return reply({ task: await store.cancel(id!) });
      if (!action && req.method === "POST") return reply({ task: await store.update(id!, await req.json() as Partial<TaskInput>) });
      const s = await store.read(); const task = s.tasks.find(t => t.id === id);
      if (!task) return reply({ error: "Task not found." }, 404);
      if (action === "runs" && req.method === "GET") {
        const offset = Math.max(0, Number(url.searchParams.get("offset")) || 0);
        const all = s.runs.filter(r => r.taskId === id).reverse();
        return reply({ runs: all.slice(offset, offset + 50), total: all.length });
      }
      if (!action && req.method === "GET") return reply({ task });
      return reply({ error: "Method not allowed." }, 405);
    } catch (e) { return reply({ error: (e as Error).message }, e instanceof TaskError ? e.status : e instanceof SyntaxError ? 400 : 500); }
  };
}
