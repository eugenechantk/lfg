import { readdir, realpath, stat } from "node:fs/promises";
import { statSync, mkdirSync, type Dirent } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import { PATHS } from "../config.ts";
import { hostInfo } from "../hostinfo.ts";
import { Journal } from "../journal.ts";
import { startJournalPump } from "../journal-pump.ts";
import { codexDelegationSessionIds, notePaneBusy } from "../activity.ts";
import {
  AGENTS_DIR,
  listAgents,
  loadAgent,
  writeAgent,
} from "../agents/registry.ts";
import {
  parseActions,
  readActionsSidecar,
  reportPathFor,
  runAgent,
  type ActionRow,
} from "../agents/runner.ts";
import { executeAction, executeActionsCombined, dispatchSendFixAgent } from "../actions/index.ts";
import {
  listAutoAgents,
  getAutoAgent,
  saveAutoAgent,
  deleteAutoAgent,
  isRunning,
  listFindings,
  updateFinding,
} from "../auto/store.ts";
import { runAutoAgent } from "../auto/runner.ts";
import { startAutoScheduler } from "../auto/scheduler.ts";
import {
  listSessions,
  resolveTranscript,
  recentMessages,
  snapshotMessages,
  messagePage,
  normalizeLineMessages,
  setSessionTitle,
  sessionIdForPid,
  pendingToolPrompt,
  lastUserPromptText,
  listResumable,
  cwdForTranscript,
  modelAliasForTranscript,
  type Session,
  type PendingPrompt,
} from "../sessions.ts";
import {
  capturePaneAsync,
  parsePrompt,
  type PanePrompt,
  answerPrompt,
  dismissPrompt,
  tmuxInterrupt,
  tmuxKillPane,
  tmuxKillSession,
  spawnManagedSession,
  relaunchSessionWithModel,
  spawnManagedCodexSession,
  spawnManagedAisdkSession,
  spawnManagedCodexAisdkSession,
  spawnManagedOpencodeAisdkSession,
  dismissCodexUpdatePrompt,
  panePidForSession,
  isBusy,
} from "../tmux.ts";
import { addManaged, forkLineageForSession, normalizeParentSessionId, patchManaged, removeManaged } from "../managed.ts";
import { PtyBridge, termSessionName } from "../pty.ts";
import { capturePaneScroll, capturePaneEscaped, paneWidth, ensureFolderTrusted } from "../tmux.ts";
import { rootDir, inboxDir, setInbox, createDir } from "../dirs.ts";
import { detectUrls } from "../links.ts";
import type { ServerWebSocket } from "bun";
import { appendCmd as appendAisdkCmd, removeEntry as removeAisdkEntry, readEntry as readAisdkEntry, findEntryByAnyId as findAisdkEntryByAnyId } from "../aisdk-registry.ts";
import { markClosed } from "../closing.ts";
import { assignUser, userRoster } from "../users.ts";
import { acquireLease, ensureLease, foreignFresh, releaseLease } from "../leases.ts";
import { registerDevice, unregisterDevice, deviceCount } from "../push/store.ts";
import { upsertLiveActivityToken } from "../push/liveactivity-store.ts";
import { startPushWatcher, pushConfigured } from "../push/watcher.ts";
import {
  BrowserFrameStore,
  publishBrowserFrame,
} from "../browser-preview.ts";

// Where the user keeps the repos lfg can launch agents into. Scanned for git
// repos at runtime; defaults to ~/repos. The lfg repo itself (PATHS.root) is
// always offered as a target since it is present and trusted.
const REPOS_ROOT = process.env.LFG_REPOS_ROOT ?? join(homedir(), "repos");
const SELF_REPO = PATHS.root;

// Allowlisted Claude models. They land both on a launch argv (--model) and in a
// `/model <id>` slash command we inject mid-session — so an unknown value is a
// hard 400, never a silent fallback. Explicit current IDs are the picker/default
// path; aliases stay accepted for existing clients and transcript-derived resume.
const CLAUDE_MODEL_IDS = [
  "claude-opus-5",
  "claude-fable-5",
  "claude-sonnet-5",
  "claude-haiku-4-5",
];
const CLAUDE_MODEL_ALIASES = ["opus", "fable", "sonnet", "haiku"];
const CLAUDE_MODELS = [...CLAUDE_MODEL_IDS, ...CLAUDE_MODEL_ALIASES];
// Models the "aisdk" session kind accepts through the Claude Code provider.
const AISDK_MODELS = CLAUDE_MODELS;
const CODEX_MODEL_RE = /^[A-Za-z0-9_.:-]{1,80}$/;

function transcriptFamily(path: string): "claude" | "codex" | null {
  const claudeRoot = process.env.LFG_CLAUDE_PROJECTS_DIR ?? join(homedir(), ".claude", "projects");
  const codexRoot = join(process.env.HOME ?? homedir(), ".codex", "sessions");
  if (path.startsWith(`${claudeRoot}/`) || path.includes("/.claude/projects/")) return "claude";
  if (path.startsWith(`${codexRoot}/`) || path.includes("/.codex/sessions/")) return "codex";
  return null;
}

function validateModelForAgent(agent: "claude" | "codex", model: string | undefined): string | null {
  if (!model) return null;
  if (agent === "claude" && !CLAUDE_MODELS.includes(model)) return `unknown model "${model}"`;
  if (agent === "codex" && !CODEX_MODEL_RE.test(model)) return "invalid codex model name";
  return null;
}
import {
  enqueueMessage,
  listQueue,
  retryMessage,
  clearResolved,
  reconcileQueued,
  getMessage,
  removeMessage,
  sendNow,
  startQueuePump,
  setSendqJournal,
  setSendqStore,
  getMessageByClientId,
  recordImmediateMessage,
} from "../sendq.ts";
import { SendqStore } from "../sendq-store.ts";

// Relaunch a closed claude session via `claude --resume <id>` in a fresh managed
// tmux pane, preserving the full conversation. Shared by the explicit
// /api/sessions/resume endpoint and the auto-resume-on-send path (a send to a
// session whose pane was reaped while idle — box reboot, host restart, manual
// close). Claude continues into a NEW sessionId/transcript, which we resolve
// from the pidfile (like /new) and hand back so the client can re-point at it.
type ResumeOutcome =
  | { ok: true; tmuxName: string; cwd: string; newId: string | null; agent: "claude" | "codex"; alreadyLive?: boolean }
  | { ok: false; status: number; error: string; liveOn?: string };

async function resumeClosedSession(opts: {
  sessionId: string;
  model?: string;
  user?: string;
  prompt?: string;
}): Promise<ResumeOutcome> {
  const sessionId = opts.sessionId.trim();
  if (!sessionId) return { ok: false, status: 400, error: "sessionId required" };
  // Already running? Don't double-spawn — point the caller at the live one.
  const live = (await listSessions()).find((s) => s.sessionId === sessionId);
  if (live && (live.agent === "claude" || live.agent === "codex")) {
    const modelError = validateModelForAgent(live.agent, opts.model);
    if (modelError) return { ok: false, status: 400, error: modelError };
    return {
      ok: true,
      tmuxName: live.tmuxName ?? "",
      cwd: live.cwd ?? "",
      newId: sessionId,
      agent: live.agent,
      alreadyLive: true,
    };
  }
  const liveOn = await foreignFresh(sessionId);
  if (liveOn)
    return { ok: false, status: 409, error: "session is live on another host", liveOn };
  const transcript = await resolveTranscript(sessionId);
  if (!transcript) return { ok: false, status: 404, error: "no transcript found for that session" };
  const agent = transcriptFamily(transcript);
  if (!agent) return { ok: false, status: 400, error: "only claude and codex sessions can be resumed" };
  const modelError = validateModelForAgent(agent, opts.model);
  if (modelError) return { ok: false, status: 400, error: modelError };
  const cwd = (await cwdForTranscript(transcript)) ?? SELF_REPO;
  if (agent === "codex") {
    const tmuxName = `lfg-${randomBytes(3).toString("hex")}`;
    const spawnStartedAt = Date.now();
    const r = spawnManagedCodexSession({ name: tmuxName, cwd, resume: sessionId, prompt: opts.prompt });
    if (!r.ok) return { ok: false, status: 502, error: r.error || "failed to resume session" };
    // Codex resume is id-stable. Persist that intended id immediately so every
    // later listSessions()/refreshWatchSet pass binds this pane by known id
    // instead of the create-path skew heuristic.
    addManaged({ tmuxName, cwd, createdAt: spawnStartedAt, agent: "codex", sessionId });
    if (opts.user) assignUser(tmuxName, opts.user);
    for (let i = 0; i < 12; i++) {
      const pid = panePidForSession(tmuxName);
      if (pid) {
        await acquireLease(sessionId, pid);
        break;
      }
      await new Promise((res) => setTimeout(res, 250));
    }
    return { ok: true, tmuxName, cwd, newId: sessionId, agent: "codex" };
  }
  // Relaunch on the model the conversation was last using (read from the
  // transcript) so a resume doesn't silently bump the session to opus.
  const model = opts.model || (await modelAliasForTranscript(transcript)) || undefined;
  const tmuxName = `lfg-${randomBytes(3).toString("hex")}`;
  const r = spawnManagedSession({ name: tmuxName, cwd, model, resume: sessionId, prompt: opts.prompt });
  if (!r.ok) return { ok: false, status: 502, error: r.error || "failed to resume session" };
  addManaged({ tmuxName, cwd, createdAt: Date.now(), agent: "claude" });
  if (opts.user) assignUser(tmuxName, opts.user);
  // Claude resumes into a fresh sessionId/transcript — wait for the pidfile.
  let newId: string | null = null;
  let newPid: number | null = null;
  for (let i = 0; i < 12 && !newId; i++) {
    await new Promise((res) => setTimeout(res, 500));
    const pid = panePidForSession(tmuxName);
    if (pid) {
      newPid = pid;
      newId = sessionIdForPid(pid);
    }
  }
  if (newId && newPid) await acquireLease(newId, newPid);
  return { ok: true, tmuxName, cwd, newId, agent: "claude" };
}

// Fork a claude session into a new branch via `claude --resume <id>
// --fork-session`. Unlike resume, this NEVER dedupes against a live session —
// forking a running conversation is the whole point (branch off whatever's
// flushed to the transcript, leaving the source untouched). Claude mints a new
// sessionId/transcript for the branch, which we resolve from the pidfile and
// hand back so the client can deep-link into the fork.
type ForkOutcome =
  | { ok: true; tmuxName: string; cwd: string; newId: string | null; agent: "claude" | "codex" }
  | { ok: false; status: number; error: string; liveOn?: string };

