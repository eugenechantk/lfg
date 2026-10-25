// Explicit connection-error recovery, on the existing Autopilot cadence.
// Claims are immutable and written BEFORE enqueue: uncertain delivery is never
// automatically replayed. Fresh ownership + delivery-time guards fail closed.
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, open, readFile, readdir, link, unlink } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { PATHS } from '../config.ts';
import { hostInfo } from '../hostinfo.ts';
import { readLease, leaseIsFresh, type LeaseRecord } from '../leases.ts';
import { interruptStands } from '../interrupt-marks.ts';
import { scanBack } from '../transcript.ts';
import { listSessions, type Session } from '../sessions.ts';
import { enqueueMessage, listQueue, type QueuedMsg } from '../sendq.ts';
import { capturePaneAsync, inputBoxFromPane, isBusy, parsePrompt, questionSelectorOpen, feedbackPromptOpen } from '../tmux.ts';
import type { AutopilotStep, TaskContext, TaskResult } from './registry.ts';

export const RECOVERY_PREFIX = '[LFG connection recovery]';
const CLIENT_PREFIX = 'autopilot-recovery:';
const DIR = join(PATHS.data, 'autopilot-recovery');
const SETTLE_MS = 60_000;
const MAX_AGE_MS = 24 * 60 * 60_000;
const BACKOFF = [0, 10 * 60_000, 30 * 60_000];
export type RecoveryError = { id: string; at: number; taskId: string };
type Claim = { sessionId: string; taskId: string; at: number; errorId: string };
const hash = (text: string) => createHash('sha256').update(text).digest('hex');
export const recoveryClientId = (errorId: string) => CLIENT_PREFIX + hash(errorId);
export const isRecoveryMessage = (msg: Pick<QueuedMsg, 'clientId'>) => msg.clientId.startsWith(CLIENT_PREFIX);

