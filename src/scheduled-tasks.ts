import { Cron } from "croner";
import { mkdir, readFile, rename, writeFile, stat } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { randomUUID, createHash } from "node:crypto";
import type { TaskOutcome } from "./scheduled-task-outcome.ts";
import { TaskPostReviewQueue } from "./task-post-review.ts";
import type { JobDecision } from "./chat-job-result.ts";

/** `at` anchors once/repeat, and optionally interval (an exact gap counted from `at`).
 * `maxRuns` (cron) and `endsAt` (cron, interval) end an otherwise open schedule. */
export type TaskSchedule = { kind: "once" | "interval" | "repeat" | "cron"; timezone: string; at?: string; everyMinutes?: number; occurrences?: number; expression?: string; maxRuns?: number; endsAt?: string };
export type TaskAction = "session" | "chat" | "notify";
export type TaskInput = { name: string; prompt: string; cwd?: string; agent?: "claude" | "codex"; model?: string | null; schedule: TaskSchedule; enabled?: boolean; sourceSessionId?: string; action?: TaskAction; chatId?: string; notification?: "always" | "requested"; stopOnNotify?: boolean; requestID?: string };
export const taskAction = (task: Pick<TaskInput,"action">): TaskAction => task.action ?? "session";
export type TaskEditSessionConfig = Pick<TaskInput, "agent" | "model">;
/** `scheduledRunCount` counts scheduled (not manual) runs since the schedule last changed; cron `maxRuns` reads it.
 * `pausedAt` is set when the user switches a task off and cleared on resume. */
export type ScheduledTask = TaskInput & { id: string; enabled: boolean; createdAt: number; updatedAt: number; nextRunAt: number | null; revision?: number; requestFingerprint?: string; retryAt?: number; retryOfRunId?: string; retryAutomatic?: boolean; scheduleDelayMs?: number; scheduleRevision?: number; lastRunAt?: number; cancelledAt?: number; pausedAt?: number; scheduledRunCount?: number; editSessionId?: string; editSessionIds?: string[]; editSessionConfig?: TaskEditSessionConfig };
export type TaskRun = { id: string; taskId: string; taskName: string; agent: string; trigger: "scheduled" | "manual"; scheduledFor: number; startedAt: number; finishedAt?: number; retryOfRunId?: string; retryFallbackAt?: number; retryFallbackAutomatic?: boolean; occurrence?: number; scheduleRevision?: number; status: "queued" | "starting" | "running" | "needs_input" | "succeeded" | "incomplete" | "failed" | "interrupted" | "cancelled"; sessionId?: string; tmuxName?: string; summary?: string; error?: string; needsInputAt?: number; outcome?: TaskOutcome; snapshot?: ScheduledTask; decision?: JobDecision; chatRequestID?: string; outcomeReviews?: TaskOutcomeReview[] };
export type TaskDelivery = {state:"pending"|"accepted"|"retired"|"failed";attempts:number;nextAttemptAt:number;error?:string};
export type TaskNotification = {id:string;runId:string;taskId:string;chatId:string;title:string;body:string;createdAt:number;state:"pending"|"accepted"|"cancelled"|"failed";devices:Record<string,TaskDelivery>;error?:string};
export type TaskState = { version: 2; tasks: ScheduledTask[]; runs: TaskRun[]; notifications:TaskNotification[]; imports?:string[]; deletedChatIDs?:string[] };
export const activeRun = (r: TaskRun) => ["queued", "starting", "running", "needs_input"].includes(r.status);
type RunAssessment = Pick<TaskRun, "status" | "summary" | "error" | "outcome">;
export type TaskOutcomeReview = { at: number; reason: string; sessionId: string; source: "session_final_verdict"; previous: RunAssessment; outcome: TaskOutcome; report: string };
const assessment = (r: RunAssessment): RunAssessment => ({ status: r.status, outcome: r.outcome, summary: r.summary, error: r.error });
const reviewVersion = (r: TaskRun) => JSON.stringify([assessment(r), r.sessionId, r.outcomeReviews?.length ?? 0]);
export class TaskError extends Error { constructor(message: string, readonly status = 400) { super(message); } }

function cron(schedule: TaskSchedule) {
  const expression = schedule.expression?.trim() ?? "";
  if (expression.split(/\s+/).length !== 5 || /\/0(?:\D|$)/.test(expression)) throw new TaskError("Use a five-field cron expression with positive steps.");
  try { return new Cron(expression, { timezone: schedule.timezone, paused: true }); }
  catch { throw new TaskError("The cron expression is invalid."); }
}

/** A schedule that stops on its own: a finite repeat, or cron/interval with an end. */
export const finiteSchedule = (s: TaskSchedule) => s.kind === "repeat" || s.maxRuns != null || s.endsAt != null;

/** Recovery moves remaining occurrences, while preserving the user's saved schedule. */
export function effectiveSchedule(t: ScheduledTask): TaskSchedule {
  return t.scheduleDelayMs && t.schedule.at && t.schedule.kind === "repeat"
    ? { ...t.schedule, at: new Date(Date.parse(t.schedule.at) + t.scheduleDelayMs).toISOString() }
    : t.schedule;
}

/** The next interval, including the recovery window after a repeat's final occurrence. */
function nextRetryWindow(t: ScheduledTask, after: number): number | null {
  const schedule = effectiveSchedule(t);
  if (schedule.kind !== "repeat" && schedule.kind !== "interval") return null;
  return nextOccurrence({ ...schedule, kind: "interval", occurrences: undefined }, after);
}

