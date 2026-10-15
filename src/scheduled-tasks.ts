import { Cron } from "croner";
import { mkdir, readFile, rename, writeFile, stat } from "node:fs/promises";
import { dirname, isAbsolute } from "node:path";
import { randomUUID } from "node:crypto";

/** `at` anchors once/repeat, and optionally interval (an exact gap counted from `at`).
 * `maxRuns` (cron) and `endsAt` (cron, interval) end an otherwise open schedule. */
export type TaskSchedule = { kind: "once" | "interval" | "repeat" | "cron"; timezone: string; at?: string; everyMinutes?: number; occurrences?: number; expression?: string; maxRuns?: number; endsAt?: string };
export type TaskInput = { name: string; prompt: string; cwd: string; agent: "claude" | "codex"; model?: string | null; schedule: TaskSchedule; enabled?: boolean; sourceSessionId?: string };
/** `scheduledRunCount` counts scheduled (not manual) runs since the schedule last changed; cron `maxRuns` reads it.
 * `pausedAt` is set when the user switches a task off and cleared on resume. */
export type ScheduledTask = TaskInput & { id: string; enabled: boolean; createdAt: number; updatedAt: number; nextRunAt: number | null; lastRunAt?: number; cancelledAt?: number; pausedAt?: number; scheduledRunCount?: number; editSessionId?: string; editSessionIds?: string[] };
export type TaskRun = { id: string; taskId: string; taskName: string; agent: string; trigger: "scheduled" | "manual"; scheduledFor: number; startedAt: number; finishedAt?: number; status: "starting" | "running" | "needs_input" | "succeeded" | "failed" | "interrupted"; sessionId?: string; tmuxName?: string; summary?: string; error?: string; needsInputAt?: number };
type State = { version: 1; tasks: ScheduledTask[]; runs: TaskRun[] };
export const activeRun = (r: TaskRun) => ["starting", "running", "needs_input"].includes(r.status);
export class TaskError extends Error { constructor(message: string, readonly status = 400) { super(message); } }

function cron(schedule: TaskSchedule) {
  const expression = schedule.expression?.trim() ?? "";
  if (expression.split(/\s+/).length !== 5 || /\/0(?:\D|$)/.test(expression)) throw new TaskError("Use a five-field cron expression with positive steps.");
  try { return new Cron(expression, { timezone: schedule.timezone, paused: true }); }
  catch { throw new TaskError("The cron expression is invalid."); }
}

/** A schedule that stops on its own: a finite repeat, or cron/interval with an end. */
export const finiteSchedule = (s: TaskSchedule) => s.kind === "repeat" || s.maxRuns != null || s.endsAt != null;

/** `done` = scheduled runs already claimed under this schedule (for cron `maxRuns`). */
export function nextOccurrence(s: TaskSchedule, after: number, done = 0): number | null {
  if (s.maxRuns != null && done >= s.maxRuns) return null;
  let next: number | null;
  if (s.kind === "once") next = Date.parse(s.at!);
  else if (s.kind === "interval") {
    const step = s.everyMinutes! * 60_000;
    if (s.at == null) next = after + step;
    else {
      // An exact gap counted from `at`, so "every 3 days from Friday 9:00" keeps its clock time.
      const start = Date.parse(s.at);
      next = after < start ? start : start + (Math.floor((after - start) / step) + 1) * step;
    }
  } else if (s.kind === "repeat") {
    const start = Date.parse(s.at!), step = s.everyMinutes! * 60_000;
    const index = Math.max(0, Math.floor((after - start) / step) + 1);
    next = index < s.occurrences! ? start + index * step : null;
  } else next = cron(s).nextRun(new Date(after))?.getTime() ?? null;
  if (next != null && s.endsAt != null && next > Date.parse(s.endsAt)) return null;
  return next;
}

/** The next `n` occurrences after `after`, stopping early when the schedule ends. */
export function nextOccurrences(s: TaskSchedule, after: number, n: number, done = 0): number[] {
  const out: number[] = [];
  let cursor = after;
  while (out.length < n) {
    const next = nextOccurrence(s, cursor, done + out.length);
    if (next == null || (out.length && next <= out.at(-1)!)) break;
    out.push(next); cursor = next;
    if (s.kind === "once") break;
  }
  return out;
}