/** Parse actual records, never quoted prose; a newer conversation row vetoes. */
export function recoveryError(text: string, sessionId: string): RecoveryError | null {
 let last: any = null, taskId = '';
 for (const line of text.split('\n')) {
  let row: any; try { row = JSON.parse(line); } catch { if (line.trim()) last = { type: 'invalid' }; continue; }
  if (row.type === 'system' && ['continued-in', 'compact_boundary'].includes(row.subtype)) last = row;
  if (row.type === 'queue-operation') last = row;
  if (row.type !== 'user' && row.type !== 'assistant') continue;
  last = row;
  if (row.type === 'user' && !row.isMeta && !row.isCompactSummary) {
   const c = row.message?.content;
   const userText = typeof c === 'string' ? c : Array.isArray(c) ? c.filter((x: any) => x.type === 'text').map((x: any) => x.text).join('\n') : '';
   if (userText && !userText.startsWith(RECOVERY_PREFIX)) taskId = row.uuid ?? '';
  }
 }
 if (last?.type !== 'assistant' || last.isApiErrorMessage !== true || last.error !== 'server_error' || last.sessionId !== sessionId || !last.uuid || !taskId) return null;
 const c = last.message?.content;
 const message = typeof c === 'string' ? c : Array.isArray(c) ? c.map((x: any) => x.text ?? '').join('\n') : '';
 // Restrict to observed transport failures, including older Claude wording.
 if (!/Connection (?:lost|dropped|closed)|The response stopped arriving|Response stalled|Stream idle timeout|Can't reach the API server|Unable to connect to API|No response from API|Request timed out/i.test(message)) return null;
 if (/sleep|asleep/i.test(message)) return null;
 const at = Date.parse(last.timestamp);
 return Number.isFinite(at) ? { id: last.uuid, at, taskId } : null;
}

export function recoverySessionSafe(s: Session): boolean {
 return s.agent === 'claude' && s.control === 'direct' && !!s.sessionId && !!s.tmuxTarget && !!s.transcriptPath && !s.busy &&
  !(s.runningChildAgentCount || s.runningChildSessionCount || s.runningBackgroundProcessCount);
}
export function recoveryPaneSafe(pane: string | null, expectedDraft = ''): boolean {
 if (!pane || isBusy(pane) || parsePrompt(pane) || questionSelectorOpen(pane) || feedbackPromptOpen(pane)) return false;
 const box = inputBoxFromPane(pane);
 const norm = (text: string) => text.replace(/\s+/g, ' ').trim();
 return box !== null && norm(box.replace(/^\s*❯[ \u00a0]*/, '')) === norm(expectedDraft);
}

export async function readRecoveryError(path: string, sessionId: string): Promise<RecoveryError | null> {
 let error: RecoveryError | null = null;
 const result = await scanBack<RecoveryError | false>(path, line => {
  let row: any; try { row = JSON.parse(line); } catch { return false; }
  if (!error) {
   if (row.type !== 'user' && row.type !== 'assistant' && row.type !== 'queue-operation' && !(row.type === 'system' && ['continued-in', 'compact_boundary'].includes(row.subtype))) return null;
   error = recoveryError(JSON.stringify({ type: 'user', uuid: 'boundary', message: { content: 'task' } }) + '\n' + line, sessionId);
   return error ? null : false;
  }
  if (row.type !== 'user' || row.isMeta || row.isCompactSummary) return null;
  const c = row.message?.content;
  const text = typeof c === 'string' ? c : Array.isArray(c) ? c.filter((x: any) => x.type === 'text').map((x: any) => x.text).join('\n') : '';
  if (!text || text.startsWith(RECOVERY_PREFIX)) return null;
  return row.uuid ? { ...error, taskId: row.uuid } : false;
 });
 return result || null;
}

export async function explicitlyStopped(sid: string, path: string, hookAt: number | null, errorAt: number): Promise<boolean> {
 if (await interruptStands(sid, path, hookAt)) return true;
 // Stop can leave no transcript row. The existing operation log also survives
 // host restarts, unlike the in-memory interrupt mark. Stop intent wins even
 // when its Escape was not confirmed by the terminal.
 const ops = process.env.LFG_OPS_LOG ?? join(process.cwd(), 'data', 'ops.log');
 for (const file of [ops, `${ops}.1`]) {
  const stopped = await scanBack<boolean>(file, line => {
   let row: any; try { row = JSON.parse(line); } catch { return null; }
   if (Date.parse(row.at) < errorAt) return false;
   return row.sessionId === sid && (row.op === 'interrupt' || row.op === 'close') ? true : null;
  });
  if (stopped) return true;
 }
 return false;
}

export type InspectionDeps = {
 lease: (sid: string) => Promise<LeaseRecord | null>;
 hostId: () => string;
 queue: typeof listQueue;
 pane: (target: string) => Promise<string | null>;
 stopped: typeof explicitlyStopped;
};
const inspection: InspectionDeps = {
 lease: readLease, hostId: () => hostInfo().hostId, queue: listQueue,
 pane: capturePaneAsync, stopped: explicitlyStopped,
};

export async function inspectRecoverySession(s: Session, now = Date.now(), ownQueueId?: string, deps = inspection, expectedDraft = ''): Promise<RecoveryError | null> {
 if (!recoverySessionSafe(s)) return null;
 const sid = s.sessionId!;
 const lease = await deps.lease(sid);
 if (!lease || lease.hostId !== deps.hostId() || !leaseIsFresh(lease, now) || lease.pid !== s.pid || lease.state === 'ended') return null;
 if (deps.queue(sid).some(m => m.id !== ownQueueId && (['pending', 'sending', 'queued'].includes(m.status) || m.updatedAt > (s.last?.ts ?? 0)))) return null;
 const file = Bun.file(s.transcriptPath!);
 const size = file.size;
 const error = await readRecoveryError(s.transcriptPath!, sid);
 if (!error || (s.lastUserAt != null && s.lastUserAt > error.at)) return null;
 if (await deps.stopped(sid, s.transcriptPath!, lease.stateAt ?? null, error.at)) return null;
 const pane = await deps.pane(s.tmuxTarget!);
 if (!recoveryPaneSafe(pane, expectedDraft)) return null;
 // Reject edits made while the pane was being captured.
 if (Bun.file(s.transcriptPath!).size !== size) return null;
 return error;
}

/** Called again by sendq immediately before typing, including after restart. */
export async function recoveryDeliverySafe(s: Session, msg: QueuedMsg, deps = inspection): Promise<boolean> {
 const error = await inspectRecoverySession(s, Date.now(), msg.id, deps);
 return !!error && recoveryClientId(error.id) === msg.clientId;
}

export async function recoverySubmissionSafe(s: Session, msg: QueuedMsg, deps = inspection): Promise<boolean> {
 const error = await inspectRecoverySession(s, Date.now(), msg.id, deps, msg.text);
 return !!error && recoveryClientId(error.id) === msg.clientId;
}

export type RecoveryDeps = {
 dir: string;
 list: () => Promise<Session[]>;
 inspect: (s: Session, now: number) => Promise<RecoveryError | null>;
 send: (sessionId: string, error: RecoveryError) => unknown;
};

async function exclusiveJson(path: string, value: unknown): Promise<boolean> {
 // Publish a complete record atomically, without replacing a concurrent claim.
 // Opening the final path with wx exposes an empty file before write completes.
 const temp = join(dirname(path), `.pending-${randomUUID()}`);
 const handle = await open(temp, 'wx', 0o600);
 try {
  try { await handle.writeFile(JSON.stringify(value)); await handle.sync(); }
  finally { await handle.close(); }
  try { await link(temp, path); return true; }
  catch (e: any) { if (e.code === 'EEXIST') return false; throw e; }
 } finally { await unlink(temp).catch(() => {}); }
}

export async function runRecovery(ctx: TaskContext, deps: RecoveryDeps = production): Promise<TaskResult> {
 const { now, dryRun, log } = ctx;
 let activatedAt = now;
 if (!dryRun) {
  await mkdir(deps.dir, { recursive: true });
  await exclusiveJson(join(deps.dir, 'activation.json'), { at: now });
 }
 try { activatedAt = JSON.parse(await readFile(join(deps.dir, 'activation.json'), 'utf8')).at; }
 catch (e: any) { if (!dryRun || e.code !== 'ENOENT') throw e; }
 if (!Number.isFinite(activatedAt)) throw Error('Invalid recovery activation record');
 const claims: Claim[] = [];
 let names: string[] = [];
 try { names = await readdir(deps.dir); } catch (e: any) { if (e.code !== 'ENOENT') throw e; }
 for (const name of names.filter(n => n.startsWith('claim-'))) {
  // A partial claim after a crash must fail closed, never erase the budget.
  const claim = JSON.parse(await readFile(join(deps.dir, name), 'utf8')) as Claim;
  if (!claim.sessionId || !claim.taskId || !Number.isFinite(claim.at) || !claim.errorId) throw Error('Invalid recovery claim');
  claims.push(claim);
 }
 const sessions = await deps.list();
 const detail: { id: string; from: string; to: string }[] = [];
 let changed = 0;
 for (const s of sessions) {
  if (!s.sessionId) continue;
  const error = await deps.inspect(s, now);
  if (!error || error.at < activatedAt || now - error.at < SETTLE_MS || now - error.at > MAX_AGE_MS) continue;
  if (claims.some(c => c.errorId === error.id)) continue;
  const prior = claims.filter(c => c.sessionId === s.sessionId && c.taskId === error.taskId);
  if (prior.length >= BACKOFF.length) { log(`[recovery] ${s.sessionId}: recovery budget exhausted; needs attention`); continue; }
  const last = Math.max(0, ...prior.map(c => c.at));
  if (now - last < BACKOFF[prior.length]!) continue;
  detail.push({ id: s.sessionId, from: 'Connection interrupted', to: 'Continue original task' });
  if (dryRun) continue;
  // Recheck immediately before claiming. No user/agent activity may supersede
  // the failed turn while filesystem inspection was underway.
  const current = await deps.inspect(s, now);
  if (!current || current.id !== error.id) continue;
  const claim: Claim = { sessionId: s.sessionId, taskId: error.taskId, at: now, errorId: error.id };
  if (!await exclusiveJson(join(deps.dir, `claim-${hash(error.id)}.json`), claim)) continue;
  claims.push(claim);
  try {
   await deps.send(s.sessionId, error);
   changed++;
   log(`[recovery] ${s.sessionId}: continuation queued (attempt ${prior.length + 1}/3)`);
  } catch (e) { log(`[recovery] ${s.sessionId}: delivery uncertain; no automatic resend: ${e}`); }
 }
 return { examined: sessions.length, changed, note: dryRun ? `${detail.length} eligible (dry run)` : `${changed} continuation(s) queued`, detail };
}

const production: RecoveryDeps = {
 dir: DIR,
 list: listSessions,
 inspect: inspectRecoverySession,
 send: (sessionId, error) => enqueueMessage(sessionId,
  `${RECOVERY_PREFIX} Your last turn ended with a connection error. Check completed tool results, files, and external action receipts, then continue the original task from the last confirmed progress. Do not repeat confirmed actions. If an external action has an uncertain result, inspect its state before retrying. Respect the original scope, approvals, budget, and deadline. Stop and report if the task is complete, cancelled, expired, or needs user input.`,
  { clientId: recoveryClientId(error.id) }),
};
export const recoveryStep: AutopilotStep = {
 name: 'recover-connections',
 description: 'Continue live Claude sessions stopped by explicit connection errors',
 run: runRecovery,
};