async function forkSession(opts: {
  sessionId: string;
  model?: string;
  user?: string;
}): Promise<ForkOutcome> {
  const sessionId = opts.sessionId.trim();
  if (!sessionId) return { ok: false, status: 400, error: "sessionId required" };
  const liveOn = await foreignFresh(sessionId);
  if (liveOn)
    return { ok: false, status: 409, error: "session is live on another host", liveOn };
  const transcript = await resolveTranscript(sessionId);
  if (!transcript) return { ok: false, status: 404, error: "no transcript found for that session" };
  const agent = transcriptFamily(transcript);
  if (!agent) return { ok: false, status: 400, error: "only claude and codex sessions can be forked" };
  const modelError = validateModelForAgent(agent, opts.model);
  if (modelError) return { ok: false, status: 400, error: modelError };
  const cwd = (await cwdForTranscript(transcript)) ?? SELF_REPO;
  if (agent === "codex") {
    const tmuxName = `lfg-${randomBytes(3).toString("hex")}`;
    const spawnStartedAt = Date.now();
    const r = spawnManagedCodexSession({
      name: tmuxName,
      cwd,
      model: opts.model,
      resume: sessionId,
      fork: true,
    });
    if (!r.ok) return { ok: false, status: 502, error: r.error || "failed to fork session" };
    // The new id is not known until Codex writes session_meta, but the parent
    // link is exact. Store it before polling so listSessions binds by
    // forked_from_id during the initial wait and on future re-scans.
    addManaged({ tmuxName, cwd, createdAt: spawnStartedAt, agent: "codex", forkedFrom: sessionId });
    if (opts.user) assignUser(tmuxName, opts.user);
    let newId: string | null = null;
    let newPid: number | null = null;
    for (let i = 0; i < CODEX_CREATE_SESSION_BIND_POLLS && !newId; i++) {
      await new Promise((res) => setTimeout(res, CREATE_SESSION_BIND_POLL_MS));
      dismissCodexUpdatePrompt(`${tmuxName}:0.0`);
      const liveFork = (await listSessions()).find((s) => s.tmuxName === tmuxName);
      newId = liveFork?.sessionId ?? null;
      if (newId) newPid = panePidForSession(tmuxName);
    }
    if (newId) {
      patchManaged(tmuxName, { sessionId: newId });
      if (newPid) await acquireLease(newId, newPid);
    }
    return { ok: true, tmuxName, cwd, newId, agent: "codex" };
  }
  // Branch on the model the conversation was last using, unless overridden.
  const model = opts.model || (await modelAliasForTranscript(transcript)) || undefined;
  const forkSourceBytes = statSync(transcript).size;
  const tmuxName = `lfg-${randomBytes(3).toString("hex")}`;
  const r = spawnManagedSession({ name: tmuxName, cwd, model, resume: sessionId, fork: true });
  if (!r.ok) return { ok: false, status: 502, error: r.error || "failed to fork session" };
  addManaged({ tmuxName, cwd, createdAt: Date.now(), agent: "claude" });
  if (opts.user) assignUser(tmuxName, opts.user);
  // The fork gets a fresh sessionId/transcript — wait for the pidfile.
  let newId: string | null = null;
  let newPid: number | null = null;
  for (let i = 0; i < 12 && !newId; i++) {
    await new Promise((res) => setTimeout(res, 500));
    const pid = panePidForSession(tmuxName);
    if (pid) {
      newPid = pid;
      newId = sessionIdForPid(pid);
    }
  }
  if (newId) {
    patchManaged(tmuxName, { sessionId: newId, forkedFrom: sessionId, forkSourceBytes });
    if (newPid) await acquireLease(newId, newPid);
  }
  return { ok: true, tmuxName, cwd, newId, agent: "claude" };
}

const PORT = Number(process.env.LFG_PORT ?? 8766);
// Bind to loopback by default — the UI is meant to be reached over Tailscale
// (via `tailscale serve`), never the public internet. Override LFG_HOST only
// if you understand the exposure.
const HOST = process.env.LFG_HOST ?? "127.0.0.1";
const CREATE_SESSION_BIND_POLL_MS = 500;
const DEFAULT_CREATE_SESSION_BIND_POLLS = 12;
const CODEX_CREATE_SESSION_BIND_POLLS = 28;
const CODEX_CREATE_FALLBACK_WINDOW_MS =
  CODEX_CREATE_SESSION_BIND_POLLS * CREATE_SESSION_BIND_POLL_MS;
const UUID_RE = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;

// ---------- legacy: pre-agents flat reports ----------

async function listLegacyReports() {
  const dir = join(PATHS.data, "reports");
  let files: string[];
  try {
    files = await readdir(dir);
  } catch {
    return [];
  }
  const entries = await Promise.all(
    files
      .filter((f) => f.endsWith(".md") && /^\d{4}-\d{2}-\d{2}\.md$/.test(f))
      .map(async (f) => {
        const s = await stat(join(dir, f));
        return { date: f.replace(/\.md$/, ""), bytes: s.size, mtime: s.mtimeMs };
      }),
  );
  return entries.sort((a, b) => b.date.localeCompare(a.date));
}

async function readLegacyReport(date: string): Promise<string | null> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const f = Bun.file(join(PATHS.data, "reports", `${date}.md`));
  return (await f.exists()) ? await f.text() : null;
}

async function listRepos() {
  let root: string;
  try {
    root = await realpath(REPOS_ROOT);
  } catch {
    root = REPOS_ROOT;
  }
  const repos: Array<{ name: string; cwd: string }> = [];
  const addRepo = async (name: string, cwd: string) => {
    if (repos.some((r) => r.cwd === cwd)) return;
    try {
      await stat(join(cwd, ".git"));
      repos.push({ name, cwd });
    } catch {}
  };
  let entries: Dirent[] = [];
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {}
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
    await addRepo(entry.name, join(root, entry.name));
  }
  // Always offer the lfg repo itself as a target — it is present and trusted.
  await addRepo("lfg", SELF_REPO);
  repos.sort((a, b) => a.name.localeCompare(b.name));
  return repos;
}

// ---------- agent reports ----------

async function listAgentReports(agent: string) {
  const dir = join(PATHS.data, "reports", agent);
  let files: string[];
  try {
    files = await readdir(dir);
  } catch {
    return [];
  }
  const entries = await Promise.all(
    files
      .filter((f) => /^\d{4}-\d{2}-\d{2}\.md$/.test(f))
      .map(async (f) => {
        const s = await stat(join(dir, f));
        return { date: f.replace(/\.md$/, ""), bytes: s.size, mtime: s.mtimeMs };
      }),
  );
  return entries.sort((a, b) => b.date.localeCompare(a.date));
}

async function readAgentReport(agent: string, date: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  if (!/^[a-z0-9_-]+$/.test(agent)) return null;
  const f = Bun.file(reportPathFor(agent, date));
  if (!(await f.exists())) return null;
  const raw = await f.text();
  const parsed = parseActions(agent, date, raw).map((p) => p.id);
  const sidecar = await readActionsSidecar(agent, date);
  const byId = new Map(sidecar.map((s) => [s.id, s] as const));
  const actions = parsed
    .map((id) => byId.get(id))
    .filter((r): r is ActionRow => !!r);
  return { date, raw, actions };
}

// ---------- run lifecycle ----------

type RunState = {
  id: string;
  agent: string;
  date: string;
  startedAt: number;
  status: "running" | "done" | "failed";
  logs: string[];
  result?: unknown;
  error?: string;
  subscribers: Set<(ev: { line?: string; final?: RunState }) => void>;
};

const RUNS = new Map<string, RunState>();
const RUN_TTL_MS = 60 * 60 * 1000;

// Last successful /api/claude/usage payload (60s TTL).
let usageCache: { at: number; data: unknown } | null = null;

function evictOldRuns() {
  const cutoff = Date.now() - RUN_TTL_MS;
  for (const [k, v] of RUNS) if (v.startedAt < cutoff && v.status !== "running") RUNS.delete(k);
}

function emit(state: RunState, ev: { line?: string; final?: RunState }) {
  for (const s of state.subscribers) {
    try {
      s(ev);
    } catch {}
  }
}

async function startRun(agent: string): Promise<RunState> {
  evictOldRuns();
  const id = randomBytes(6).toString("hex");
  const state: RunState = {
    id,
    agent,
    date: new Date().toISOString().slice(0, 10),
    startedAt: Date.now(),
    status: "running",
    logs: [],
    subscribers: new Set(),
  };
  RUNS.set(id, state);

  runAgent(agent, {
    onLog: (line) => {
      state.logs.push(line);
      emit(state, { line });
    },
  })
    .then((r) => {
      state.status = "done";
      state.result = r;
      emit(state, { final: state });
    })
    .catch((e) => {
      state.status = "failed";
      state.error = e instanceof Error ? e.message : String(e);
      emit(state, { final: state });
    });

  return state;
}

// ---------- HTTP helpers ----------