/** The final occurrence of a finite schedule, or null when it has no end or none remain. */
export function lastOccurrence(s: TaskSchedule, after: number, done = 0): number | null {
  if (s.kind === "once") { const at = Date.parse(s.at!); return at > after ? at : null; }
  if (s.kind === "repeat") { const start = Date.parse(s.at!); const last = start + (s.occurrences! - 1) * s.everyMinutes! * 60_000; return last > after ? last : null; }
  if (s.maxRuns != null) { const left = s.maxRuns - done; return left > 0 ? nextOccurrences(s, after, left, done).at(-1) ?? null : null; }
  if (s.endsAt == null) return null;
  const end = Date.parse(s.endsAt);
  if (s.kind === "interval") {
    const first = nextOccurrence(s, after, done); if (first == null) return null;
    const step = s.everyMinutes! * 60_000; return first + Math.floor((end - first) / step) * step;
  }
  // Cron with an end date: walk back from the end with croner's previous runs when available.
  const job = cron(s) as Cron & { previousRuns?: (n: number, d: Date) => Date[] };
  const prev = job.previousRuns?.(1, new Date(end + 1))?.[0]?.getTime();
  return prev != null && prev > after ? prev : (nextOccurrence(s, after, done) ?? null);
}

function sameSchedule(a: TaskSchedule, b: TaskSchedule): boolean {
  if (a.kind !== b.kind || a.timezone !== b.timezone) return false;
  if (a.kind === "once") return Date.parse(a.at!) === Date.parse(b.at!);
  const time = (v?: string) => v == null ? null : Date.parse(v);
  if (a.maxRuns !== b.maxRuns || time(a.endsAt) !== time(b.endsAt)) return false;
  if (a.kind === "interval") return a.everyMinutes === b.everyMinutes && time(a.at) === time(b.at);
  if (a.kind === "repeat") return Date.parse(a.at!) === Date.parse(b.at!) && a.everyMinutes === b.everyMinutes && a.occurrences === b.occurrences;
  const normalized = (value?: string) => typeof value === "string" ? value.trim().replace(/\s+/g, " ").toUpperCase() : "";
  return normalized(a.expression) === normalized(b.expression);
}

const isoWithOffset = (v: unknown): v is string => typeof v === "string" && /(Z|[+-]\d{2}:\d{2})$/i.test(v) && Number.isFinite(Date.parse(v));

