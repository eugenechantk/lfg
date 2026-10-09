import { Cron } from "croner";
import { mkdir, readFile, rename, writeFile, stat } from "node:fs/promises";
import { dirname, isAbsolute } from "node:path";
import { randomUUID } from "node:crypto";

export type TaskSchedule = { kind: "once" | "interval" | "cron"; timezone: string; at?: string; everyMinutes?: number; expression?: string };
export type TaskInput = { name: string; prompt: string; cwd: string; agent: "claude" | "codex"; model?: string | null; schedule: TaskSchedule; enabled?: boolean; sourceSessionId?: string };
export type ScheduledTask = TaskInput & { id: string; enabled: boolean; createdAt: number; updatedAt: number; nextRunAt: number | null; lastRunAt?: number; cancelledAt?: number };
export type TaskRun = { id: string; taskId: string; taskName: string; agent: string; trigger: "scheduled" | "manual"; scheduledFor: number; startedAt: number; finishedAt?: number; status: "starting" | "running" | "needs_input" | "succeeded" | "failed" | "interrupted"; sessionId?: string; tmuxName?: string; summary?: string; error?: string };
type State = { version: 1; tasks: ScheduledTask[]; runs: TaskRun[] };
export const activeRun = (r: TaskRun) => ["starting", "running", "needs_input"].includes(r.status);
export class TaskError extends Error { constructor(message: string, readonly status = 400) { super(message); } }

function cron(schedule: TaskSchedule) {
  const expression = schedule.expression?.trim() ?? "";
  if (expression.split(/\s+/).length !== 5 || /\/0(?:\D|$)/.test(expression)) throw new TaskError("Use a five-field cron expression with positive steps.");
  try { return new Cron(expression, { timezone: schedule.timezone, paused: true }); }
  catch { throw new TaskError("The cron expression is invalid."); }
}

export function nextOccurrence(s: TaskSchedule, after: number): number | null {
  if (s.kind === "once") return Date.parse(s.at!);
  if (s.kind === "interval") return after + s.everyMinutes! * 60_000;
  return cron(s).nextRun(new Date(after))?.getTime() ?? null;
}

function sameSchedule(a: TaskSchedule, b: TaskSchedule): boolean {
  if (a.kind !== b.kind || a.timezone !== b.timezone) return false;
  if (a.kind === "once") return Date.parse(a.at!) === Date.parse(b.at!);
  if (a.kind === "interval") return a.everyMinutes === b.everyMinutes;
  const normalized = (value?: string) => typeof value === "string" ? value.trim().replace(/\s+/g, " ").toUpperCase() : "";
  return normalized(a.expression) === normalized(b.expression);
}

export function validateTask(input: TaskInput, now: number, allowPastOnce = false): TaskInput {
  if (!input || typeof input !== "object") throw new TaskError("Task details are required.");
  for (const key of ["name", "prompt", "cwd"] as const) {
    if (typeof input[key] !== "string" || !input[key].trim()) throw new TaskError(`${key} is required.`);
  }
  if (input.name.length > 160 || input.prompt.length > 50_000) throw new TaskError("Task name or instructions are too long.");
  if (!isAbsolute(input.cwd)) throw new TaskError("Choose an absolute directory on this host.");
  if (!["claude", "codex"].includes(input.agent)) throw new TaskError("Choose Claude or Codex.");
  if (input.model != null && (typeof input.model !== "string" || !/^[a-zA-Z0-9._:/-]{1,160}$/.test(input.model))) throw new TaskError("Invalid model name.");
  if (input.enabled != null && typeof input.enabled !== "boolean") throw new TaskError("enabled must be true or false.");
  const s = input.schedule;
  if (!s || !["once", "interval", "cron"].includes(s.kind)) throw new TaskError("Choose a one-time, interval, or cron schedule.");
  try { if (!s.timezone) throw Error(); new Intl.DateTimeFormat("en", { timeZone: s.timezone }).format(); }
  catch { throw new TaskError("Choose a valid timezone, such as Asia/Hong_Kong."); }
  if (s.kind === "once") {
    if (typeof s.at !== "string" || !/(Z|[+-]\d{2}:\d{2})$/i.test(s.at) || !Number.isFinite(Date.parse(s.at))) throw new TaskError("One-time schedules need an ISO date with a timezone offset.");
    if (!allowPastOnce && Date.parse(s.at) <= now) throw new TaskError("Choose a time in the future.");
  }
  if (s.kind === "interval" && (!Number.isInteger(s.everyMinutes) || s.everyMinutes! < 1 || s.everyMinutes! > 525600)) throw new TaskError("The interval must be between 1 minute and 365 days.");
  if (s.kind === "cron" && nextOccurrence(s, now) === null) throw new TaskError("This cron schedule has no future occurrence.");
  return { name: input.name.trim(), prompt: input.prompt.trim(), cwd: input.cwd.trim(), agent: input.agent, schedule: { ...s }, enabled: input.enabled ?? true,
    ...(input.model ? { model: input.model } : {}), ...(typeof input.sourceSessionId === "string" ? { sourceSessionId: input.sourceSessionId } : {}) };
}

