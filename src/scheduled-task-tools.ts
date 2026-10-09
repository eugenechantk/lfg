import { text, type McpTool } from "./mcp-server.ts";

type Api = { get<T>(path: string): Promise<T>; post<T>(path: string, body?: unknown): Promise<T> };
export function scheduledTaskTools(api: Api): McpTool[] {
  const schedule = { type: "object", properties: {
    kind: { type: "string", enum: ["once", "interval", "cron"] },
    timezone: { type: "string", description: "IANA timezone, such as Asia/Hong_Kong." },
    at: { type: "string", description: "One-time ISO 8601 timestamp including Z or an explicit offset. Convert relative delays to an exact future time." },
    everyMinutes: { type: "integer", minimum: 1 },
    expression: { type: "string", description: "Five-field cron expression." },
  }, required: ["kind", "timezone"] };
  const properties = { name: { type: "string" }, prompt: { type: "string", description: "Self-contained instructions for each execution." }, cwd: { type: "string", description: "Absolute directory on this host." }, agent: { type: "string", enum: ["claude", "codex"] }, model: { type: ["string", "null"], description: "Optional model override. Set null to restore the default model." }, enabled: { type: "boolean" }, schedule, sourceSessionId: { type: "string" } };
  const idProps = { task_id: { type: "string", description: "Task UUID returned by list_scheduled_tasks." } };
  const id = (args: Record<string, unknown>) => { if (typeof args.task_id !== "string" || !/^[0-9a-f-]{36}$/.test(args.task_id)) throw Error("A valid task_id is required."); return args.task_id; };
  const result = (value: unknown) => text(JSON.stringify(value, null, 2));
  return [
    { name: "list_scheduled_tasks", description: "List this host's one-time tasks, recurring intervals, and cron jobs, with next run and last result.", inputSchema: { type: "object", properties: {} }, annotations: { readOnlyHint: true, openWorldHint: false }, run: async () => result(await api.get("/api/scheduled-tasks")) },
    { name: "create_scheduled_task", description: "Save a user-requested task on this host. Supports one-time or recurring execution with Claude or Codex. Clarify ambiguous times and timezone first. Returns the saved task and next run; does not run it immediately.", inputSchema: { type: "object", properties, required: ["name", "prompt", "cwd", "agent", "schedule"] }, annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }, run: async args => result(await api.post("/api/scheduled-tasks", args)) },
    { name: "update_scheduled_task", description: "Edit a task or pause/resume it with enabled=false/true. Supply only fields to change. History is retained.", inputSchema: { type: "object", properties: { ...idProps, ...properties }, required: ["task_id"] }, annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }, run: async args => { const { task_id, ...patch } = args; return result(await api.post(`/api/scheduled-tasks/${id(args)}`, patch)); } },
    { name: "scheduled_task_runs", description: "Read a task's previous runs, including status, errors, result summaries, and session IDs for opening transcripts. Paginate with offset.", inputSchema: { type: "object", properties: { ...idProps, offset: { type: "integer", minimum: 0 } }, required: ["task_id"] }, annotations: { readOnlyHint: true, openWorldHint: false }, run: async args => result(await api.get(`/api/scheduled-tasks/${id(args)}/runs?offset=${Math.max(0, Number(args.offset) || 0)}`)) },
    { name: "run_scheduled_task", description: "Run a saved task now when the user requests it. Creates a normal session and a history entry. Refuses overlapping runs.", inputSchema: { type: "object", properties: idProps, required: ["task_id"] }, annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }, run: async args => result(await api.post(`/api/scheduled-tasks/${id(args)}/run`)) },
    { name: "cancel_scheduled_task", description: "Cancel future executions of a user-selected task. Keeps previous runs and does not stop an already-running session.", inputSchema: { type: "object", properties: idProps, required: ["task_id"] }, annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }, run: async args => result(await api.post(`/api/scheduled-tasks/${id(args)}/cancel`)) },
  ];
}