/** Shared by save, update and the form's preview, so they can never disagree. */
export function validateSchedule(s: TaskSchedule, now: number, allowPast = false): TaskSchedule {
  if (!s || !["once", "interval", "repeat", "cron"].includes(s.kind)) throw new TaskError("Choose a one-time, interval, finite repeat, or cron schedule.");
  try { if (!s.timezone) throw Error(); new Intl.DateTimeFormat("en", { timeZone: s.timezone }).format(); }
  catch { throw new TaskError("Choose a valid timezone, such as Asia/Hong_Kong."); }
  if (s.kind === "once" || s.kind === "repeat") {
    if (!isoWithOffset(s.at)) throw new TaskError("The first start needs an ISO date with a timezone offset.");
    if (!allowPast && Date.parse(s.at) <= now) throw new TaskError("Choose a time in the future.");
  }
  if (s.kind === "interval" && s.at != null && !isoWithOffset(s.at)) throw new TaskError("The start needs an ISO date with a timezone offset.");
  if (s.kind === "cron" && s.at != null) throw new TaskError("A cron schedule takes its times from the expression.");
  if ((s.kind === "interval" || s.kind === "repeat") && (!Number.isInteger(s.everyMinutes) || s.everyMinutes! < 1 || s.everyMinutes! > 525600)) throw new TaskError("The interval must be between 1 minute and 365 days.");
  if (s.kind === "repeat" && (!Number.isInteger(s.occurrences) || s.occurrences! < 1 || s.occurrences! > 1000)) throw new TaskError("Choose 1 to 1,000 total occurrences, including the first.");
  if (s.kind !== "repeat" && s.occurrences != null) throw new TaskError("Use a finite repeat schedule to set an occurrence count.");
  if (s.kind === "repeat" && !Number.isFinite(new Date(Date.parse(s.at!) + (s.occurrences! - 1) * s.everyMinutes! * 60_000).getTime())) throw new TaskError("The repeat schedule ends outside the supported date range.");
  if (s.maxRuns != null && (s.kind !== "cron" || !Number.isInteger(s.maxRuns) || s.maxRuns < 1 || s.maxRuns > 1000)) throw new TaskError(s.kind === "cron" ? "Choose 1 to 1,000 runs." : "Use occurrences to limit a repeat; maxRuns is for cron schedules.");
  if (s.endsAt != null) {
    if (s.kind !== "cron" && s.kind !== "interval") throw new TaskError("Only cron and interval schedules take an end date.");
    if (!isoWithOffset(s.endsAt)) throw new TaskError("The end date needs an ISO date with a timezone offset.");
    if (s.maxRuns != null) throw new TaskError("Choose either a number of runs or an end date, not both.");
  }
  if (s.kind === "cron") cron(s);
  if (s.kind === "cron" && s.endsAt == null && nextOccurrence(s, now) === null) throw new TaskError("This cron schedule has no future occurrence.");
  if (s.endsAt != null && !allowPast && nextOccurrence(s, now) === null) throw new TaskError("This schedule ends before its next run. Choose a later end date.");
  const clean: TaskSchedule = { kind: s.kind, timezone: s.timezone };
  for (const key of ["at", "everyMinutes", "occurrences", "expression", "maxRuns", "endsAt"] as const) if (s[key] != null) (clean as any)[key] = s[key];
  return clean;
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
  const s = validateSchedule(input.schedule, now, allowPastOnce);
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
      const task: ScheduledTask = { ...clean, id: randomUUID(), enabled: clean.enabled!, createdAt: now, updatedAt: now, nextRunAt: nextOccurrence(clean.schedule, now), scheduledRunCount: 0, ...(clean.enabled ? {} : { pausedAt: now }) };
      s.tasks.push(task); return task;
    });
  }
  async update(id: string, patch: Partial<TaskInput>, now = Date.now()): Promise<ScheduledTask> {
    return this.transaction(async s => {
      const t = s.tasks.find(t => t.id === id); if (!t) throw new TaskError("Task not found.", 404);
      if (t.cancelledAt) throw new TaskError("This task has been cancelled.", 409);
      const changesSchedule = patch.schedule != null && !sameSchedule(patch.schedule, t.schedule);
      const resuming = patch.enabled === true && !t.enabled;
      const pausing = patch.enabled === false && t.enabled;
      if (resuming && !changesSchedule && t.schedule.kind === "repeat" && t.nextRunAt == null) throw new TaskError("This repeat schedule has finished. Choose a future first start for a new series.", 409);
      const requested = patch.schedule ?? t.schedule;
      const sameRepeatStart = t.schedule.kind === "repeat" && requested.kind === "repeat" && Date.parse(t.schedule.at!) === Date.parse(requested.at!);
      const clean = validateTask({ ...t, ...patch }, now, (!changesSchedule && !resuming) || sameRepeatStart);
      const done = changesSchedule ? 0 : (t.scheduledRunCount ?? 0);
      const next = changesSchedule || resuming ? nextOccurrence(clean.schedule, now, done) : t.nextRunAt;
      if (clean.schedule.kind === "repeat" && clean.enabled && next == null) throw new TaskError("This repeat schedule has finished. Choose a future first start for a new series.");
      if (finiteSchedule(clean.schedule) && clean.enabled && next == null) throw new TaskError("This schedule has finished. Choose a later end or more runs to continue.", 409);
      if (!(await stat(clean.cwd).catch(() => null))?.isDirectory()) throw new TaskError("That directory does not exist on this host.");
      Object.assign(t, clean, { updatedAt: now });
      if (clean.model == null) delete t.model;
      if (changesSchedule || resuming) t.nextRunAt = next;
      if (changesSchedule) t.scheduledRunCount = 0;
      if (pausing) t.pausedAt = now;
      if (t.enabled) delete t.pausedAt;
      return t;
    });
  }
  /** Remembers the task's edit chat so the next request reuses it. */
  async setEditSession(id: string, sessionId: string): Promise<void> {
    // The id history outlives the chat: once a chat closes, its listing has no managed record left,
    // so clients find it here to keep it out of Sessions.
    await this.transaction(s => {
      const t = s.tasks.find(t => t.id === id); if (!t) return;
      t.editSessionId = sessionId;
      t.editSessionIds = [...(t.editSessionIds ?? []).filter(x => x !== sessionId), sessionId].slice(-20);
    });
  }
  /** Every edit chat any task has used, live or closed. */
  async editSessionIds(): Promise<Set<string>> {
    const s = await this.read();
    return new Set(s.tasks.flatMap(t => [...(t.editSessionIds ?? []), ...(t.editSessionId ? [t.editSessionId] : [])]));
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
      else if (!manual) {
        // Manual runs never use up a scheduled run.
        t.scheduledRunCount = (t.scheduledRunCount ?? 0) + 1;
        t.nextRunAt = nextOccurrence(t.schedule, now, t.scheduledRunCount);
        if (finiteSchedule(t.schedule) && t.nextRunAt == null) t.enabled = false;
      }
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
        if (snap.state === "needs_input") { this.idleSince.delete(r.id); await this.store.record(r.id, { status: "needs_input", needsInputAt: r.needsInputAt ?? now }); }
        else if (snap.state === "failed" || snap.state === "missing") {
          await this.store.record(r.id, { status: snap.state === "failed" ? "failed" : "interrupted", finishedAt: now, error: snap.error ?? "The session is no longer running. Open its conversation to inspect the result." });
        } else if (snap.state === "idle" && snap.summary) {
          const since = this.idleSince.get(r.id);
          if (since == null) this.idleSince.set(r.id, now);
          else if (now - since >= 5000) { await this.store.record(r.id, { status: "succeeded", finishedAt: now, summary: snap.summary.slice(0, 8000) }); this.idleSince.delete(r.id); }
        } else { this.idleSince.delete(r.id); if (r.status === "needs_input") await this.store.record(r.id, { status: "running", needsInputAt: undefined }); }
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