function json(obj: unknown, init?: ResponseInit) {
  return new Response(JSON.stringify(obj), {
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

function err(status: number, message: string, extra?: Record<string, unknown>) {
  return json({ error: message, ...(extra ?? {}) }, { status });
}

type CodexCreateFallbackCandidate = {
  id: string;
  cwd: string | null;
  createdAt: number | null;
};

export function pickSingleCodexCreateFallbackCandidate(args: {
  cwd: string;
  spawnedAt: number;
  candidates: CodexCreateFallbackCandidate[];
  claimedIds?: Set<string>;
}): CodexCreateFallbackCandidate | null {
  const maxCreatedAt = args.spawnedAt + CODEX_CREATE_FALLBACK_WINDOW_MS;
  const matches = args.candidates.filter(
    (candidate) =>
      candidate.cwd === args.cwd &&
      candidate.createdAt != null &&
      candidate.createdAt >= args.spawnedAt &&
      candidate.createdAt <= maxCreatedAt &&
      !args.claimedIds?.has(candidate.id),
  );
  return matches.length === 1 ? matches[0] : null;
}

function codexSessionsDir(): string {
  return join(process.env.HOME ?? homedir(), ".codex", "sessions");
}

async function codexCreateFallbackCandidates(): Promise<CodexCreateFallbackCandidate[]> {
  const out: CodexCreateFallbackCandidate[] = [];
  let years: string[];
  try {
    years = await readdir(codexSessionsDir());
  } catch {
    return out;
  }
  for (const year of years) {
    let months: string[];
    try {
      months = await readdir(join(codexSessionsDir(), year));
    } catch {
      continue;
    }
    for (const month of months) {
      let days: string[];
      try {
        days = await readdir(join(codexSessionsDir(), year, month));
      } catch {
        continue;
      }
      for (const day of days) {
        let files: string[];
        try {
          files = await readdir(join(codexSessionsDir(), year, month, day));
        } catch {
          continue;
        }
        for (const file of files) {
          if (!file.endsWith(".jsonl")) continue;
          const path = join(codexSessionsDir(), year, month, day, file);
          try {
            const first = (await Bun.file(path).slice(0, 128 * 1024).text()).split("\n")[0];
            if (!first) continue;
            const row = JSON.parse(first) as {
              type?: string;
              payload?: { id?: string; cwd?: string; timestamp?: string };
            };
            const id = row.payload?.id ?? path.match(UUID_RE)?.[0] ?? null;
            if (row.type !== "session_meta" || !id) continue;
            const createdAt = row.payload?.timestamp ? Date.parse(row.payload.timestamp) : NaN;
            out.push({
              id,
              cwd: row.payload?.cwd ?? null,
              createdAt: Number.isFinite(createdAt) ? createdAt : null,
            });
          } catch {}
        }
      }
    }
  }
  return out;
}

async function messagePageFromSnapshot(
  path: string,
  opts: { before?: number | null; limit?: number; maxBytes: number | null },
): Promise<{
  messages: Awaited<ReturnType<typeof snapshotMessages>>;
  nextBefore: number | null;
  total: number;
}> {
  const all = await snapshotMessages(path, 0, { maxBytes: opts.maxBytes });
  const limit = Math.max(1, Math.min(500, opts.limit ?? 220));
  const rawEnd = opts.before ?? all.length;
  const end = Math.max(0, Math.min(all.length, rawEnd));
  const start = Math.max(0, end - limit);
  return {
    messages: all.slice(start, end),
    nextBefore: start > 0 ? start : null,
    total: all.length,
  };
}

export async function messagesResponseForSession(sid: string, url: URL): Promise<Response> {
  let tp = await resolveTranscript(sid);
  let forkPending = false;
  let forkSourceBytes: number | null = null;
  if (!tp) {
    const lineage = forkLineageForSession(sid);
    if (!lineage?.forkedFrom) return err(404, "session transcript not found");
    tp = await resolveTranscript(lineage.forkedFrom);
    if (!tp) return err(404, "session transcript not found");
    forkPending = true;
    forkSourceBytes = lineage.forkSourceBytes ?? null;
  }

  if (url.searchParams.get("page") === "backward") {
    const rawLimit = parseInt(url.searchParams.get("limit") ?? "220", 10);
    const rawBefore = url.searchParams.get("before");
    const before =
      rawBefore == null ? null : Math.max(0, parseInt(rawBefore, 10) || 0);
    const page = forkPending
      ? await messagePageFromSnapshot(tp, {
          before,
          limit: Number.isFinite(rawLimit) ? rawLimit : 220,
          maxBytes: forkSourceBytes,
        })
      : await messagePage(tp, {
          before,
          limit: Number.isFinite(rawLimit) ? rawLimit : 220,
        });
    return json({
      id: sid,
      total: page.total,
      nextBefore: page.nextBefore,
      messages: page.messages,
      ...(forkPending ? { forkPending: true } : {}),
    });
  }

  const full = url.searchParams.get("full") === "1";
  const rawLimit = parseInt(url.searchParams.get("limit") ?? (full ? "0" : "30"), 10);
  const lim = full
    ? Math.max(0, Math.min(20000, Number.isFinite(rawLimit) ? rawLimit : 0))
    : Math.min(200, Math.max(1, Number.isFinite(rawLimit) ? rawLimit : 30));
  const messages = forkPending
    ? await snapshotMessages(tp, lim, { maxBytes: forkSourceBytes })
    : await recentMessages(tp, lim, { maxBytes: full ? null : undefined });
  return json({
    id: sid,
    messages,
    ...(forkPending ? { forkPending: true } : {}),
  });
}

export type LiveStreamPane = { sid: string; tp: string; target: string | null };

export async function liveStreamInitialState(
  ids: string[],
  deps: {
    listSessions?: () => Promise<Session[]>;
    resolveTranscript?: (sid: string) => Promise<string | null>;
    forkLineageForSession?: (sid: string) => unknown;
  } = {},
): Promise<{ panes: LiveStreamPane[]; pending: Set<string>; sessions: Session[] }> {
  const listSessionsFn = deps.listSessions ?? listSessions;
  const resolveTranscriptFn = deps.resolveTranscript ?? resolveTranscript;
  const forkLineageForSessionFn = deps.forkLineageForSession ?? forkLineageForSession;
  const sessions = await listSessionsFn();
  const pending = new Set<string>();
  const panes = (
    await Promise.all(
      ids.map(async (sid) => {
        const tp = await resolveTranscriptFn(sid);
        if (!tp) {
          if (forkLineageForSessionFn(sid)) pending.add(sid);
          return null;
        }
        const target = sessions.find((s) => s.sessionId === sid)?.tmuxTarget ?? null;
        return { sid, tp, target };
      }),
    )
  ).filter((p): p is LiveStreamPane => !!p);
  return { panes, pending, sessions };
}

export async function attachPendingForkTranscripts(args: {
  pending: Set<string>;
  panes: LiveStreamPane[];
  sessions: Session[];
  offsets: Map<string, number>;
  send: (s: string) => void;
  pollOne?: (p: LiveStreamPane) => void | Promise<void>;
  queueOne?: (p: { sid: string }) => void | Promise<void>;
  listSessions?: () => Promise<Session[]>;
  resolveTranscript?: (sid: string) => Promise<string | null>;
}): Promise<number> {
  if (!args.pending.size) return 0;
  const resolveTranscriptFn = args.resolveTranscript ?? resolveTranscript;
  let sessions = args.sessions;
  if (args.listSessions) {
    sessions = await args.listSessions().catch(() => args.sessions);
  }
  let attached = 0;
  for (const sid of [...args.pending]) {
    const tp = await resolveTranscriptFn(sid);
    if (!tp) continue;
    const target = sessions.find((s) => s.sessionId === sid)?.tmuxTarget
      ?? args.sessions.find((s) => s.sessionId === sid)?.tmuxTarget
      ?? null;
    const pane = { sid, tp, target };
    args.pending.delete(sid);
    args.panes.push(pane);
    args.offsets.set(sid, Bun.file(tp).size);
    args.send(`event: reset\ndata: ${JSON.stringify({ sid })}\n\n`);
    await args.pollOne?.(pane);
    await args.queueOne?.(pane);
    attached++;
  }
  return attached;
}

// Compact, spoken-summary-friendly snapshot of every live session, injected into
// the voice orchestrator's spawn prompt so its FIRST reply can be a proactive
// status briefing with no tool-call round-trip. Each session is classified:
//   BLOCKED  — sitting on a permission / plan / trust selector (needs the user NOW)
//   WORKING  — mid-turn
//   IDLE     — not busy, no pending prompt
// Blocked sessions carry the prompt question + option labels so she can name what
// the user has to decide. Built BEFORE the voice session is spawned, so it never
// lists itself.
async function voiceStatusSnapshot(): Promise<string> {
  let sessions;
  try {
    sessions = await listSessions();
  } catch {
    return "(session list unavailable)";
  }
  if (!sessions.length) return "(no sessions running)";
  const now = Date.now();
  const ago = (t: number | null): string => {
    if (!t) return "";
    const s = Math.max(0, Math.round((now - t) / 1000));
    if (s < 60) return `${s}s ago`;
    const m = Math.round(s / 60);
    if (m < 60) return `${m}m ago`;
    return `${Math.round(m / 60)}h ago`;
  };
  const clip = (t: string, n: number) => {
    const c = t.replace(/\s+/g, " ").trim();
    return c.length > n ? c.slice(0, n - 1).trimEnd() + "…" : c;
  };
  const lines: string[] = [];
  for (const s of sessions) {
    // Titles are often the whole kickoff prompt — clip hard so a line reads as a
    // label, not a paragraph.
    const name = clip(s.title || s.tmuxName || s.sessionId?.slice(0, 8) || "session", 60);
    const who = s.assignedUser ? ` [${s.assignedUser}]` : "";
    let status = "IDLE";
    let detail = "";
    if (s.tmuxTarget) {
      const pane = await capturePaneAsync(s.tmuxTarget);
      const tp = s.sessionId ? await resolveTranscript(s.sessionId) : null;
      const prompt = await resolveSessionPrompt(tp, pane);
      if (prompt) {
        status = "BLOCKED";
        const opts = prompt.options
          .map((o) => o.label)
          .filter(Boolean)
          .slice(0, 4)
          .join(" / ");
        detail = ` — needs an answer: "${clip(prompt.question, 100)}"${opts ? ` (${opts})` : ""}`;
      } else if (pane && isBusy(pane)) {
        status = "WORKING";
      }
    }
    // Skip "last ask" when it just restates the (clipped) title — common for the
    // agent sessions whose title IS their first prompt.
    const last = clip(s.lastUserText || "", 100);
    const redundant = last && name.replace(/…$/, "").startsWith(last.slice(0, 30));
    const lastBit = last && !redundant ? ` last ask: "${last}"` : "";
    const when = ago(s.lastActivityAt);
    lines.push(`- ${name}${who}: ${status}${detail}.${lastBit}${when ? ` (${when})` : ""}`);
  }
  return lines.join("\n");
}

// Best available interactive prompt for a session. Prefers a structured
// AskUserQuestion read from the transcript (exact text, survives the preview /
// multi-select / wrapped layouts the pane scraper can't follow), and falls back
// to the pane-scraped selector for prompts that only live in the TUI —
// permission, plan-approval (ExitPlanMode) and trust dialogs. Both shapes share
// { question, options:[{index,label,selected}] }, so the SSE `prompt` event and
// the client render either identically.
async function resolveSessionPrompt(
  tp: string | null,
  pane: string | null,
): Promise<PanePrompt | PendingPrompt | null> {
  if (tp) {
    const pending = await pendingToolPrompt(tp);
    if (pending) return pending;
  }
  if (!pane) return null;
  // Pass the last user turn so the pane scraper can tell a scrolled-off assistant
  // preamble apart from the user's own scrolled-off prompt when surfacing context.
  const lastUser = tp ? await lastUserPromptText(tp).catch(() => null) : null;
  return parsePrompt(pane, lastUser ?? undefined);
}

function sseHeaders(): Record<string, string> {
  return {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache, no-transform",
    Connection: "keep-alive",
    "X-Accel-Buffering": "no",
  };
}

// ---------- server ----------

// Per-socket state for the browser terminal: which tmux session it attaches to
// and the initial geometry the client reported at connect time.
type TermSocketData = { sessionName: string; cols: number; rows: number };

// Live PTY bridges keyed by their websocket, so message/close handlers can find
// the bridge to write to / tear down.
const termBridges = new WeakMap<object, PtyBridge>();

// Parse a terminal dimension from a query param, clamped to a sane range so a
// bogus value can't allocate an absurd pty winsize.
function clampDim(raw: string | null, fallback: number): number {
  const n = parseInt(raw ?? "", 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(1, Math.min(500, n));
}

function startLeaseHeartbeat(): () => void {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const loop = async () => {
    if (stopped) return;
    try {
      const sessions = await listSessions();
      for (const s of sessions) {
        if (stopped) return;
        // ensure, not renew: `renewLease` no-ops unless the lease is already
        // ours, so sessions lfg ADOPTED rather than spawned never got one (7 of
        // 16 on this machine). That is fatal once `closed` means "no fresh
        // lease" — a leaseless running session would read as ended. Driving it
        // from enumeration removes the "remember to acquire" step entirely.
        if (s.sessionId) await ensureLease(s.sessionId, s.pid);
      }
    } catch {}
    if (!stopped) timer = setTimeout(loop, 30_000);
  };
  timer = setTimeout(loop, 1_000);
  return () => {
    stopped = true;
    if (timer) clearTimeout(timer);
  };
}

export async function cmdServe() {
  // Event journal + the one global session pump: the single live-delivery path.
  // The per-connection pumps behind /api/live/stream and /api/sessions/:id/stream
  // are gone along with the web client that was their last consumer, so live
  // delivery costs O(sessions) rather than O(connections x sessions), and a
  // busy/prompt fix lands in one place instead of two. See src/journal.ts.
  const journalPath = join(PATHS.data, "journal.db");
  const journal = Journal.open(journalPath);
  const browserFrames = new BrowserFrameStore();
  setSendqJournal(journal);
  setSendqStore(SendqStore.open(journalPath));
  startJournalPump(journal, {
    resolvePrompt: (tp, pane) => resolveSessionPrompt(tp, pane),
    browserFrames,
  });
  startLeaseHeartbeat();
  const ensurePushWatcher = () =>
    startPushWatcher((l) => console.log(l), {
      head: () => journal.head(),
      hostId: () => hostInfo().hostId,
      hostName: () => hostInfo().hostName,
    });

  const server = Bun.serve({
    port: PORT,
    hostname: HOST,
    idleTimeout: 240,
    websocket: {
      // The browser terminal: each socket owns a PTY attached to a persistent
      // tmux shell session. Input arrives as binary frames (raw keystrokes);
      // text frames are JSON control messages (resize). Output is streamed back
      // as binary frames — the full raw VT byte stream a faithful renderer wants.
      idleTimeout: 600,
      open(ws: ServerWebSocket<TermSocketData>) {
        try {
          const { sessionName, cols, rows } = ws.data;
          const bridge = new PtyBridge(
            ["tmux", "new-session", "-A", "-s", sessionName],
            { cols, rows, cwd: homedir() },
          );
          bridge.onData((chunk) => {
            try {
              ws.send(chunk);
            } catch {}
          });
          bridge.onExit(() => {
            try {
              ws.close();
            } catch {}
          });
          termBridges.set(ws, bridge);
        } catch (e) {
          try {
            ws.send(`\r\n[lfg] failed to open terminal: ${(e as Error).message}\r\n`);
            ws.close();
          } catch {}
        }
      },
      message(ws: ServerWebSocket<TermSocketData>, message) {
        const bridge = termBridges.get(ws);
        if (!bridge) return;
        if (typeof message === "string") {
          // Control channel (resize). Anything unparseable is ignored.
          try {
            const ctrl = JSON.parse(message) as {
              t?: string;
              cols?: number;
              rows?: number;
            };
            if (ctrl.t === "resize" && ctrl.cols && ctrl.rows)
              bridge.resize(ctrl.cols, ctrl.rows);
          } catch {}
          return;
        }
        // Binary frame = raw keystrokes.
        bridge.write(message as Uint8Array);
      },
      close(ws: ServerWebSocket<TermSocketData>) {
        const bridge = termBridges.get(ws);
        termBridges.delete(ws);
        // Tears down our attach client; the tmux session itself persists so the
        // shell (and any in-flight OAuth / long command) survives a reconnect.
        bridge?.close();
      },
    },
    // Backstop for any uncaught throw in fetch(). Without this Bun returns a
    // bare, unstructured 500 (the flakey list-view 500s traced to a spawn-storm
    // RangeError escaping listSessions()). Return structured JSON instead so the
    // client sees a real error shape, and log it for diagnosis.
    error(e: Error) {
      console.error(`[serve] unhandled fetch error: ${e?.stack ?? e}`);
      return new Response(JSON.stringify({ error: "internal error" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    },
    async fetch(req, server) {
      const url = new URL(req.url);
      const path = url.pathname;

      // Latest browser screenshot for a session. Metadata rides the durable SSE
      // journal; the potentially-large bytes stay process-local and are fetched
      // only by a detail screen that is actually showing the preview.
      if (path === "/api/browser/frame" && req.method === "GET") {
        const sessionId = url.searchParams.get("sessionId");
        if (!sessionId) return err(400, "sessionId query param required");
        return browserFrames.response(sessionId, url.searchParams.get("frameId"));
      }

      if (path === "/api/browser/frame/meta" && req.method === "GET") {
        const sessionId = url.searchParams.get("sessionId");
        if (!sessionId) return err(400, "sessionId query param required");
        return browserFrames.metadataResponse(sessionId);
      }

      // Prototype seam for visible end-to-end verification. Production frames
      // enter through transcript extraction above; this endpoint exercises the
      // identical journal + image-fetch path with a known screenshot.
      if (path === "/api/browser/frame" && req.method === "POST") {
        const sessionId = url.searchParams.get("sessionId");
        if (!sessionId) return err(400, "sessionId query param required");
        const contentType = (req.headers.get("content-type") ?? "").split(";")[0];
        const data = new Uint8Array(await req.arrayBuffer());
        const meta = publishBrowserFrame(journal, browserFrames, sessionId, {
          data,
          contentType,
          source: "prototype",
        });
        if (!meta) return err(400, "unsupported, empty, oversized, or duplicate frame");
        return json(meta, { status: 201 });
      }

      // ---- browser terminal (websocket upgrade) ----
      if (path === "/api/term") {
        const sessionName = termSessionName(url.searchParams.get("session") || "main");
        const cols = clampDim(url.searchParams.get("cols"), 80);
        const rows = clampDim(url.searchParams.get("rows"), 24);
        const ok = server.upgrade(req, {
          data: { sessionName, cols, rows },
        });
        if (ok) return undefined; // upgraded — Bun takes over the socket
        return err(400, "expected a websocket upgrade");
      }

      // Detect links in the terminal for the tappable-chip UI. A long URL is
      // wrapped across rows in the rendered terminal (and often hard-wrapped by
      // the app, so tmux -J can't help). We reconstruct full URLs from the pane
      // by stitching full-width rows, and also read any OSC 8 hyperlink targets.
      if (path === "/api/term/scan" && req.method === "GET") {
        const target = termSessionName(url.searchParams.get("session") || "main");
        const plain = capturePaneScroll(target);
        if (plain == null) return json({ urls: [] });
        const urls = detectUrls({
          plain,
          escaped: capturePaneEscaped(target) ?? undefined,
          width: paneWidth(target) ?? 80,
        });
        return json({ urls });
      }


      // ---- voice TTS proxy: forward to the self-hosted SuperTonic service on
      // the control-plane box. The token + upstream URL live server-side (.env)
      // so the browser never sees them; the client just plays the returned WAV.
      if (path === "/api/voice/tts" && req.method === "POST") {
        const up = process.env.TTS_UPSTREAM;
        const tok = process.env.TTS_TOKEN;
        if (!up || !tok) return err(503, "tts not configured");
        const body = (await req.json().catch(() => null)) as {
          text?: string;
          voice?: string;
        } | null;
        const text = body?.text?.trim();
        if (!text) return err(400, "expected { text }");
        try {
          const r = await fetch(`${up}/tts`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${tok}`,
            },
            body: JSON.stringify({ text, voice: body?.voice || "F1" }),
            signal: AbortSignal.timeout(30000),
          });
          if (!r.ok) return err(502, `tts upstream ${r.status}`);
          return new Response(r.body, {
            headers: { "Content-Type": "audio/wav", "Cache-Control": "no-store" },
          });
        } catch {
          return err(502, "tts upstream unreachable");
        }
      }

      // ---- voice STT proxy: forward uploaded WAV audio to the self-hosted
      // faster-whisper service; returns { text }. Keeps the device thin (no
      // local Whisper model).
      if (path === "/api/voice/stt" && req.method === "POST") {
        const up = process.env.TTS_UPSTREAM;
        const tok = process.env.TTS_TOKEN;
        if (!up || !tok) return err(503, "stt not configured");
        const audio = await req.arrayBuffer();
        if (!audio.byteLength) return err(400, "empty audio");
        try {
          const r = await fetch(`${up}/stt`, {
            method: "POST",
            headers: {
              "Content-Type": "application/octet-stream",
              Authorization: `Bearer ${tok}`,
            },
            body: audio,
            signal: AbortSignal.timeout(30000),
          });
          if (!r.ok) return err(502, `stt upstream ${r.status}`);
          return new Response(r.body, { headers: { "Content-Type": "application/json" } });
        } catch {
          return err(502, "stt upstream unreachable");
        }
      }

      // ---- voice speaker-ID proxy: forward uploaded WAV to the upstream
      // /identify (resemblyzer) and return { embedding }. The client compares
      // the embedding (cosine) against its enrolled refs in localStorage to gate
      // barge-ins to known speakers — keeps refs on-device, box stays stateless.
      if (path === "/api/voice/identify" && req.method === "POST") {
        const up = process.env.TTS_UPSTREAM;
        const tok = process.env.TTS_TOKEN;
        if (!up || !tok) return err(503, "identify not configured");
        const audio = await req.arrayBuffer();
        if (!audio.byteLength) return err(400, "empty audio");
        try {
          const r = await fetch(`${up}/identify`, {
            method: "POST",
            headers: {
              "Content-Type": "application/octet-stream",
              Authorization: `Bearer ${tok}`,
            },
            body: audio,
            signal: AbortSignal.timeout(30000),
          });
          if (!r.ok) return err(502, `identify upstream ${r.status}`);
          return new Response(r.body, { headers: { "Content-Type": "application/json" } });
        } catch {
          return err(502, "identify upstream unreachable");
        }
      }

      // ---- extension backend proxy (optional, config-driven) ----
      // A same-origin reverse proxy for runtime UI extensions that must call a
      // private backend WITHOUT shipping its token to the browser. Fully driven
      // by env (no defaults, no hardcoded hosts) — builds that set nothing get
      // no proxy:
      //   LFG_PROXY_PREFIX    path prefix to match (e.g. "/_ext")
      //   LFG_PROXY_UPSTREAM  upstream origin to forward to
      //   LFG_PROXY_TOKEN     bearer token injected server-side
      //   LFG_PROXY_ALLOW     comma-sep allowed upstream path prefixes (empty = all)
      const proxyPrefix = process.env.LFG_PROXY_PREFIX;
      if (proxyPrefix && path.startsWith(proxyPrefix + "/")) {
        const upstream = (process.env.LFG_PROXY_UPSTREAM || "").replace(/\/$/, "");
        const tok = process.env.LFG_PROXY_TOKEN || "";
        if (!upstream || !tok) return err(503, "proxy not configured");
        const upstreamPath = path.slice(proxyPrefix.length);
        const allow = (process.env.LFG_PROXY_ALLOW || "")
          .split(",")
          .map((s) => s.trim())
          .filter(Boolean);
        if (allow.length && !allow.some((p) => upstreamPath.startsWith(p))) {
          return err(403, "forbidden path");
        }
        try {
          const r = await fetch(`${upstream}${upstreamPath}${url.search}`, {
            method: req.method,
            headers: {
              "Content-Type": req.headers.get("content-type") || "application/json",
              Authorization: `Bearer ${tok}`,
            },
            body: req.method === "GET" || req.method === "HEAD" ? undefined : await req.text(),
            signal: AbortSignal.timeout(30000),
          });
          return new Response(r.body, {
            status: r.status,
            headers: {
              "Content-Type": r.headers.get("content-type") || "application/json",
              "Cache-Control": "no-store",
            },
          });
        } catch {
          return err(502, "proxy upstream unreachable");
        }
      }

      // ---- legacy flat reports (for back-compat with old UI bookmarks) ----
      if (path === "/api/reports") return json({ reports: await listLegacyReports() });
      {
        const m = path.match(/^\/api\/reports\/(\d{4}-\d{2}-\d{2})$/);
        if (m) {
          const raw = await readLegacyReport(m[1]);
          if (raw === null) return err(404, "not found");
          return json({ date: m[1], raw });
        }
      }

      // ---- agents ----
      if (path === "/api/agents") {
        const agents = await listAgents();
        const out = await Promise.all(
          agents.map(async (a) => {
            const reps = await listAgentReports(a.name);
            return {
              name: a.name,
              title: a.frontmatter.title ?? a.name,
              enabled: a.frontmatter.enabled !== false,
              inputCount: a.frontmatter.inputs?.length ?? 0,
              lastReport: reps[0]
                ? { date: reps[0].date, bytes: reps[0].bytes, mtime: reps[0].mtime }
                : null,
            };
          }),
        );
        return json({ agents: out });
      }

      {
        const m = path.match(/^\/api\/agents\/([a-z0-9_-]+)$/);
        if (m) {
          const name = m[1];
          if (req.method === "GET") {
            try {
              const a = await loadAgent(name);
              return json({
                name: a.name,
                filePath: a.filePath,
                frontmatter: a.frontmatter,
                body: a.body,
                raw: a.raw,
              });
            } catch (e) {
              return err(404, e instanceof Error ? e.message : String(e));
            }
          }
          if (req.method === "PUT") {
            const body = (await req.json().catch(() => null)) as { content?: unknown } | null;
            if (!body || typeof body.content !== "string")
              return err(400, "expected { content: string }");
            try {
              const a = await writeAgent(name, body.content);
              return json({ ok: true, name: a.name });
            } catch (e) {
              return err(400, e instanceof Error ? e.message : String(e));
            }
          }
          return err(405, "method not allowed");
        }
      }

      {
        const m = path.match(/^\/api\/agents\/([a-z0-9_-]+)\/reports$/);
        if (m) {
          const reps = await listAgentReports(m[1]);
          return json({ agent: m[1], reports: reps });
        }
      }

      {
        const m = path.match(
          /^\/api\/agents\/([a-z0-9_-]+)\/reports\/(\d{4}-\d{2}-\d{2})$/,
        );
        if (m) {
          const r = await readAgentReport(m[1], m[2]);
          if (!r) return err(404, "not found");
          return json(r);
        }
      }

      // ---- auto agents (streamlined: prompt + schedule → findings) ----
      if (path === "/api/auto/agents") {
        if (req.method === "GET") {
          const agents = await listAutoAgents();
          return json({
            agents: agents.map((a) => ({ ...a, running: isRunning(a.id) })),
            tz: process.env.LFG_SCHED_TZ ?? "Asia/Hong_Kong",
          });
        }
        if (req.method === "POST") {
          const b = (await req.json().catch(() => null)) as {
            id?: string;
            name?: string;
            prompt?: string;
            schedule?: string;
            enabled?: boolean;
            cwd?: string;
            tools?: string[];
          } | null;
          if (!b?.name || !b?.prompt || !b?.schedule) {
            return err(400, "name, prompt and schedule are required");
          }
          const agent = await saveAutoAgent({
            id: b.id,
            name: b.name,
            prompt: b.prompt,
            schedule: b.schedule,
            enabled: b.enabled !== false,
            cwd: b.cwd,
            tools: Array.isArray(b.tools) ? b.tools : undefined,
          });
          return json({ agent });
        }
      }
      {
        const m = path.match(/^\/api\/auto\/agents\/([a-z0-9_-]+)$/);
        if (m && req.method === "DELETE") {
          await deleteAutoAgent(m[1]);
          return json({ ok: true });
        }
      }
      {
        const m = path.match(/^\/api\/auto\/agents\/([a-z0-9_-]+)\/run$/);
        if (m && req.method === "POST") {
          const agent = await getAutoAgent(m[1]);
          if (!agent) return err(404, "unknown auto agent");
          // fire-and-forget; the finding surfaces via the findings poll
          void runAutoAgent(agent, (l) => console.log(l)).catch((e) =>
            console.error("[auto] manual run failed:", e),
          );
          return json({ ok: true });
        }
      }
      if (path === "/api/auto/findings" && req.method === "GET") {
        const status = url.searchParams.get("status") || undefined;
        return json({ findings: await listFindings(status) });
      }
      {
        const m = path.match(/^\/api\/auto\/findings\/([0-9a-f]+)$/);
        if (m && req.method === "POST") {
          const b = (await req.json().catch(() => null)) as {
            status?: "open" | "dismissed" | "session" | "read";
            sessionId?: string;
          } | null;
          const patch: { status?: "open" | "dismissed" | "session" | "read"; sessionId?: string } = {};
          if (b?.status) patch.status = b.status;
          if (b?.sessionId) patch.sessionId = b.sessionId;
          const f = await updateFinding(m[1], patch);
          if (!f) return err(404, "unknown finding");
          return json({ finding: f });
        }
      }

      // ---- runs ----
      {
        const m = path.match(/^\/api\/agents\/([a-z0-9_-]+)\/run$/);
        if (m && req.method === "POST") {
          try {
            await loadAgent(m[1]);
          } catch (e) {
            return err(404, e instanceof Error ? e.message : String(e));
          }
          const state = await startRun(m[1]);
          return json({ runId: state.id, agent: state.agent, date: state.date });
        }
      }

      {
        const m = path.match(/^\/api\/agents\/([a-z0-9_-]+)\/runs\/([0-9a-f]+)$/);
        if (m) {
          const state = RUNS.get(m[2]);
          if (!state) return err(404, "run not found");
          if (req.headers.get("accept")?.includes("text/event-stream")) {
            const stream = new ReadableStream({
              start(controller) {
                const send = (ev: { line?: string; final?: RunState }) => {
                  if (ev.line) {
                    controller.enqueue(
                      `event: log\ndata: ${JSON.stringify(ev.line)}\n\n`,
                    );
                  }
                  if (ev.final) {
                    controller.enqueue(
                      `event: ${ev.final.status}\ndata: ${JSON.stringify({
                        status: ev.final.status,
                        result: ev.final.result,
                        error: ev.final.error,
                      })}\n\n`,
                    );
                    controller.close();
                  }
                };
                for (const l of state.logs) send({ line: l });
                if (state.status !== "running") {
                  send({ final: state });
                  return;
                }
                state.subscribers.add(send);
              },
              cancel() {
                // sub gets evicted with the run eventually
              },
            });
            return new Response(stream, { headers: sseHeaders() });
          }
          // plain JSON status
          return json({
            id: state.id,
            agent: state.agent,
            status: state.status,
            logs: state.logs,
            result: state.result,
            error: state.error,
          });
        }
      }

      // ---- actions ----
      {
        const m = path.match(
          /^\/api\/actions\/([a-z0-9_-]+)\/(\d{4}-\d{2}-\d{2})$/,
        );
        if (m && req.method === "GET") {
          const rows = await readActionsSidecar(m[1], m[2]);
          return json({ agent: m[1], date: m[2], actions: rows });
        }
      }

      if (path === "/api/actions/execute" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          agent?: string;
          date?: string;
          id?: string;
          force?: boolean;
        } | null;
        if (!body?.agent || !body.date || !body.id)
          return err(400, "expected { agent, date, id }");
        try {
          const r = await executeAction(body.agent, body.date, body.id, {
            force: !!body.force,
          });
          return json(r);
        } catch (e) {
          return err(400, e instanceof Error ? e.message : String(e));
        }
      }

      // Run several selected actions inside ONE agent session (one worktree),
      // instead of one dispatched agent per action.
      if (path === "/api/actions/execute-combined" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          agent?: string;
          date?: string;
          ids?: string[];
          force?: boolean;
        } | null;
        if (!body?.agent || !body.date || !Array.isArray(body.ids) || body.ids.length === 0)
          return err(400, "expected { agent, date, ids: string[] }");
        try {
          const r = await executeActionsCombined(body.agent, body.date, body.ids, {
            force: !!body.force,
          });
          return json(r);
        } catch (e) {
          return err(400, e instanceof Error ? e.message : String(e));
        }
      }

      // ---- multi-user (session tagging) ----
      if (path === "/api/users") {
        return json({ users: userRoster() });
      }

      // ---- host identity (multi-host) ----
      // The iOS client fans out to every configured host and uses this to label
      // sessions by machine and dedupe a host reached via two URLs.
      if (path === "/api/info") {
        return json(hostInfo());
      }

      // ---- keepalive ----
      // Tiny 200 the client pings every ~10s per live host: keeps carrier-NAT
      // mappings on the phone's cellular path warm (idle UDP bindings expire in
      // ~30s and their expiry is what forces Tailscale re-punch flaps), doubles
      // as an RTT sample, and detects a dead path in both directions fast.
      if (path === "/api/ping") {
        return json({ ok: true, seq: journal.head(), ts: Date.now() });
      }

      // ---- journaled event page (cursor-resumable, non-streaming) ----
      // GET /api/events/page?since=<seq>&limit=<n>. Mirrors /api/events replay
      // semantics for background wakes where iOS has a short fetch window and
      // wants one bounded JSON page instead of holding an SSE stream.
      if (path === "/api/events/page") {
        const since = Number(url.searchParams.get("since") ?? "0");
        const cursor = Number.isFinite(since) && since >= 0 ? Math.floor(since) : 0;
        const rawLimit = Number(url.searchParams.get("limit") ?? "200");
        const limit = Math.max(
          1,
          Math.min(1000, Number.isFinite(rawLimit) ? Math.floor(rawLimit) : 200),
        );
        const head = journal.head();
        if (!journal.canServe(cursor)) {
          console.log(`[events] page since=${cursor} limit=${limit} head=${head} served=0`);
          return json({ events: [], head, canServe: false });
        }
        const events = journal.since(cursor, limit);
        console.log(
          `[events] page since=${cursor} limit=${limit} head=${head} served=${events.length}`,
        );
        return json({ events, head, canServe: true });
      }

      // ---- journaled event stream (cursor-resumable) ----
      // GET /api/events?since=<seq>. Replays every journaled event after the
      // client's cursor, then streams live — one stream covers ALL sessions on
      // this host (no ids= selection, so nothing ever needs rebuilding when
      // sessions open/close/transfer). SSE `id:` carries the seq; the client
      // persists the last-applied seq per host and resumes losslessly. An
      // unserviceable cursor (predates retention, or from a previous journal
      // lifetime) gets `event: resync` — the client full-refreshes via REST and
      // resets its cursor to the accompanying head.
      if (path === "/api/events") {
        const since = Number(url.searchParams.get("since") ?? "0");
        const cursor = Number.isFinite(since) && since >= 0 ? Math.floor(since) : 0;
        // One line per connect: low-volume, and the observable that proves
        // cursor-resume behavior in the field (client's since vs our head).
        console.log(`[events] connect since=${cursor} head=${journal.head()}`);
        let unsub: (() => void) | null = null;
        let hb: ReturnType<typeof setInterval> | null = null;
        let closed = false;
        const stream = new ReadableStream({
          start(controller) {
            const send = (s: string) => {
              if (closed) return;
              try {
                controller.enqueue(s);
              } catch {
                closed = true;
                if (unsub) unsub();
                if (hb) clearInterval(hb);
              }
            };
            const sendRow = (r: {
              seq: number;
              type: string;
              payload: string;
            }) => send(`id: ${r.seq}\nevent: ${r.type}\ndata: ${r.payload}\n\n`);

            if (!journal.canServe(cursor)) {
              send(`event: resync\ndata: ${JSON.stringify({ head: journal.head() })}\n\n`);
            } else {
              // Subscribe FIRST (buffering), then replay, then flush the buffer —
              // an event appended mid-replay is neither lost nor duplicated.
              let lastSent = cursor;
              let replaying = true;
              const buffered: { seq: number; type: string; payload: string }[] = [];
              unsub = journal.subscribe((row) => {
                if (replaying) buffered.push(row);
                else if (row.seq > lastSent) {
                  lastSent = row.seq;
                  sendRow(row);
                }
              });
              let at = cursor;
              for (;;) {
                const rows = journal.since(at, 1000);
                if (rows.length === 0) break;
                for (const r of rows) {
                  sendRow(r);
                  lastSent = r.seq;
                }
                at = lastSent;
              }
              for (const r of buffered) {
                if (r.seq > lastSent) {
                  lastSent = r.seq;
                  sendRow(r);
                }
              }
              replaying = false;
            }
            // Heartbeat carrying head seq: keepalive + a cheap gap detector
            // (client compares against its cursor without waiting for events).
            //
            // The FIRST one is sent immediately, not 10s in. A client whose
            // cursor is already at head — the normal case when no sessions are
            // running — gets no replay rows, so without this the response body
            // stays empty for up to 10s and the client cannot tell an
            // established stream from a black-holed dial. `HostLink` only leaves
            // `.connecting` on the first element received, so that silence was
            // the app showing "Offline" for ~10s after reopening against a
            // perfectly healthy idle host.
            send(`: hb ${journal.head()}\n\n`);
            hb = setInterval(() => send(`: hb ${journal.head()}\n\n`), 10_000);
          },
          cancel() {
            closed = true;
            if (unsub) unsub();
            if (hb) clearInterval(hb);
          },
        });
        return new Response(stream, { headers: sseHeaders() });
      }

      // ---- running claude sessions ----
      if (path === "/api/repos") {
        return json({ repos: await listRepos() });
      }

      // Directories for new sessions: scanned repos + the root and inbox
      // fallbacks. Create a new directory or reconfigure the inbox.
      if (path === "/api/dirs") {
        return json({ root: rootDir(), inbox: inboxDir(), repos: await listRepos() });
      }
      if (path === "/api/dirs/new" && req.method === "POST") {
        const b = (await req.json().catch(() => null)) as { name?: string } | null;
        if (!b?.name?.trim()) return err(400, "name required");
        const dir = createDir(b.name);
        if (!dir) return err(400, "invalid directory name");
        ensureFolderTrusted(dir.cwd);
        return json({ ok: true, ...dir });
      }
      if (path === "/api/dirs/inbox" && req.method === "POST") {
        const b = (await req.json().catch(() => null)) as { path?: string } | null;
        if (!b?.path?.trim()) return err(400, "path required");
        const inbox = setInbox(b.path);
        ensureFolderTrusted(inbox);
        return json({ ok: true, inbox });
      }

      // Serve an agent-produced file (image/video/pdf/md/…) by absolute path so
      // the client can render it inline. Scoped to a few roots and hardened
      // against traversal via realpath containment. Read-only GET. Same
      // unauthenticated-behind-Tailscale posture as the rest of the API (the
      // terminal already grants full shell, so this adds no new exposure).
      if (path === "/api/file") {
        const raw = url.searchParams.get("path");
        if (!raw) return err(400, "path query param required");
        let real: string;
        try {
          real = await realpath(raw);
        } catch {
          return err(404, "file not found");
        }
        // Roots the client may fetch from. homedir() already covers ~everything
        // under the user's home; the temp dirs are added because codex (unlike
        // Claude Code, which is instructed to write into cwd/home) saves
        // screenshots to /tmp and $TMPDIR/.../T and presents those paths in its
        // messages — without these they render as file cards that 404 on tap.
        // Adding /tmp is strictly less exposure than the already-served homedir.
        const rootCandidates = [
          REPOS_ROOT,
          SELF_REPO,
          homedir(),
          tmpdir(), // $TMPDIR — on macOS /var/folders/.../T
          "/tmp",
          "/private/tmp", // macOS /tmp realpaths here
        ];
        const roots = await Promise.all(
          rootCandidates.map(async (r) => {
            try { return await realpath(r); } catch { return r; }
          }),
        );
        if (!roots.some((r) => real === r || real.startsWith(r + "/")))
          return err(403, "path outside allowed roots");
        const f = Bun.file(real);
        if (!(await f.exists())) return err(404, "file not found");
        const size = f.size;
        const baseHeaders: Record<string, string> = {
          "Content-Type": f.type || "application/octet-stream",
          "Cache-Control": "private, max-age=60",
          // iOS AVPlayer streams remote video with Range requests and refuses
          // to play a source that answers 200-with-the-whole-file. Advertise
          // range support so it issues a 206-based progressive load.
          "Accept-Ranges": "bytes",
        };
        // Honor a single byte-range (bytes=start-end | bytes=start- | bytes=-suffix).
        const rangeHeader = req.headers.get("range");
        const m = rangeHeader && /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
        if (m) {
          let start = m[1] === "" ? NaN : parseInt(m[1], 10);
          let end = m[2] === "" ? NaN : parseInt(m[2], 10);
          if (Number.isNaN(start)) {
            // suffix range: last N bytes
            start = Math.max(0, size - end);
            end = size - 1;
          } else if (Number.isNaN(end)) {
            end = size - 1;
          }
          if (start < 0 || start >= size || start > end) {
            return new Response(null, {
              status: 416,
              headers: { "Content-Range": `bytes */${size}`, "Accept-Ranges": "bytes" },
            });
          }
          end = Math.min(end, size - 1);
          return new Response(f.slice(start, end + 1), {
            status: 206,
            headers: {
              ...baseHeaders,
              "Content-Range": `bytes ${start}-${end}/${size}`,
              "Content-Length": String(end - start + 1),
            },
          });
        }
        return new Response(f, { headers: baseHeaders });
      }

      if (path === "/api/sessions") {
        return json({ sessions: await listSessions() });
      }

      // Claude subscription usage (5-hour + 7-day windows) via the OAuth usage
      // endpoint, authed with the local Claude Code credentials. Cached for a
      // minute so reopening the new-session dialog doesn't hammer Anthropic.
      if (path === "/api/claude/usage") {
        if (usageCache && Date.now() - usageCache.at < 60_000)
          return json(usageCache.data);
        try {
          const creds = await Bun.file(
            join(process.env.HOME || "", ".claude", ".credentials.json"),
          ).json();
          const token = creds?.claudeAiOauth?.accessToken;
          if (!token) return err(503, "no Claude credentials on this box");
          const r = await fetch("https://api.anthropic.com/api/oauth/usage", {
            headers: {
              Authorization: `Bearer ${token}`,
              "anthropic-beta": "oauth-2025-04-20",
            },
          });
          if (!r.ok) return err(502, `usage endpoint returned ${r.status}`);
          const u = (await r.json()) as {
            five_hour?: { utilization?: number; resets_at?: string | null };
            seven_day?: { utilization?: number; resets_at?: string | null };
          };
          const data = {
            ok: true,
            fiveHour: { pct: u.five_hour?.utilization ?? null, resetsAt: u.five_hour?.resets_at ?? null },
            sevenDay: { pct: u.seven_day?.utilization ?? null, resetsAt: u.seven_day?.resets_at ?? null },
          };
          usageCache = { at: Date.now(), data };
          return json(data);
        } catch (e) {
          return err(502, e instanceof Error ? e.message : String(e));
        }
      }

      // ---- push notifications (APNs device registry) ----
      // The iOS app registers its APNs device token here so the background
      // watcher can notify it when a session finishes a turn or needs input.
      if (path === "/api/push/register" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          token?: string;
          env?: string;
          owner?: string | null;
        } | null;
        const token = body?.token?.trim();
        if (!token || !/^[0-9a-fA-F]{8,}$/.test(token)) return err(400, "invalid token");
        const env = body?.env === "production" ? "production" : "sandbox";
        const device = await registerDevice({ token, env, owner: body?.owner ?? null });
        // A device just arrived — make sure the watcher is running (it self-skips
        // when push isn't configured, so this is a no-op without APNs creds).
        ensurePushWatcher();
        return json({ ok: true, env: device.env });
      }
      if (path === "/api/push/live-activity/start-token" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          token?: string;
          env?: string;
        } | null;
        const token = body?.token?.trim();
        if (!token || !/^[0-9a-fA-F]{8,}$/.test(token)) return err(400, "invalid token");
        const env = body?.env === "production" ? "production" : "sandbox";
        const record = await upsertLiveActivityToken({ token, env, kind: "pushToStart" });
        ensurePushWatcher();
        return json({ ok: true, kind: record.kind, env: record.env });
      }
      if (path === "/api/push/live-activity/update-token" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          token?: string;
          env?: string;
          sessionId?: string;
        } | null;
        const token = body?.token?.trim();
        if (!token || !/^[0-9a-fA-F]{8,}$/.test(token)) return err(400, "invalid token");
        const env = body?.env === "production" ? "production" : "sandbox";
        const sessionId = body?.sessionId?.trim();
        const record = await upsertLiveActivityToken({
          token,
          env,
          kind: "activityUpdate",
          ...(sessionId ? { sessionId } : {}),
        });
        ensurePushWatcher();
        return json({ ok: true, kind: record.kind, env: record.env });
      }
      if (path === "/api/push/unregister" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as { token?: string } | null;
        const token = body?.token?.trim();
        if (!token) return err(400, "missing token");
        await unregisterDevice(token);
        return json({ ok: true });
      }
      if (path === "/api/push/health" && req.method === "GET") {
        return json({ configured: pushConfigured(), devices: await deviceCount() });
      }

      // Tag a session to a user (or clear with user:null). Keyed server-side by
      // the session's tmux name so the tag survives /clear sessionId rotation.
      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/user$/);
        if (m && req.method === "POST") {
          const body = (await req.json().catch(() => null)) as { user?: string | null } | null;
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (!sess.tmuxName) return err(409, "session is not in a tmux pane — cannot tag");
          if (!assignUser(sess.tmuxName, body?.user ?? null))
            return err(400, "unknown user");
          return json({ ok: true });
        }
      }

      // Start a new lfg-managed session: spin up a detached tmux session
      // running `claude` that we own end-to-end. Because we pick the tmux name
      // we know the exact pane, so we can resolve the authoritative sessionId
      // (no pgrep/heuristic guessing) and tear it down cleanly later.
      // Closed/rebooted-away sessions that can be brought back with `claude
      // --resume`. After the box reboots, the live list (pgrep-based) is empty
      // but every transcript survives on disk — this surfaces those so the UI
      // can offer to resume one. Excludes anything currently live.
      if (path === "/api/sessions/resumable" && req.method === "GET") {
        const liveIds = new Set(
          (await listSessions()).map((s) => s.sessionId).filter((x): x is string => !!x),
        );
        const limit = Number(url.searchParams.get("limit")) || 30;
        const rawBefore = url.searchParams.get("before");
        const before = rawBefore == null ? null : Number.parseFloat(rawBefore);
        const page = await listResumable({
          limit,
          before: before != null && Number.isFinite(before) ? before : null,
        });
        return json(page);
      }

      // Resume a closed claude session: relaunch `claude --resume <id>` in the
      // transcript's original cwd as a fresh managed tmux session, preserving the
      // full conversation. Claude continues into a NEW sessionId, which we resolve
      // from the pidfile (like /new) and hand back so the client can deep-link in.
      if (path === "/api/sessions/resume" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          sessionId?: string;
          model?: string;
          user?: string;
          prompt?: string;
        } | null;
        const sessionId = body?.sessionId?.trim();
        if (!sessionId) return err(400, "sessionId required");
        const model = body?.model?.trim() || undefined;
        const out = await resumeClosedSession({ sessionId, model, user: body?.user, prompt: body?.prompt });
        if (!out.ok) return err(out.status, out.error, out.liveOn ? { liveOn: out.liveOn } : undefined);
        if (out.alreadyLive)
          return json({ ok: true, tmuxName: out.tmuxName, cwd: out.cwd, sessionId, alreadyLive: true, agent: out.agent });
        return json({ ok: true, tmuxName: out.tmuxName, cwd: out.cwd, sessionId: out.newId, resumedFrom: sessionId, agent: out.agent });
      }

      // Fork a claude session into a new branch: `claude --resume <id>
      // --fork-session` mints a new sessionId from the source's history, leaving
      // the original transcript untouched. Works on live sessions too (branch off
      // whatever's flushed). Returns the new forked id so the client deep-links in.
      if (path === "/api/sessions/fork" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          sessionId?: string;
          model?: string;
          user?: string;
        } | null;
        const sessionId = body?.sessionId?.trim();
        if (!sessionId) return err(400, "sessionId required");
        const model = body?.model?.trim() || undefined;
        const out = await forkSession({ sessionId, model, user: body?.user });
        if (!out.ok) return err(out.status, out.error, out.liveOn ? { liveOn: out.liveOn } : undefined);
        return json({ ok: true, tmuxName: out.tmuxName, cwd: out.cwd, sessionId: out.newId, forkedFrom: sessionId, agent: out.agent });
      }

      if (path === "/api/sessions/new" && req.method === "POST") {
        const body = (await req.json().catch(() => null)) as {
          cwd?: string;
          prompt?: string;
          user?: string;
          voice?: boolean;
          model?: string;
          agent?: "claude" | "codex" | "aisdk" | "codex-aisdk" | "opencode";
          parentSessionId?: unknown;
        } | null;
        // Default flip (Task B): with no agent specified, the default Claude path
        // now goes through the AI SDK ("aisdk") rather than the Claude CLI. Every
        // explicit value still works, INCLUDING explicit "claude" for the CLI.
        const agent =
          body?.agent === "codex"
            ? "codex"
            : body?.agent === "codex-aisdk"
              ? "codex-aisdk"
              : body?.agent === "opencode"
                ? "opencode"
                : body?.agent === "claude"
                  ? "claude"
                  : "aisdk";
        // Allowlist Claude models — they land on a shell argv. Unknown value =
        // hard 400, never a silent fallback to some other model. Codex model
        // names are provider/catalog driven, so validate shape instead.
        const model = body?.model?.trim() || undefined;
        if (agent === "claude" && model && !CLAUDE_MODELS.includes(model))
          return err(400, `unknown model "${model}" (expected one of ${CLAUDE_MODELS.join(", ")})`);
        if (agent === "codex" && model && !CODEX_MODEL_RE.test(model))
          return err(400, "invalid codex model name");
        if (agent === "aisdk" && model && !AISDK_MODELS.includes(model))
          return err(400, `unknown model "${model}" (expected one of ${AISDK_MODELS.join(", ")})`);
        // codex-aisdk drives codex through the AI SDK, so its model is a codex
        // slug (gpt-5.x…) — provider/catalog driven like the tmux codex.
        // Validate by shape, same as the codex branch.
        if (agent === "codex-aisdk" && model && !CODEX_MODEL_RE.test(model))
          return err(400, "invalid codex model name");
        // opencode models are "provider/model" (e.g. anthropic/claude-sonnet-5),
        // so the validation shape additionally allows a slash. Catalog-driven, so
        // validate by shape rather than an allowlist.
        if (agent === "opencode" && model && !/^[A-Za-z0-9_.:\/-]{1,80}$/.test(model))
          return err(400, "invalid opencode model name");
        // Always spawn in a trusted folder — claude shows a blocking "trust this
        // folder?" dialog for any untrusted cwd, which hangs session startup. The
        // lfg-sessions skill is installed user-level (~/.claude/skills) so the
        // voice/orchestrator agent gets it regardless of cwd.
        const requestedCwd = body?.cwd?.trim() || SELF_REPO;
        // Accept a scanned repo, the root/inbox fallbacks, or any existing
        // directory (so newly-created dirs work). Pre-trust it so claude's
        // folder-trust dialog doesn't hang startup.
        let cwd = (await listRepos()).find((r) => r.cwd === requestedCwd)?.cwd ?? null;
        if (!cwd) {
          try {
            if (statSync(requestedCwd).isDirectory()) cwd = requestedCwd;
          } catch {}
        }
        if (!cwd) return err(400, "directory not found");
        ensureFolderTrusted(cwd);
        const parentSessionId = normalizeParentSessionId(body?.parentSessionId);
        const tmuxName = `lfg-${randomBytes(3).toString("hex")}`;
        // For the voice orchestrator, append a live snapshot of every OTHER
        // session (built before this one spawns, so it's not in the list) so its
        // first spoken reply can be a proactive blockers-first status briefing.
        let prompt = body?.prompt;
        if (body?.voice) {
          const snap = await voiceStatusSnapshot();
          prompt = `${prompt ?? ""}\n\n=== SESSION SNAPSHOT (live, at session start) ===\n${snap}\n=== END SNAPSHOT ===`;
        }
        // aisdk sessions own their sessionId up front (deterministic transcript
        // path), so we generate it here and hand it to the harness.
        const aisdkSessionId = agent === "aisdk" ? crypto.randomUUID() : null;
        // codex-aisdk can't pick its transcript id (codex mints the threadId
        // after turn 1), so we mint a CONTROL-PLANE KEY instead — it names the
        // registry/command files and is what serve routes sends through until
        // the threadId is known. (See the codex-aisdk harness header.)
        const codexAisdkKey = agent === "codex-aisdk" ? crypto.randomUUID() : null;
        // opencode mints a control-plane KEY that is ALSO the transcript id: the
        // harness self-persists the Claude-shaped transcript named by this key, so
        // the returned sessionId == key (no after-turn-1 id to wait for, unlike
        // codex-aisdk). See the opencode harness header.
        const opencodeKey = agent === "opencode" ? crypto.randomUUID() : null;
        const spawnStartedAt = Date.now();
        const r =
          agent === "codex"
            ? spawnManagedCodexSession({ name: tmuxName, cwd, prompt, model })
            : agent === "aisdk"
              ? spawnManagedAisdkSession({
                  name: tmuxName,
                  cwd,
                  prompt,
                  model: model ?? "claude-opus-5",
                  sessionId: aisdkSessionId!,
                })
              : agent === "codex-aisdk"
                ? spawnManagedCodexAisdkSession({
                    name: tmuxName,
                    cwd,
                    prompt,
                    model: model ?? "gpt-5.6-sol",
                    key: codexAisdkKey!,
                  })
                : agent === "opencode"
                  ? spawnManagedOpencodeAisdkSession({
                      name: tmuxName,
                      cwd,
                      prompt,
                      model: model ?? "anthropic/claude-sonnet-5",
                      key: opencodeKey!,
                    })
                  : spawnManagedSession({ name: tmuxName, cwd, prompt, model });
        if (!r.ok) return err(502, r.error || "failed to start session");
        addManaged({
          tmuxName,
          cwd,
          createdAt: Date.now(),
          agent,
          ...(parentSessionId ? { parentSessionId } : {}),
        });
        // Tag the new session to whoever created it so it lands in their filter
        // immediately (best-effort: assignUser ignores an unknown email).
        if (body?.user) assignUser(tmuxName, body.user);
        // Resolve the sessionId so the client can deep-link straight into the
        // new session. Claude writes a pidfile; Codex writes its rollout after
        // startup/first prompt, and may first show an update selector that we
        // dismiss automatically. aisdk's id is known immediately — just wait for
        // the harness to register so the session is listable.
        let sessionId: string | null = aisdkSessionId;
        const bindPolls =
          agent === "codex" ? CODEX_CREATE_SESSION_BIND_POLLS : DEFAULT_CREATE_SESSION_BIND_POLLS;
        for (let i = 0; i < bindPolls && !sessionId; i++) {
          await new Promise((res) => setTimeout(res, CREATE_SESSION_BIND_POLL_MS));
          if (agent === "codex") {
            dismissCodexUpdatePrompt(`${tmuxName}:0.0`);
            sessionId =
              (await listSessions()).find((s) => s.tmuxName === tmuxName)?.sessionId ??
              null;
          } else {
            const pid = panePidForSession(tmuxName);
            if (pid) sessionId = sessionIdForPid(pid);
          }
        }
        if (agent === "codex" && !sessionId) {
          const sessions = await listSessions();
          sessionId = sessions.find((s) => s.tmuxName === tmuxName)?.sessionId ?? null;
          if (!sessionId) {
            const claimedIds = new Set(
              sessions
                .filter((s) => s.sessionId)
                .map((s) => s.sessionId as string),
            );
            sessionId =
              pickSingleCodexCreateFallbackCandidate({
                cwd,
                spawnedAt: spawnStartedAt,
                candidates: await codexCreateFallbackCandidates(),
                claimedIds,
              })?.id ?? null;
          }
        }
        if (agent === "aisdk") {
          for (let i = 0; i < 20 && !readAisdkEntry(aisdkSessionId!); i++)
            await new Promise((res) => setTimeout(res, 250));
        }
        // opencode: the harness writes the transcript at the key, so the
        // sessionId IS the key — just wait for the harness to register so the
        // session is listable (no after-turn-1 threadId to wait for).
        if (agent === "opencode") {
          for (let i = 0; i < 20 && !readAisdkEntry(opencodeKey!); i++)
            await new Promise((res) => setTimeout(res, 250));
          sessionId = opencodeKey;
        }
        // codex-aisdk: wait for the harness to register (so the session is
        // listable), then prefer the codex threadId once turn 1 reports it (it
        // deep-links to the rollout transcript). The threadId only lands after
        // the first turn completes, so don't block on it — fall back to the
        // control-plane key, a stable handle serve maps back internally. Total
        // added wait stays bounded (~5s registration + ~3s threadId).
        if (agent === "codex-aisdk") {
          for (let i = 0; i < 20 && !readAisdkEntry(codexAisdkKey!); i++)
            await new Promise((res) => setTimeout(res, 250));
          sessionId = codexAisdkKey;
          for (let i = 0; i < 12; i++) {
            const tid = readAisdkEntry(codexAisdkKey!)?.threadId;
            if (tid) {
              sessionId = tid;
              break;
            }
            await new Promise((res) => setTimeout(res, 250));
          }
        }
        if (sessionId) {
          const entry =
            aisdkSessionId
              ? readAisdkEntry(aisdkSessionId)
              : codexAisdkKey
                ? readAisdkEntry(codexAisdkKey)
                : opencodeKey
                  ? readAisdkEntry(opencodeKey)
                  : null;
          const leasePid = entry?.harnessPid ?? panePidForSession(tmuxName);
          if (leasePid) await acquireLease(sessionId, leasePid);
        }
        return json({ ok: true, tmuxName, cwd, sessionId, agent });
      }

      {
        // Image attach: the browser POSTs raw image bytes; we persist them and
        // hand back an absolute path. The client then includes that path in the
        // message text — Claude Code reads local image paths as image input.
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/upload$/);
        if (m && req.method === "POST") {
          const ct = (req.headers.get("content-type") || "").toLowerCase();
          const ext = ct.includes("png")
            ? "png"
            : ct.includes("webp")
              ? "webp"
              : ct.includes("gif")
                ? "gif"
                : "jpg";
          const buf = new Uint8Array(await req.arrayBuffer());
          if (!buf.length) return err(400, "empty upload");
          const dir = join(tmpdir(), "lfg-uploads");
          mkdirSync(dir, { recursive: true });
          const name = `${m[1]}-${Date.now()}-${randomBytes(3).toString("hex")}.${ext}`;
          const fp = join(dir, name);
          await Bun.write(fp, buf);
          return json({ ok: true, path: fp });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/send$/);
        if (m && req.method === "POST") {
          const body = (await req.json().catch(() => null)) as {
            text?: string;
            clientId?: unknown;
          } | null;
          const text = body?.text?.trim();
          if (!text) return err(400, "expected { text }");
          if (
            body?.clientId !== undefined &&
            (typeof body.clientId !== "string" || body.clientId.length > 128)
          ) {
            return err(400, "clientId must be a string <= 128 chars");
          }
          const clientId = typeof body?.clientId === "string" && body.clientId
            ? body.clientId
            : crypto.randomUUID();
          const existing = getMessageByClientId(m[1], clientId);
          if (existing) {
            const { duplicate: _duplicate, ...msgBody } = existing;
            return json({ ok: true, msg: msgBody, clientId: existing.clientId, duplicate: true });
          }
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          // The session's pane is gone — it was reaped while idle (box reboot,
          // host restart, the user closing it) but its transcript survives on
          // disk. Rather than fail the send (the old "session not found" 404
          // that stranded every message to a since-closed session), resume the
          // conversation with this message as the kickoff prompt. Claude
          // continues into a NEW sessionId for Claude, while Codex resume is
          // id-stable and returns the same id. resumeClosedSession branches by
          // transcript family and records the Codex binding before the live
          // scanner can fall back to heuristics.
          if (!sess) {
            const transcript = await resolveTranscript(m[1]);
            if (!transcript) return err(404, "session not found");
            const out = await resumeClosedSession({ sessionId: m[1], prompt: text });
            if (!out.ok) return err(out.status, out.error, out.liveOn ? { liveOn: out.liveOn } : undefined);
            const msg = recordImmediateMessage(m[1], text, clientId);
            const { duplicate: _duplicate, ...msgBody } = msg;
            return json({
              ok: true,
              resumed: true,
              sessionId: out.newId,
              resumedFrom: m[1],
              tmuxName: out.tmuxName,
              cwd: out.cwd,
              agent: out.agent,
              clientId: msg.clientId,
              msg: msgBody,
            });
          }
          // aisdk / codex-aisdk sessions have no pane — push the turn through the
          // harness's command file instead of the tmux send-keys queue. The new
          // user turn surfaces in the transcript (and thus the live view) once
          // the harness runs it. For codex-aisdk the live-view id is the codex
          // threadId, not the control-plane key the command file is named by, so
          // map it back via the registry.
          if (
            sess.agent === "aisdk" ||
            sess.agent === "codex-aisdk" ||
            sess.agent === "opencode"
          ) {
            const key = findAisdkEntryByAnyId(m[1])?.sessionId ?? m[1];
            appendAisdkCmd(key, { type: "send", text });
            const msg = recordImmediateMessage(m[1], text, clientId);
            const { duplicate: _duplicate, ...msgBody } = msg;
            return json({
              ok: true,
              clientId: msg.clientId,
              msg: msgBody,
            });
          }
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot send");
          // Enqueue and return immediately; the queue confirms delivery in the
          // background and the client tracks status via the `queue` SSE event.
          const msg = enqueueMessage(m[1], text, { clientId });
          const { duplicate: _duplicate, ...msgBody } = msg;
          return json({
            ok: true,
            msg: msgBody,
            clientId: msg.clientId,
            ...(msg.duplicate ? { duplicate: true } : {}),
          });
        }
      }

      // Change the model of a running session mid-flight. Claude Code's own
      // `/model <alias>` slash command switches the active model for the rest of
      // the session and takes effect on the next turn — so we just inject it
      // through the confirmed-delivery queue (which treats a slash command as
      // delivered the instant it leaves the composer). If Claude raises a
      // "re-read history?" confirmation, it surfaces in the normal prompt panel
      // for the user to confirm. (Inline /model also nudges the global default,
      // but that's inert here: lfg always launches new sessions with an
      // explicit --model.)
      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/model$/);
        if (m && req.method === "POST") {
          const body = (await req.json().catch(() => null)) as {
            model?: string;
          } | null;
          const model = body?.model?.trim();
          if (!model) return err(400, "expected { model }");
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (sess.agent !== "claude")
            return err(409, "mid-session model change is only supported for Claude sessions");
          if (!CLAUDE_MODELS.includes(model))
            return err(400, `unknown model "${model}" (expected one of ${CLAUDE_MODELS.join(", ")})`);
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot change model");
          // If the session is FROZEN on an unavailable model, an injected
          // `/model` no-ops — Claude Code rejects the turn before handling the
          // slash command ("Kept model as <dead model>"). Relaunch the pane on
          // the new model instead (resumes the transcript, so the build
          // continues). For a healthy session the in-place `/model` is gentler
          // (no process restart), so keep that path for the normal case.
          if (sess.statusReason === "model_unavailable") {
            if (!sess.sessionId || !sess.cwd)
              return err(409, "cannot relaunch: session id or cwd unknown");
            const r = relaunchSessionWithModel({
              tmuxTarget: sess.tmuxTarget,
              cwd: sess.cwd,
              sessionId: sess.sessionId,
              model,
            });
            if (!r.ok) return err(500, r.error || "relaunch failed");
            return json({ ok: true, relaunched: true, model });
          }
          const msg = enqueueMessage(m[1], `/model ${model}`);
          return json({ ok: true, msg });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/queue$/);
        if (m && req.method === "GET") {
          // Reconcile before snapshotting so the client's poll safety-net (used
          // when its SSE stream stalled) also promotes surfaced messages and
          // retires orphaned-queued ones, rather than echoing a stuck "queued".
          await reconcileQueued(m[1]);
          return json({ id: m[1], queue: listQueue(m[1]) });
        }
        if (m && req.method === "DELETE") {
          return json({ ok: true, cleared: clearResolved(m[1]) });
        }
      }

      // Non-streaming transcript read — lets an orchestrator (e.g. the voice
      // agent via the lfg-sessions skill) inspect what another session is
      // doing without holding an SSE connection.
      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/messages$/);
        if (m && req.method === "GET") {
          return messagesResponseForSession(m[1], url);
        }
      }

      {
        const m = path.match(
          /^\/api\/sessions\/([0-9a-fA-F-]{36})\/queue\/([0-9a-f]+)\/retry$/,
        );
        if (m && req.method === "POST") {
          const msg = retryMessage(m[1], m[2]);
          if (!msg) return err(404, "queued message not found");
          return json({ ok: true, msg });
        }
      }

      // Remove a not-yet-delivered queued message. Clean because we hold it in
      // lfg's own queue (not Claude's) until the agent is idle — see sendq.ts.
      {
        const m = path.match(
          /^\/api\/sessions\/([0-9a-fA-F-]{36})\/queue\/([0-9a-f]+)$/,
        );
        if (m && req.method === "DELETE") {
          if (!removeMessage(m[1], m[2]))
            return err(409, "message already delivered or in-flight");
          return json({ ok: true });
        }
      }

      // "Send now + interrupt": stop the current turn and run this message next.
      {
        const m = path.match(
          /^\/api\/sessions\/([0-9a-fA-F-]{36})\/queue\/([0-9a-f]+)\/send-now$/,
        );
        if (m && req.method === "POST") {
          if (!(await sendNow(m[1], m[2])))
            return err(409, "message already delivered or in-flight");
          return json({ ok: true });
        }
      }

      // Dispatch a coding agent to debug why a send failed. Only valid for a
      // failed message — it spawns an agent into the lfg repo with the
      // message text, the delivery error, and a live capture of the stuck pane.
      {
        const m = path.match(
          /^\/api\/sessions\/([0-9a-fA-F-]{36})\/queue\/([0-9a-f]+)\/debug$/,
        );
        if (m && req.method === "POST") {
          const msg = getMessage(m[1], m[2]);
          if (!msg) return err(404, "queued message not found");
          if (msg.status !== "failed")
            return err(409, "only a failed message can be debugged");
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          const result = await dispatchSendFixAgent({
            failSessionId: m[1],
            failTarget: sess?.tmuxTarget ?? null,
            failTitle: sess?.title,
            msgId: msg.id,
            msgText: msg.text,
            msgError: msg.error,
            msgAttempts: msg.attempts,
          });
          if (!result.ok) return err(502, result.summary);
          return json({ ok: true, ...(result.data as object) });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/title$/);
        if (m && req.method === "PUT") {
          const body = (await req.json().catch(() => null)) as {
            title?: string;
          } | null;
          await setSessionTitle(m[1], body?.title ?? "");
          return json({ ok: true });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/answer$/);
        if (m && req.method === "POST") {
          const body = (await req.json().catch(() => null)) as {
            index?: number;
          } | null;
          if (typeof body?.index !== "number")
            return err(400, "missing option index");
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot answer");
          const r = await answerPrompt(sess.tmuxTarget, body.index);
          if (!r.ok) return err(502, r.error || "answer failed");
          return json({ ok: true });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/dismiss$/);
        if (m && req.method === "POST") {
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot dismiss");
          // Skip the question without answering: Escape cancels the selector.
          const r = await dismissPrompt(sess.tmuxTarget);
          if (!r.ok) return err(502, r.error || "dismiss failed");
          return json({ ok: true });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/interrupt$/);
        if (m && req.method === "POST") {
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (
            sess.agent === "aisdk" ||
            sess.agent === "codex-aisdk" ||
            sess.agent === "opencode"
          ) {
            // Abort the current turn via the harness (AbortController on its
            // side). Map a codex-aisdk threadId back to the control-plane key.
            const key = findAisdkEntryByAnyId(m[1])?.sessionId ?? m[1];
            appendAisdkCmd(key, { type: "interrupt" });
            return json({ ok: true });
          }
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot interrupt");
          // A single Escape stops the current turn. This doubles as "steer":
          // any message already sitting in Claude's own queue gets processed as
          // the next turn once the running one is interrupted. We deliberately
          // don't drop pending sends — that would discard the message the user
          // is steering with.
          if (!tmuxInterrupt(sess.tmuxTarget)) return err(502, "interrupt failed");
          return json({ ok: true });
        }
      }

      {
        const m = path.match(/^\/api\/sessions\/([0-9a-fA-F-]{36})\/close$/);
        if (m && req.method === "POST") {
          const sess = (await listSessions()).find((s) => s.sessionId === m[1]);
          if (!sess) return err(404, "session not found");
          if (
            sess.agent === "aisdk" ||
            sess.agent === "codex-aisdk" ||
            sess.agent === "opencode"
          ) {
            // Ask the harness to shut down, then tear down its supervisor pane and
            // control-plane files. markClosed tombstones the harness pid so the
            // session drops out of the list immediately. For codex-aisdk the
            // live-view id is the threadId — map it back to the key the command
            // file and registry entry are named by.
            const key = findAisdkEntryByAnyId(m[1])?.sessionId ?? m[1];
            appendAisdkCmd(key, { type: "close" });
            if (sess.tmuxName) tmuxKillSession(sess.tmuxName);
            markClosed(sess.pid);
            removeAisdkEntry(key);
            if (sess.tmuxName) {
              removeManaged(sess.tmuxName);
              assignUser(sess.tmuxName, null);
            }
            clearResolved(m[1]);
            await releaseLease(m[1]);
            return json({ ok: true });
          }
          if (!sess.tmuxTarget)
            return err(409, "session is not in a tmux pane — cannot close");
          // A session lfg started owns its whole tmux session (one managed
          // claude, no sibling panes) — kill the session and deregister it.
          // Attached sessions might share a tmux session with the user's other
          // panes, so only kill the one pane.
          const ok =
            sess.managed && sess.tmuxName
              ? tmuxKillSession(sess.tmuxName)
              : tmuxKillPane(sess.tmuxTarget);
          if (!ok) return err(502, "close failed");
          // Tombstone the pid so the session drops out of listSessions() at once
          // — the process lingers briefly after the SIGHUP and would otherwise
          // flicker back for a poll or two before pgrep stops seeing it.
          markClosed(sess.pid);
          if (sess.managed && sess.tmuxName) {
            removeManaged(sess.tmuxName);
            assignUser(sess.tmuxName, null); // a managed name is unique + now gone
          }
          clearResolved(m[1]);
          await releaseLease(m[1]);
          return json({ ok: true });
        }
      }

      // How recently a bare CLI session's transcript must have been written for
      // it to count as "running" when there's no pane to scrape. Bigger than the
      // 1s poll interval so brief gaps between streamed lines don't flicker it
      // off; small enough that it clears within a few seconds of a turn ending.
      const BARE_BUSY_WINDOW_MS = 4000;


      return err(404, "not found");
    },
  });

  startAutoScheduler((l) => console.log(l));
  // Background push watcher — no-op unless APNs is configured (LFG_APNS_*).
  ensurePushWatcher();
  // Client-independent queue pump: drains the hold-in-lfg outbound queue when
  // each agent goes idle (held messages must deliver even with the app closed).
  startQueuePump();

  console.log(`lfg web → http://${server.hostname}:${server.port}`);
  console.log(`  agents dir: ${AGENTS_DIR}`);
}