/** The host owns all mutations. Serial transactions + atomic rename prevent lost claims. */
export class TaskStore {
  private queue: Promise<unknown> = Promise.resolve();
  constructor(readonly path: string) {}
  private async load(): Promise<State> {
    try {
      const value = JSON.parse(await readFile(this.path, "utf8"));
      if (value.version !== 1 || !Array.isArray(value.tasks) || !Array.isArray(value.runs)) throw Error("Invalid scheduled task store");
      return value;
    } catch (e) { if ((e as NodeJS.ErrnoException).code === "ENOENT") return { version: 1, tasks: [], runs: [] }; throw e; }
  }
  async read(): Promise<State> { await this.queue; return this.load(); }
  private transaction<T>(fn: (s: State) => T | Promise<T>): Promise<T> {
    const work = this.queue.then(async () => {
      const s = await this.load(); const result = await fn(s);
      await mkdir(dirname(this.path), { recursive: true });
      const temp = `${this.path}.${randomUUID()}.tmp`;
      await writeFile(temp, JSON.stringify(s), { mode: 0o600 }); await rename(temp, this.path);
      return result;
    });
    this.queue = work.catch(() => {}); return work;
  }
  async save(input: TaskInput, now = Date.now()): Promise<ScheduledTask> {
    const clean = validateTask(input, now);
    if (!(await stat(clean.cwd).catch(() => null))?.isDirectory()) throw new TaskError("That directory does not exist on this host.");
    return this.transaction(s => {
      if (s.tasks.filter(t => !t.cancelledAt).length >= 1000) throw new TaskError("This host already has 1,000 tasks.");
      const task: ScheduledTask = { ...clean, id: randomUUID(), enabled: clean.enabled!, createdAt: now, updatedAt: now, nextRunAt: nextOccurrence(clean.schedule, now) };
      s.tasks.push(task); return task;
    });
  }
  async update(id: string, patch: Partial<TaskInput>, now = Date.now()): Promise<ScheduledTask> {
    return this.transaction(async s => {
      const t = s.tasks.find(t => t.id === id); if (!t) throw new TaskError("Task not found.", 404);
      if (t.cancelledAt) throw new TaskError("This task has been cancelled.", 409);
      const changesSchedule = patch.schedule != null && !sameSchedule(patch.schedule, t.schedule);
      const resuming = patch.enabled === true && !t.enabled;
      const clean = validateTask({ ...t, ...patch }, now, !changesSchedule && !resuming);
      if (!(await stat(clean.cwd).catch(() => null))?.isDirectory()) throw new TaskError("That directory does not exist on this host.");
      Object.assign(t, clean, { updatedAt: now });
      if (clean.model == null) delete t.model;
      if (changesSchedule || resuming) t.nextRunAt = nextOccurrence(t.schedule, now);
      return t;
    });
  }
  async cancel(id: string, now = Date.now()): Promise<ScheduledTask> {
    return this.transaction(s => {
      const t = s.tasks.find(t => t.id === id); if (!t) throw new TaskError("Task not found.", 404);
      t.cancelledAt = now; t.enabled = false; t.nextRunAt = null; t.updatedAt = now; return t;
    });
  }
  async claim(id: string, now = Date.now(), manual = false): Promise<TaskRun | null> {
    return this.transaction(s => {
      const t = s.tasks.find(t => t.id === id);
      if (!t || t.cancelledAt || s.runs.some(r => r.taskId === id && activeRun(r))) return null;
      if (!manual && (!t.enabled || t.nextRunAt == null || t.nextRunAt > now)) return null;
      const run: TaskRun = { id: randomUUID(), taskId: id, taskName: t.name, agent: t.agent, trigger: manual ? "manual" : "scheduled", scheduledFor: manual ? now : t.nextRunAt!, startedAt: now, status: "starting" };
      s.runs.push(run); t.lastRunAt = now;
      if (t.schedule.kind === "once") { t.enabled = false; t.nextRunAt = null; }
      else if (!manual) t.nextRunAt = nextOccurrence(t.schedule, now);
      return run;
    });
  }
  async record(id: string, patch: Partial<TaskRun>): Promise<void> {
    await this.transaction(s => { const r = s.runs.find(r => r.id === id); if (r) Object.assign(r, patch, { id: r.id, taskId: r.taskId }); });
  }
}