function deferFollowingRuns(t: ScheduledTask, at: number) {
  if (t.nextRunAt == null || t.nextRunAt > at) return;
  const next = nextRetryWindow(t, at);
  if (next != null && t.schedule.kind === "repeat") t.scheduleDelayMs = (t.scheduleDelayMs ?? 0) + next - t.nextRunAt;
  t.nextRunAt = next;
  if (finiteSchedule(t.schedule) && next == null) t.enabled = false;
}

function clearRetry(t: ScheduledTask) {
  delete t.retryAt; delete t.retryOfRunId; delete t.retryAutomatic;
}

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
  for (const key of ["name", "prompt"] as const) {
    if (typeof input[key] !== "string" || !input[key].trim()) throw new TaskError(`${key} is required.`);
  }
  if (input.name.length > 160 || input.prompt.length > 50_000) throw new TaskError("Task name or instructions are too long.");
  const action=taskAction(input);
  if (!["session","chat","notify"].includes(action)) throw new TaskError("Choose a session, chat, or reminder action.");
  if(input.chatId!=null&&!/^chat-[a-f0-9-]{36}$/.test(input.chatId))throw new TaskError("Choose a durable chat.");
  if(input.requestID!=null&&(typeof input.requestID!=="string"||!input.requestID.trim()||input.requestID.length>128))throw new TaskError("Choose a valid creation request identifier.");
  if(action!=="session"){
    if(!input.chatId)throw new TaskError("Choose a durable chat.");
    if(input.prompt.length>24000)throw new TaskError("Task instructions are too long.");
    if(!input.requestID)throw new TaskError("A stable creation request identifier is required.");
    if(input.cwd!=null||input.agent!=null||input.model!=null)throw new TaskError("Chat tasks use their owning chat's execution settings.");
    if(input.notification!=null&&!["always","requested"].includes(input.notification))throw new TaskError("Choose a notification policy.");
    if(input.stopOnNotify!=null&&typeof input.stopOnNotify!=="boolean")throw new TaskError("Choose a valid stop rule.");
    if(input.enabled!=null&&typeof input.enabled!=="boolean")throw new TaskError("enabled must be true or false.");
    return {name:input.name.trim(),prompt:input.prompt.trim(),action,chatId:input.chatId,schedule:validateSchedule(input.schedule,now,allowPastOnce),enabled:input.enabled??true,notification:action==="notify"?"always":input.notification??"requested",stopOnNotify:input.stopOnNotify??false,requestID:input.requestID.trim()};
  }
  if (typeof input.cwd!=="string"||!isAbsolute(input.cwd)) throw new TaskError("Choose an absolute directory on this host.");
  if (!["claude", "codex"].includes(input.agent!)) throw new TaskError("Choose Claude or Codex.");
  if (input.model != null && (typeof input.model !== "string" || !/^[a-zA-Z0-9._:/-]{1,160}$/.test(input.model))) throw new TaskError("Invalid model name.");
  if (input.enabled != null && typeof input.enabled !== "boolean") throw new TaskError("enabled must be true or false.");
  const s = validateSchedule(input.schedule, now, allowPastOnce);
  return { name: input.name.trim(), prompt: input.prompt.trim(), cwd: input.cwd.trim(), agent: input.agent, schedule: { ...s }, enabled: input.enabled ?? true,
    ...(input.model ? { model: input.model } : {}), ...(typeof input.sourceSessionId === "string" ? { sourceSessionId: input.sourceSessionId } : {}), ...(input.action?{action}:{}),...(input.chatId?{chatId:input.chatId}:{}),...(input.requestID?{requestID:input.requestID.trim()}: {}) };
}

function creationFingerprint(t:TaskInput){
  // Retain the v1 chat-job receipt format, including retries after migration.
  const value=taskAction(t)==="session"?t:{chatId:t.chatId,name:t.name,instructions:t.prompt,action:t.action==="chat"?"run":"notify",schedule:t.schedule,notification:t.notification,stopOnNotify:t.stopOnNotify};
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

/** The host owns all mutations. Serial transactions + atomic rename prevent lost claims. */
export class TaskStore {
  private queue: Promise<unknown> = Promise.resolve();
  constructor(readonly path: string) {}
  private async load(): Promise<TaskState> {
    try {
      const value = JSON.parse(await readFile(this.path, "utf8"));
      if (![1,2].includes(value.version) || !Array.isArray(value.tasks) || !Array.isArray(value.runs)||(value.version===2||value.notifications!=null)&&!Array.isArray(value.notifications)) throw Error("Invalid scheduled task store");
      if(value.deletedChatIDs!=null&&(!Array.isArray(value.deletedChatIDs)||value.deletedChatIDs.some((id:unknown)=>typeof id!=="string")))throw Error("Invalid deleted chat identifiers");
      return {...value,version:2,notifications:value.notifications??[]};
    } catch (e) { if ((e as NodeJS.ErrnoException).code === "ENOENT") return { version: 2, tasks: [], runs: [],notifications:[] }; throw e; }
  }
  async read(): Promise<TaskState> { await this.queue; return this.load(); }
  transaction<T>(fn: (s: TaskState) => T | Promise<T>): Promise<T> {
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
    const clean = validateTask(input, now,!!input.requestID);
    if (taskAction(clean)==="session"&&!(await stat(clean.cwd!).catch(() => null))?.isDirectory()) throw new TaskError("That directory does not exist on this host.");
    return this.transaction(s => {
      if(clean.chatId&&s.deletedChatIDs?.includes(clean.chatId))throw new TaskError("This chat was deleted.",410);
      const fingerprint=clean.requestID?creationFingerprint(clean):undefined;
      const existing=clean.requestID?s.tasks.find(t=>t.chatId===clean.chatId&&t.requestID===clean.requestID):undefined;
      if(existing){if(existing.requestFingerprint!==fingerprint)throw new TaskError("This request identifier belongs to a different task.",409);return existing;}
      validateSchedule(clean.schedule,now);
      if (s.tasks.filter(t => !t.cancelledAt).length >= 1000) throw new TaskError("This host already has 1,000 tasks.");
      const task: ScheduledTask = { ...clean, id: randomUUID(), enabled: clean.enabled!, createdAt: now, updatedAt: now, nextRunAt: nextOccurrence(clean.schedule, now), scheduledRunCount: 0, revision:1,...(fingerprint?{requestFingerprint:fingerprint}:{}), ...(clean.enabled ? {} : { pausedAt: now }) };
      s.tasks.push(task); return task;
    });
  }
  async update(id: string, patch: Partial<TaskInput>&{revision?:number}, now = Date.now()): Promise<ScheduledTask> {
    return this.transaction(async s => {
      const t = s.tasks.find(t => t.id === id); if (!t) throw new TaskError("Task not found.", 404);
      if (t.cancelledAt) throw new TaskError("This task has been cancelled.", 409);
      if(patch.revision!==undefined&&patch.revision!==(t.revision??1))throw new TaskError("The task changed. Reload before saving.",409);
      if(patch.action!=null&&taskAction(patch)!==taskAction(t)||patch.chatId!=null&&patch.chatId!==t.chatId||patch.requestID!=null&&patch.requestID!==t.requestID)throw new TaskError("Create a new task to change its action or chat.");
      if(taskAction(t)!=="session"){
        if(patch.revision!==(t.revision??1))throw new TaskError("The task changed. Reload before saving.",409);
        const clean=validateTask({...t,...patch},now,patch.schedule==null);
        if(patch.schedule!=null){t.schedule=clean.schedule;t.scheduledRunCount=0;t.nextRunAt=nextOccurrence(clean.schedule,now);t.scheduleRevision=(t.scheduleRevision??0)+1;clearRetry(t);}
        if(patch.enabled===true&&t.nextRunAt==null&&patch.schedule==null&&!s.runs.some(r=>r.taskId===id&&r.status==="queued"))throw new TaskError("This task finished. Choose a new schedule to run again.",409);
        Object.assign(t,{name:clean.name,prompt:clean.prompt,notification:clean.notification,stopOnNotify:clean.stopOnNotify});
        if(patch.enabled===false){t.enabled=false;t.pausedAt=now;}
        if(patch.enabled===true){t.enabled=true;delete t.pausedAt;}
        t.revision=(t.revision??1)+1;t.updatedAt=now;
        for(const r of s.runs.filter(r=>r.taskId===id&&r.status==="queued")){if(patch.schedule!=null)r.status="cancelled";else r.snapshot=structuredClone(t);}
        return t;
      }
      const changesSchedule = patch.schedule != null && !sameSchedule(patch.schedule, t.schedule);
      const resuming = patch.enabled === true && !t.enabled;
      const pausing = patch.enabled === false;
      const pendingRecovery = !changesSchedule && t.retryOfRunId != null;
      if (resuming && !changesSchedule && !pendingRecovery && t.schedule.kind === "repeat" && t.nextRunAt == null) throw new TaskError("This repeat schedule has finished. Choose a future first start for a new series.", 409);
      const requested = patch.schedule ?? t.schedule;
      const sameRepeatStart = t.schedule.kind === "repeat" && requested.kind === "repeat" && Date.parse(t.schedule.at!) === Date.parse(requested.at!);
      const clean = validateTask({ ...t, ...patch }, now, (!changesSchedule && !resuming) || sameRepeatStart);
      const done = changesSchedule ? 0 : (t.scheduledRunCount ?? 0);
      const next = changesSchedule || (resuming && !pendingRecovery) ? nextOccurrence(changesSchedule ? clean.schedule : effectiveSchedule(t), now, done) : t.nextRunAt;
      if (clean.schedule.kind === "repeat" && clean.enabled && next == null && !pendingRecovery) throw new TaskError("This repeat schedule has finished. Choose a future first start for a new series.");
      if (finiteSchedule(clean.schedule) && clean.enabled && next == null && !pendingRecovery) throw new TaskError("This schedule has finished. Choose a later end or more runs to continue.", 409);
      if (!(await stat(clean.cwd!).catch(() => null))?.isDirectory()) throw new TaskError("That directory does not exist on this host.");
      Object.assign(t, clean, { updatedAt: now });
      t.revision=(t.revision??1)+1;
      if (clean.model == null) delete t.model;
      if (changesSchedule || resuming) t.nextRunAt = next;
      if (changesSchedule) {
        t.scheduledRunCount = 0; delete t.scheduleDelayMs;
        t.scheduleRevision = (t.scheduleRevision ?? 0) + 1;
        if (t.retryOfRunId != null) clearRetry(t);
      }
      if (pausing) t.pausedAt = now;
      if (t.enabled) delete t.pausedAt;
      return t;
    });
  }
  /** Remembers the task's edit chat so the next request reuses it. */
  async setEditSession(id: string, sessionId: string, config?: TaskEditSessionConfig): Promise<void> {
    // The id history outlives the chat: once a chat closes, its listing has no managed record left,
    // so clients find it here to keep it out of Sessions.
    await this.transaction(s => {
      const t = s.tasks.find(t => t.id === id); if (!t) return;
      t.editSessionId = sessionId;
      t.editSessionIds = [...(t.editSessionIds ?? []).filter(x => x !== sessionId), sessionId].slice(-20);
      // Capture the launch settings, not whatever the task may have changed to
      // while the provider was starting. Legacy callers leave them unknown.
      if (config) t.editSessionConfig = { agent: config.agent, ...(config.model ? { model: config.model } : {}) };
      else delete t.editSessionConfig;
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
      t.cancelledAt = now; t.enabled = false; t.nextRunAt = null; clearRetry(t); t.updatedAt = now;t.revision=(t.revision??1)+1;
      for(const n of s.notifications)if(n.taskId===id&&n.state==="pending")n.state="cancelled";
      for(const r of s.runs)if(r.taskId===id&&r.status==="queued")r.status="cancelled";
      return t;
    });
  }
  /** Cancel this conversation's future work and unsent alerts; retain Task audit history. */
  async cancelForChat(chatId:string,now=Date.now()){
    return this.transaction(s=>{
      const owned=s.tasks.filter(t=>t.chatId===chatId);
      if(s.runs.some(r=>activeRun(r)&&owned.some(t=>t.id===r.taskId&&taskAction(t)==='session')))
        throw new TaskError('Stop this chat’s running task before deleting it.',409);
      if(!s.deletedChatIDs?.includes(chatId))s.deletedChatIDs=[...(s.deletedChatIDs??[]),chatId];
      const ids=new Set<string>();
      for(const t of owned){
        ids.add(t.id);
        if(t.cancelledAt!=null)continue;
        t.cancelledAt=now;t.enabled=false;t.nextRunAt=null;clearRetry(t);t.updatedAt=now;t.revision=(t.revision??1)+1;
      }
      for(const n of s.notifications)if(ids.has(n.taskId)&&n.state==='pending')n.state='cancelled';
      for(const r of s.runs)if(ids.has(r.taskId)&&activeRun(r)){r.status='cancelled';r.finishedAt=now;}
    });
  }
  /** A durable extra run; null cancels it without changing the regular schedule. */
  async scheduleRetry(id: string, at: string | null, now = Date.now()): Promise<ScheduledTask> {
    if (at !== null && (!isoWithOffset(at) || Date.parse(at) <= now)) throw new TaskError("Choose a retry time in the future with a timezone offset.");
    return this.transaction(s => {
      const t = s.tasks.find(t => t.id === id); if (!t) throw new TaskError("Task not found.", 404);
      if (t.cancelledAt) throw new TaskError("This task has been cancelled.", 409);
      if (at !== null && s.runs.some(r => r.taskId === id && activeRun(r))) throw new TaskError("This task is already running.", 409);
      if (at === null) clearRetry(t);
      else {
        t.retryAt = Date.parse(at); delete t.retryAutomatic;
        if (t.retryOfRunId != null) deferFollowingRuns(t, t.retryAt);
      }
      t.updatedAt = now; return t;
    });
  }
  async claim(id: string, now = Date.now(), manual: boolean | "retry" = false): Promise<TaskRun | null> {
    return this.transaction(s => {
      const t = s.tasks.find(t => t.id === id);
      if(t?.chatId&&s.deletedChatIDs?.includes(t.chatId))return null;
      if (!t || t.cancelledAt || s.runs.some(r => r.taskId === id && activeRun(r))) return null;
      if (!manual && t.retryOfRunId != null) return null;
      if (!manual && (!t.enabled || t.nextRunAt == null || t.nextRunAt > now)) return null;
      if (manual === "retry" && (t.retryAt == null || t.retryAt > now)) return null;
      if (manual === "retry" && t.retryAutomatic && t.pausedAt != null) return null;
      const run: TaskRun = { id: randomUUID(), taskId: id, taskName: t.name, agent: t.agent??"claude", trigger: manual ? "manual" : "scheduled", scheduledFor: manual === "retry" ? t.retryAt! : manual ? now : t.nextRunAt!, startedAt: now, status: taskAction(t)==="session"?"starting":"queued",...(taskAction(t)!=="session"?{snapshot:structuredClone(t)}:{}) };
      run.scheduleRevision = t.scheduleRevision ?? 0;
      if (manual && t.retryOfRunId != null) {
        run.retryOfRunId = t.retryOfRunId;
        if (manual === true) { run.retryFallbackAt = t.retryAt; run.retryFallbackAutomatic = t.retryAutomatic === true; }
        run.occurrence = s.runs.find(r => r.id === t.retryOfRunId)?.occurrence;
        deferFollowingRuns(t, now);
        if (finiteSchedule(t.schedule) && t.nextRunAt == null) t.enabled = false;
      } else if (!manual && t.schedule.kind === "repeat") {
        run.occurrence = Math.floor((run.scheduledFor - Date.parse(effectiveSchedule(t).at!)) / (t.schedule.everyMinutes! * 60_000)) + 1;
      }
      s.runs.push(run); t.lastRunAt = now;
      if (manual) clearRetry(t);
      if (t.schedule.kind === "once" && manual !== "retry") { t.enabled = false; t.nextRunAt = null; }
      else if (!manual) {
        // Manual runs never use up a scheduled run.
        t.scheduledRunCount = (t.scheduledRunCount ?? 0) + 1;
        t.nextRunAt = nextOccurrence(effectiveSchedule(t), now, t.scheduledRunCount);
        if (finiteSchedule(t.schedule) && t.nextRunAt == null) t.enabled = false;
      }
      return run;
    });
  }
  /** An explicit review changes the displayed assessment, never scheduling or execution identity. */
  async reviewOutcome(taskId: string, id: string, expected: TaskRun, outcome: TaskOutcome, report: string, reason: string, now: number) {
    return this.transaction(s => {
      const r = s.runs.find(r => r.id === id && r.taskId === taskId);
      if (!r || !s.tasks.some(t => t.id === taskId)) throw new TaskError("Task run not found.", 404);
      if (activeRun(r) || !r.sessionId) throw new TaskError("Only a finalized run with a source session can be reviewed.", 409);
      if (!["completed", "incomplete", "error"].includes(outcome.status) || !outcome.summary?.trim() || outcome.summary.length > 8000)
        throw new TaskError("A valid structured outcome is required.");
      const next: RunAssessment = { status: outcome.status === "completed" ? "succeeded" : outcome.status === "error" ? "failed" : "incomplete",
        outcome, summary: report.slice(0, 8000), error: outcome.status === "completed" ? undefined : outcome.summary };
      if (JSON.stringify(assessment(r)) === JSON.stringify(next)) return { run: r, changed: false };
      if (reviewVersion(r) !== reviewVersion(expected)) throw new TaskError("The run changed during review. Read its latest outcome and review again.", 409);
      const review: TaskOutcomeReview = { at: now, reason, sessionId: r.sessionId, source: "session_final_verdict",
        previous: assessment(r), outcome, report: next.summary! };
      r.outcomeReviews = [...(r.outcomeReviews ?? []), review];
      Object.assign(r, next);
      return { run: r, changed: true };
    });
  }
  async record(id: string, patch: Partial<TaskRun>): Promise<void> {
    await this.transaction(s => {
      const r = s.runs.find(r => r.id === id); if (!r) return;
      if (r.status === "cancelled") return;
      const wasActive = activeRun(r);
      Object.assign(r, patch, { id: r.id, taskId: r.taskId });
      const t = s.tasks.find(t => t.id === r.taskId);
      if (!wasActive || activeRun(r) || !t || t.cancelledAt) return;
      if(taskAction(t)!=="session"){
        if(r.status!=="succeeded")return;
        const saved=r.snapshot??t,notify=saved.notification==="always"||r.decision?.notify===true;
        if(r.decision?.stop||(notify&&saved.stopOnNotify)){t.enabled=false;t.nextRunAt=null;t.revision=(t.revision??1)+1;}
        if(notify&&!s.notifications.some(n=>n.runId===r.id))s.notifications.push({id:r.id,runId:r.id,taskId:t.id,chatId:t.chatId!,title:saved.name,body:(r.decision?.message||r.summary||saved.prompt).slice(0,1000),createdAt:r.finishedAt??Date.now(),state:"pending",devices:{}});
        return;
      }
      if((r.scheduleRevision ?? 0) !== (t.scheduleRevision ?? 0))return;
      const now = r.finishedAt ?? Date.now();
      if (r.retryOfRunId && r.status === "succeeded") { deferFollowingRuns(t, now); return; }
      if (!(r.status === "incomplete" && r.trigger === "scheduled") && !(r.retryOfRunId && ["incomplete", "failed", "interrupted"].includes(r.status))) return;
      const fallbackAt = r.retryFallbackAt != null && r.retryFallbackAt > now ? r.retryFallbackAt : undefined;
      const at = t.retryAt ?? fallbackAt ?? (t.nextRunAt != null && t.nextRunAt > now ? t.nextRunAt : nextRetryWindow(t, now));
      if (at == null || (t.schedule.kind !== "interval" && t.schedule.kind !== "repeat")) return;
      // Runs launched by an older host do not yet carry their occurrence number.
      // Capture it before moving the effective anchor, so earlier retries keep it.
      if (r.occurrence == null && r.trigger === "scheduled" && t.schedule.kind === "repeat") {
        r.occurrence = Math.floor((r.scheduledFor - Date.parse(effectiveSchedule(t).at!)) / (t.schedule.everyMinutes! * 60_000)) + 1;
      }
      if (t.retryAt == null) {
        if (fallbackAt != null && r.retryFallbackAutomatic === false) delete t.retryAutomatic;
        else t.retryAutomatic = true;
      }
      t.retryAt = at; t.retryOfRunId = r.retryOfRunId ?? r.id;
      deferFollowingRuns(t, at); t.updatedAt = now;
    });
  }
  /** Atomic, idempotent import. Preserve source files for review and rollback. */
  async importChatJobs(path:string):Promise<void>{
    const key="chat-jobs-v1:"+path;
    if((await this.read()).imports?.includes(key))return;
    let source:any;try{source=JSON.parse(await readFile(path,"utf8"));}catch(e:any){if(e.code==="ENOENT")return;throw e;}
    if(source.version!==1||!Array.isArray(source.jobs)||!Array.isArray(source.runs)||!Array.isArray(source.notifications))throw new TaskError("Invalid legacy chat job store.");
    const object=(v:any)=>v!=null&&typeof v==="object"&&!Array.isArray(v);
    const uuid=(v:any)=>typeof v==="string"&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
    const time=(v:any)=>typeof v==="number"&&Number.isFinite(v)&&v>=0;
    const count=(v:any)=>Number.isSafeInteger(v)&&v>=0;
    const optionalText=(v:any)=>v===undefined||typeof v==="string";
    const receiptKey=(t:Pick<TaskInput,"chatId"|"requestID">)=>JSON.stringify([t.chatId,t.requestID]);
    const convert=(j:any):ScheduledTask=>{
      if(!object(j)||!uuid(j.id)||!["run","notify"].includes(j.action)||typeof j.enabled!=="boolean"||
        !["always","requested"].includes(j.notification)||typeof j.stopOnNotify!=="boolean"||
        !time(j.createdAt)||!time(j.updatedAt)||(j.nextRunAt!==null&&!time(j.nextRunAt))||
        !Number.isSafeInteger(j.revision)||j.revision<1||!count(j.scheduledRunCount)||
        typeof j.requestFingerprint!=="string"||!j.requestFingerprint.trim()||
        j.pausedAt!==undefined&&!time(j.pausedAt)||j.cancelledAt!==undefined&&!time(j.cancelledAt))
        throw new TaskError("Invalid legacy task lifecycle or identity.");
      const clean=validateTask({name:j.name,prompt:j.instructions,action:j.action==="run"?"chat":"notify",chatId:j.chatId,schedule:j.schedule,enabled:j.enabled,notification:j.notification,stopOnNotify:j.stopOnNotify,requestID:j.requestID},Date.now(),true);
      return {...clean,id:j.id,enabled:j.enabled,createdAt:j.createdAt,updatedAt:j.updatedAt,nextRunAt:j.nextRunAt,revision:j.revision,requestFingerprint:j.requestFingerprint,scheduledRunCount:j.scheduledRunCount,...(j.pausedAt!=null?{pausedAt:j.pausedAt}:{}),...(j.cancelledAt!=null?{cancelledAt:j.cancelledAt}:{})};
    };
    const tasks:ScheduledTask[]=source.jobs.map(convert),ids=new Set(tasks.map(t=>t.id));
    if(ids.size!==tasks.length)throw new TaskError("Duplicate legacy task identities.");
    if(new Set(tasks.map(receiptKey)).size!==tasks.length)throw new TaskError("Duplicate legacy task creation receipts.");
    const statuses:Record<string,TaskRun["status"]>={queued:"queued",running:"running",completed:"succeeded",failed:"failed",interrupted:"interrupted",cancelled:"cancelled"};
    const runs:TaskRun[]=source.runs.map((r:any)=>{
      const task=tasks.find(t=>t.id===r?.jobId);
      if(!object(r)||!task||!Object.hasOwn(statuses,r.state)||!object(r.snapshot)||r.snapshot.id!==r.jobId||r.chatId!==task.chatId||r.snapshot.chatId!==task.chatId||!uuid(r.id)||
        !time(r.scheduledFor)||!time(r.createdAt)||r.finishedAt!==undefined&&!time(r.finishedAt)||!optionalText(r.summary)||!optionalText(r.error)||
        r.decision!==undefined&&(!object(r.decision)||typeof r.decision.notify!=="boolean"||typeof r.decision.stop!=="boolean"||typeof r.decision.message!=="string"||r.decision.message.length>1000))
        throw new TaskError("Invalid legacy task run.");
      const snapshot=convert(r.snapshot);
      if(snapshot.action!==task.action||snapshot.requestID!==task.requestID||snapshot.requestFingerprint!==task.requestFingerprint)throw new TaskError("Invalid legacy run ownership.");
      return {id:r.id,taskId:r.jobId,taskName:snapshot.name,agent:"claude",trigger:"scheduled",scheduledFor:r.scheduledFor,startedAt:r.createdAt,finishedAt:r.finishedAt,status:statuses[r.state]!,snapshot,chatRequestID:"job:"+r.id,sessionId:r.state==="queued"?undefined:r.chatId,summary:r.summary,error:r.error,decision:r.decision,scheduleRevision:0};
    });
    if(new Set(runs.map(r=>r.id)).size!==runs.length)throw new TaskError("Duplicate legacy run identities.");
    const notifications:TaskNotification[]=source.notifications.map((n:any)=>{
      const run=runs.find(r=>r.id===n?.runId);
      if(!object(n)||!uuid(n.id)||n.id!==n.runId||!run||run.taskId!==n.jobId||run.snapshot!.chatId!==n.chatId||
        !["pending","accepted","cancelled","failed"].includes(n.state)||!object(n.devices)||!time(n.createdAt)||
        typeof n.title!=="string"||!n.title.trim()||typeof n.body!=="string"||!optionalText(n.error))throw new TaskError("Invalid legacy notification.");
      for(const [key,d] of Object.entries(n.devices) as [string,any][]){
        if(!key||!object(d)||!["pending","accepted","retired","failed"].includes(d.state)||!count(d.attempts)||!time(d.nextAttemptAt)||!optionalText(d.error))throw new TaskError("Invalid legacy notification delivery receipt.");
      }
      return {id:n.id,runId:n.runId,taskId:n.jobId,chatId:n.chatId,title:n.title,body:n.body,createdAt:n.createdAt,state:n.state,devices:n.devices,...(n.error!==undefined?{error:n.error}:{})};
    });
    if(new Set(notifications.map(n=>n.id)).size!==notifications.length)throw new TaskError("Duplicate legacy notification identities.");
    await this.transaction(s=>{
      if(s.imports?.includes(key))return;
      if(tasks.some(t=>s.tasks.some(x=>x.id===t.id||x.requestID!=null&&receiptKey(x)===receiptKey(t)))||runs.some(r=>s.runs.some(x=>x.id===r.id))||notifications.some(n=>s.notifications.some(x=>x.id===n.id)))
        throw new TaskError("Legacy task identity or creation receipt collision. Import stopped without changing records.",409);
      s.tasks.push(...tasks);s.runs.push(...runs);s.notifications.push(...notifications);s.imports=[...(s.imports??[]),key];
    });
  }
}

export type RunSnapshot = { state: "working" | "idle" | "needs_input" | "failed" | "missing"; summary?: string; error?: string; outcome?: TaskOutcome; decision?:JobDecision; verdictAt?: number };
export type TaskExecutor = { launch(task: ScheduledTask, run: TaskRun): Promise<{ sessionId: string; tmuxName?: string }|null>; inspect(run: TaskRun): Promise<RunSnapshot>; immediate?:boolean; recover?(run:TaskRun):Promise<void>; afterTick?():Promise<void>; validate?(task:TaskInput):Promise<void> };
export class TaskScheduler {
  private ticking = false;
  private launching = new Set<string>();
  private idleSince = new Map<string, { since: number; fingerprint: string }>();
  private executors=new Map<TaskAction,TaskExecutor>();
  private claimCursor=0;
  private chatCursor=0;
  private timer?:ReturnType<typeof setTimeout>;
  private stopReviews?:()=>void;
  private stopped=false;
  private started=false;
  private activeTick?:Promise<void>;
  private dispatches=new Set<Promise<void>>();
  constructor(readonly store: TaskStore, private executor: TaskExecutor, private now = () => Date.now()) {}
  async reviewOutcome(taskId: string, runId: string, reason: unknown, expected?: { verdictAtOrAfter?: number; outcome?: TaskOutcome }) {
    if (typeof reason !== "string" || !reason.trim() || reason.length > 2000) throw new TaskError("Give a review reason of 1–2000 characters.");
    const state = await this.store.read();
    const run = state.runs.find(r => r.id === runId && r.taskId === taskId);
    if (!run || !state.tasks.some(t => t.id === taskId)) throw new TaskError("Task run not found.", 404);
    if (activeRun(run) || !run.sessionId) throw new TaskError("Only a finalized run with a source session can be reviewed.", 409);
    const task = state.tasks.find(t => t.id === taskId)!;
    if (taskAction(task) !== "session") throw new TaskError("Only coding-session runs support outcome review. Chat tasks retain their saved notification decision.", 409);
    const snapshot = await this.executor.inspect(run);
    if (snapshot.state !== "idle" || !snapshot.outcome) throw new TaskError(snapshot.error ?? "The source session must be idle with a valid final verdict for this run.", 409);
    if (expected?.verdictAtOrAfter != null && (snapshot.verdictAt == null || snapshot.verdictAt < expected.verdictAtOrAfter))
      throw new TaskError("Waiting for the triggering turn's final transcript.", 409);
    if (expected?.outcome && JSON.stringify(snapshot.outcome) !== JSON.stringify(expected.outcome))
      throw new TaskError("Waiting for the hook's final verdict to appear in the transcript.", 409);
    return this.store.reviewOutcome(taskId, runId, run, snapshot.outcome, snapshot.summary ?? snapshot.outcome.summary, reason.trim(), this.now());
  }
  register(action:TaskAction,executor:TaskExecutor){this.executors.set(action,executor);}
  private forTask(task:Pick<TaskInput,"action">){const action=taskAction(task),executor=this.executors.get(action);if(!executor&&action!=="session")throw new TaskError("This task action is unavailable on this host.",503);return executor??this.executor;}
  async save(input:TaskInput){if(this.stopped)throw new TaskError("Tasks are stopping.",503);const clean=validateTask(input,this.now(),!!input.requestID);await this.forTask(clean).validate?.(clean);if(clean.chatId&&taskAction(clean)==="session")await this.executors.get("chat")?.validate?.(clean);return this.store.save(clean,this.now());}
  async recover() {
    const state=await this.store.read();
    for(const r of state.runs.filter(activeRun)){
      const task=r.snapshot??state.tasks.find(t=>t.id===r.taskId);if(!task)continue;
      const executor=this.forTask(task);
      if(executor.recover){await executor.recover(r);continue;}
      if (r.status === "starting" && !r.sessionId && !this.launching.has(r.id)) {
      await this.store.record(r.id, { status: "interrupted", finishedAt: this.now(), error: "The host restarted during launch. Check sessions before running again." });
      }
    }
  }
  async runNow(id: string): Promise<TaskRun> {
    if(this.stopped)throw new TaskError("Tasks are stopping.",503);
    const run = await this.store.claim(id, this.now(), true);
    if (!run) throw new TaskError("This task is cancelled, missing, or already running.", 409);
    this.dispatch(run); return run;
  }
  private dispatch(run:TaskRun){const work=this.launch(run);this.dispatches.add(work);void work.then(()=>this.dispatches.delete(work),()=>this.dispatches.delete(work));return work;}
  private async launch(run: TaskRun) {
    if(this.launching.has(run.id))return;
    this.launching.add(run.id);
    try {
      const t = (await this.store.read()).tasks.find(t => t.id === run.taskId)!;
      const executor=this.forTask(t),result = await executor.launch(t, run);
      if(result===null)return;
      if (!result.sessionId) throw Error("The agent started without a session ID. Check sessions before retrying.");
      await this.store.record(run.id, { ...result, status: "running" });
      if(executor.immediate)await this.inspect({...run,...result,status:"running"},executor);
    } catch (e) { await this.store.record(run.id, { status: "failed", error: String((e as Error).message ?? e), finishedAt: this.now() }); }
    finally { this.launching.delete(run.id); }
  }
  async tick() {
    if(this.stopped)return;
    if(this.activeTick)return this.activeTick;
    this.activeTick=this.work().finally(()=>{this.activeTick=undefined;});return this.activeTick;
  }
  private async inspect(r:TaskRun,executor:TaskExecutor){
    let snap: RunSnapshot;
    try { snap = await executor.inspect(r); }
    catch (error) { this.idleSince.delete(r.id); console.warn(`[tasks] Could not inspect run ${r.id}: ${error}`); return; }
    const now = this.now();
    if (snap.state === "needs_input") { this.idleSince.delete(r.id); await this.store.record(r.id, { status: "needs_input", needsInputAt: r.needsInputAt ?? now }); }
    else if (snap.state === "failed" || snap.state === "missing") {
      this.idleSince.delete(r.id);
      await this.store.record(r.id, { status: snap.state === "failed" ? "failed" : "interrupted", finishedAt: now, error: snap.error ?? "The session is no longer running. Open its conversation to inspect the result." });
    } else if (snap.state === "idle") {
      if (r.status === "needs_input") await this.store.record(r.id, { status: "running", needsInputAt: undefined });
      const fingerprint = JSON.stringify([snap.summary, snap.outcome, snap.error]);
      const idle = this.idleSince.get(r.id);
      if (!executor.immediate&&(!idle || idle.fingerprint !== fingerprint)) this.idleSince.set(r.id, { since: now, fingerprint });
      else if (executor.immediate || now - idle!.since >= (snap.summary || snap.outcome ? 5000 : 60_000)) {
        const status = snap.outcome?.status === "completed" ? "succeeded" : snap.outcome?.status === "error" ? "failed" : "incomplete";
        await this.store.record(r.id, { status, finishedAt: now,
          summary: (snap.summary ?? snap.outcome?.summary)?.slice(0, 8000), outcome: snap.outcome,decision:snap.decision,
          error: status === "succeeded" ? undefined : snap.outcome?.summary ?? snap.error ?? "The agent ended without a completion verdict. Open the session to review what remains.", needsInputAt: undefined });
        this.idleSince.delete(r.id);
      }
    } else { this.idleSince.delete(r.id); if (r.status === "needs_input") await this.store.record(r.id, { status: "running", needsInputAt: undefined }); }
  }
  private async work(){
    this.ticking = true;
    try {
      const state = await this.store.read();
      const chatRuns=state.runs.filter(r=>activeRun(r)&&r.snapshot&&taskAction(r.snapshot)!=="session");
      const chatBatch=new Set([...chatRuns.slice(this.chatCursor),...chatRuns.slice(0,this.chatCursor)].slice(0,20).map(r=>r.id));
      this.chatCursor=chatRuns.length?(this.chatCursor+20)%chatRuns.length:0;
      for (const r of state.runs.filter(activeRun)) {
        if(r.snapshot&&taskAction(r.snapshot)!=="session"&&!chatBatch.has(r.id))continue;
        if(this.launching.has(r.id))continue;
        const task=r.snapshot??state.tasks.find(t=>t.id===r.taskId);if(!task)continue;
        if(r.status==="queued"){await this.dispatch(r);continue;}
        if(r.sessionId)await this.inspect(r,this.forTask(task));
      }
      // Bound launches per tick. Recurring jobs coalesce missed occurrences.
      let launched = 0;
      const tasks=(await this.store.read()).tasks,ordered=[...tasks.slice(this.claimCursor),...tasks.slice(0,this.claimCursor)];
      for (const t of ordered) {
        if (t.cancelledAt) continue;
        const retryDue = t.retryAt != null && t.retryAt <= this.now();
        if (!retryDue && (!t.enabled || t.nextRunAt == null || t.nextRunAt > this.now())) continue;
        const run = await this.store.claim(t.id, this.now(), retryDue ? "retry" : false);
        if (run) { await this.dispatch(run);this.claimCursor=(tasks.indexOf(t)+1)%tasks.length; if (++launched >= 2) break; }
      }
      for(const executor of new Set([this.executor,...this.executors.values()]))await executor.afterTick?.();
    } finally { this.ticking = false; }
  }
  start(log: (message: string) => void = console.log) {
    if(this.started)return ()=>this.stop();
    this.started=true;
    const reviews = new TaskPostReviewQueue(this, join(dirname(this.store.path), "task-review-queue"), this.now);
    this.stopReviews = reviews.start(log);
    const loop = async () => { try { await this.tick(); } catch (e) { log(`[tasks] ${e}`); } if (!this.stopped)this.timer=setTimeout(loop,1000); };
    void this.recover().then(() => { if (!this.stopped)this.timer=setTimeout(loop,2000); }).catch(e => log(`[tasks] recovery failed: ${e}`));
    return ()=>this.stop();
  }
  private stop(){this.stopped=true;clearTimeout(this.timer);this.stopReviews?.();}
  async close(){this.stop();await this.activeTick;await Promise.all(this.dispatches);}
}