export type RunSnapshot = { state: "working" | "idle" | "needs_input" | "failed" | "missing"; summary?: string; error?: string };
export type TaskExecutor = { launch(task: ScheduledTask, run: TaskRun): Promise<{ sessionId: string; tmuxName?: string }>; inspect(run: TaskRun): Promise<RunSnapshot> };
export class TaskScheduler {
  private ticking = false;
  private launching = new Set<string>();
  private idleSince = new Map<string, number>();
  constructor(readonly store: TaskStore, private executor: TaskExecutor, private now = () => Date.now()) {}
  async recover() {
    for (const r of (await this.store.read()).runs) if (r.status === "starting" && !r.sessionId && !this.launching.has(r.id)) {
      await this.store.record(r.id, { status: "interrupted", finishedAt: this.now(), error: "The host restarted during launch. Check sessions before running again." });
    }
  }
  async runNow(id: string): Promise<TaskRun> {
    const run = await this.store.claim(id, this.now(), true);
    if (!run) throw new TaskError("This task is cancelled, missing, or already running.", 409);
    void this.launch(run); return run;
  }
  private async launch(run: TaskRun) {
    this.launching.add(run.id);
    try {
      const t = (await this.store.read()).tasks.find(t => t.id === run.taskId)!;
      const result = await this.executor.launch(t, run);
      if (!result.sessionId) throw Error("The agent started without a session ID. Check sessions before retrying.");
      await this.store.record(run.id, { ...result, status: "running" });
    } catch (e) { await this.store.record(run.id, { status: "failed", error: String((e as Error).message ?? e), finishedAt: this.now() }); }
    finally { this.launching.delete(run.id); }
  }
  async tick() {
    if (this.ticking) return;
    this.ticking = true;
    try {
      const state = await this.store.read();
      for (const r of state.runs.filter(activeRun)) {
        if (!r.sessionId || this.launching.has(r.id)) continue;
        // A transient transcript/API failure must not block other due tasks.
        // Keep this run active and retry its inspection on the next tick.
        let snap: RunSnapshot;
        try { snap = await this.executor.inspect(r); }
        catch (error) { this.idleSince.delete(r.id); console.warn(`[tasks] Could not inspect run ${r.id}: ${error}`); continue; }
        const now = this.now();
        if (snap.state === "needs_input") { this.idleSince.delete(r.id); await this.store.record(r.id, { status: "needs_input" }); }
        else if (snap.state === "failed" || snap.state === "missing") {
          await this.store.record(r.id, { status: snap.state === "failed" ? "failed" : "interrupted", finishedAt: now, error: snap.error ?? "The session is no longer running. Open its conversation to inspect the result." });
        } else if (snap.state === "idle" && snap.summary) {
          const since = this.idleSince.get(r.id);
          if (since == null) this.idleSince.set(r.id, now);
          else if (now - since >= 5000) { await this.store.record(r.id, { status: "succeeded", finishedAt: now, summary: snap.summary.slice(0, 8000) }); this.idleSince.delete(r.id); }
        } else { this.idleSince.delete(r.id); if (r.status === "needs_input") await this.store.record(r.id, { status: "running" }); }
      }
      // Bound launches per tick. Recurring jobs coalesce missed occurrences.
      let launched = 0;
      for (const t of state.tasks) {
        if (!t.enabled || t.cancelledAt || t.nextRunAt == null || t.nextRunAt > this.now()) continue;
        const run = await this.store.claim(t.id, this.now());
        if (run) { await this.launch(run); if (++launched >= 2) break; }
      }
    } finally { this.ticking = false; }
  }
  start(log: (message: string) => void = console.log) {
    let stopped = false; let timer: ReturnType<typeof setTimeout>;
    const loop = async () => { try { await this.tick(); } catch (e) { log(`[tasks] ${e}`); } if (!stopped) timer = setTimeout(loop, 60_000); };
    void this.recover().then(() => { if (!stopped) timer = setTimeout(loop, 2000); }).catch(e => log(`[tasks] recovery failed: ${e}`));
    return () => { stopped = true; clearTimeout(timer); };
  }
}
