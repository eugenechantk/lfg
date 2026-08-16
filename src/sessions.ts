// Running Claude Code sessions: enumerate live `claude` processes and tail
// their on-disk transcripts (~/.claude/projects/<proj>/<sessionId>.jsonl).
import { readdir, rename } from "node:fs/promises";
import { scanBack, tail } from "./transcript.ts";
import { resolveBusy, sessionTurnState } from "./session-state.ts";
import { statSync, readFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, basename, relative } from "node:path";
import { tmpdir } from "node:os";
import { tmuxTargetForPid, paneTtyForTarget } from "./tmux";
import { listManaged, patchManaged, type ManagedSession } from "./managed";
import {
  listEntries as listAisdkEntries,
  isPidAlive,
  patchEntry as patchAisdkEntry,
  findEntryByAnyId as findAisdkEntryByAnyId,
} from "./aisdk-registry";
import { isClosing } from "./closing";
import { userAssignments } from "./users";
import { PATHS } from "./config";
import {
  applyTitleOverrides,
  matchingEntries,
  parseIndexFile,
  planRefresh,
  queryTerms,
  serializeIndex,
  type IndexEntry,
} from "./session-index";
import { anyFreshAt, ensureLease } from "./leases";
import {
  flattenTitles,
  parseTitleFile,
  type TitleFile,
  type TitleRecord,
  type TitleSource,
} from "./autopilot/titles.ts";
import { homedir } from "node:os";
import { codexDelegationSessionIds, lastPaneBusy } from "./activity.ts";
import {
  listProcs,
  cwdOf,
  primeCwds,
  primeProcSnapshot,
  startTimeMsOf,
  procStartMatches,
  ppidOf as procPpidOf,
  ttyOf,
} from "./procinfo";

const HOME = process.env.HOME ?? homedir();
const PROJECTS_DIR = join(HOME, ".claude", "projects");
const TITLE_MAX = 72;
const CODEX_PROMPT_READ_BYTES = 1024 * 1024;

function claudeProjectsDir(): string {
  return process.env.LFG_CLAUDE_PROJECTS_DIR ?? PROJECTS_DIR;
}

function codexSessionsDir(): string {
  return join(process.env.HOME ?? homedir(), ".codex", "sessions");
}

export type SessionMsg = {
  // Stable per-line id (the transcript `uuid`). Lets the client dedup messages
  // that the live stream legitimately re-sends — e.g. the 40-message backlog
  // replayed on every EventSource reconnect — instead of re-rendering the
  // whole chunk again.
  id: string | null;
  role: string;
  kind: "text" | "thinking" | "tool_use" | "tool_result";
  text: string;
  ts: number | null;
  // True only for a genuine upstream API-error turn (Claude Code stamps the
  // transcript line with `isApiErrorMessage: true` — e.g. a 400 credit-balance
  // block, a 404/synthetic model-unavailable turn, a 429 limit). Normal
  // assistant prose that merely *quotes* such an error is NOT flagged, which is
  // exactly what lets computeStatus avoid false "build paused" banners on
  // sessions that are debugging or summarizing those errors.
  apiError?: boolean;
  // Structured error identity for an apiError turn, straight off the transcript
  // line: Claude Code writes a top-level `error` code (e.g. "authentication_failed")
  // and `apiErrorStatus` (the HTTP status). Present only on real upstream errors —
  // some isApiErrorMessage lines ("No response requested.") carry neither, and
  // those are not blocks. Prefer these over reading the English.
  errorCode?: string;
  apiErrorStatus?: number;
};

export type Session = {
  agent: "claude" | "codex" | "aisdk" | "codex-aisdk" | "opencode";
  pid: number;
  cmd: string;
  cwd: string | null;
  project: string;
  title: string;
  lastUserText: string | null;
  sessionId: string | null;
  startedAt: number | null;
  transcriptPath: string | null;
  lastActivityAt: number | null;
  // Best-effort "is this session mid-turn" baseline carried on the REST list so
  // the client can correct a stale "Working" badge for sessions outside the live
  // SSE window (or whose busy delta was missed across a stream reconnect). Pane
  // sessions use the pump's recent pane scrape when available; transcript
  // freshness is only the fallback. Background Codex delegations are folded in
  // here too so every surface shares the same busy boolean.
  busy: boolean;
  last: SessionMsg | null;
  tmuxTarget: string | null;
  // tmux session name (the `name` in `name:0.0`) when targetable, and whether
  // lfg started this session itself (registry hit) — managed sessions get a
  // clean kill-session teardown and a badge in the UI.
  tmuxName: string | null;
  managed: boolean;
  // The user this session is tagged to (by tmux name), or null if unassigned.
  assignedUser: string | null;
  // Active model as a short alias (opus/sonnet/haiku/fable), resolved from the
  // latest assistant turn in the transcript (so it reflects a mid-session
  // `/model` switch, not just the launch flag), falling back to the launch
  // `--model` arg. null when not yet known (e.g. no assistant output yet).
  model: string | null;
  // Health of the session as far as the build is concerned. "ok" = running
  // normally; "blocked" = the session can't make forward progress until a
  // human acts (e.g. its model was retired/disabled, or the agent ran out of
  // API credits). Surfaced to the user as a "build paused" banner so a frozen
  // session reads as an explained pause, not a silent stall. See computeStatus.
  status: "ok" | "blocked";
  // Machine-readable reason when status === "blocked"; null when ok.
  statusReason: "model_unavailable" | "out_of_credits" | "auth_required" | "unknown" | null;
  // Human-readable one-liner for the banner (e.g. the dead model id), or null.
  statusDetail: string | null;
  // Present only for orchestrator-spawned worker sessions. Omitted for
  // untagged rows so existing clients see byte-identical JSON.
  parentSessionId?: string;
};

// Classify a session's health from the most recent assistant turn. Claude Code
// emits a "<synthetic>"-model assistant turn (not a real inference) when it
// can't run — most commonly because the selected model was retired/disabled
// ("It may not exist or you may not have access to it. Run /model…"), which
// freezes the session: every subsequent turn replays the same error. We detect
// that (and the out-of-credits 400) so the UI can explain the pause instead of
// showing a spinner forever. `liveModel` is the raw model string off the last
// assistant line ("<synthetic>" for these synthetic errors).
// `lastAssistant` is the last ASSISTANT turn, not the last message. Reading the
// last message instead was a latch in the other direction: sending into a
// wedged session made its own user row the tail, which short-circuited this
// function to "ok" and erased the very error that explained the wedge. A 403 two
// rows up is still a 403 (`.claude/diagnosis-stop-close-noop-20260806.md`).
//
// The scan is bounded by correctness, not by a window: it returns the NEWEST
// assistant turn, so a successful reply after the error clears `blocked` on its
// own. The residual case is the few seconds between submitting a prompt and the
// first assistant row of the new turn, during which a previously-errored session
// still reports blocked. That is honest — the last thing the agent actually said
// was an error — and it self-clears the moment the new turn produces output.
function computeStatus(
  lastAssistant: SessionMsg | null,
  liveModel: string | null,
): { status: "ok" | "blocked"; statusReason: Session["statusReason"]; statusDetail: string | null } {
  const last = lastAssistant;
  const text = last && last.role === "assistant" ? last.text : "";
  // Only a genuine upstream API-error turn can block the build. Claude Code
  // stamps those with `isApiErrorMessage: true` (surfaced here as last.apiError);
  // normal assistant prose that merely *quotes* an error string is not flagged.
  // Gating on this is what stops a session that's debugging / shipping a fix for
  // credit or model errors from tripping a false "build paused".
  if (!text || !last?.apiError) return { status: "ok", statusReason: null, statusDetail: null };

  const code = last.errorCode ?? null;
  const httpStatus = last.apiErrorStatus ?? null;

  // --- structured first -------------------------------------------------
  // Claude Code writes a machine-readable `error` code and `apiErrorStatus`.
  // Reading those beats matching English, which changes with every upstream
  // wording tweak. Observed in real transcripts: error="authentication_failed"
  // with apiErrorStatus 401/403 and text "Please run /login · API Error: 403".
  // That case matched none of the prose patterns below, so a logged-out host
  // used to report a perfectly healthy "ok" while every turn failed.
  if (code === "authentication_failed" || httpStatus === 401 || httpStatus === 403) {
    return {
      status: "blocked",
      statusReason: "auth_required",
      statusDetail: "Not signed in on the host — run /login there",
    };
  }

  // --- prose as a labeller, never as the gate ---------------------------
  // These stay because no structured code has been observed for the model and
  // credit cases yet. They now only *label* a turn already proven to be an API
  // error; they no longer decide whether one exists.
  const modelErr =
    /issue with the selected model|may not have access to it\.?\s*run \/model|claude[\w.\s-]*is (currently )?unavailable|\bis no longer (available|supported)\b/i.test(
      text,
    );
  if (modelErr || (liveModel === "<synthetic>" && /\bmodel\b/i.test(text))) {
    const bad = text.match(/\(([^)]+)\)/)?.[1] ?? (liveModel && liveModel !== "<synthetic>" ? liveModel : null);
    return {
      status: "blocked",
      statusReason: "model_unavailable",
      statusDetail: bad ? `Model "${bad}" is unavailable` : "Selected model is unavailable",
    };
  }
  if (/credit balance is too low|"type":\s*"(credit_balance_too_low|billing_error)"/i.test(text)) {
    return { status: "blocked", statusReason: "out_of_credits", statusDetail: "Out of API credits" };
  }

  // --- unknown is a first-class state, not silence ----------------------
  // An API error we cannot name is still an API error: the session is frozen and
  // every turn replays it. Reporting "ok" here is how a new upstream wording
  // becomes an invisible outage. Surface the raw text and let the user read it.
  // Requires a structured signal: some isApiErrorMessage lines carry neither a
  // code nor a status (e.g. "No response requested.") and are not real blocks.
  if (code || httpStatus) {
    const detail = text.split("\n")[0].trim().slice(0, 160);
    return { status: "blocked", statusReason: "unknown", statusDetail: detail || "Upstream API error" };
  }

  return { status: "ok", statusReason: null, statusDetail: null };
}

// Test seam: computeStatus is private, but it is the whole of the status
// contract, so the tests drive it directly rather than standing up listSessions.
export const statusForTest = computeStatus;

// Test seam for the OTHER half of the status contract: which message
// `computeStatus` is handed. Passing the wrong one is what made a wedged session
// report healthy, and that bug is invisible to a test that calls computeStatus
// directly — it lives entirely in the selection.
export const lastAssistantForTest = (path: string) => lastAssistantMsg(path);

const UUID = /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/;
// Whole-string variant for validating a bare id (e.g. a transcript filename).
const UUID_EXACT = new RegExp(`^${UUID.source}$`);

// Live `claude` / `codex` processes with their full command line. Platform
// details (pgrep on Linux, ps on macOS) live in ./procinfo; the include gate
// (argv[0] basename must be the tool) is identical across platforms.
function listClaudeProcs(): { pid: number; cmd: string }[] {
  return listProcs("claude");
}

function listCodexProcs(): { pid: number; cmd: string }[] {
  return listProcs("codex");
}

// Authoritative pid→session map. Claude writes ~/.claude/sessions/<pid>.json
// with the LIVE sessionId. The `--resume <uuid>` in the command line is the
// *pre-resume* id (Claude continues into a fresh transcript), so it points at a
// stale file. `procStart` lets us reject a recycled pid's leftover json.
function readPidSession(
  pid: number,
): { sessionId: string; cwd: string | null; boundAt: number | null } | null {
  try {
    const raw = readFileSync(
      join(HOME, ".claude", "sessions", `${pid}.json`),
      "utf8",
    );
    const j = JSON.parse(raw) as {
      sessionId?: string;
      cwd?: string;
      procStart?: string;
      startedAt?: number;
    };
    if (!j.sessionId) return null;
    // Reject a recycled pid's leftover json: the live process's start time must
    // match the one claude stamped. Platform/encoding differences (Linux clock
    // ticks vs macOS UTC-vs-local lstart) are handled inside procStartMatches.
    if (j.procStart && !procStartMatches(pid, j.procStart)) return null;
    // `startedAt` is when this process BOUND this sessionId, which is not the
    // process start time when a running claude switches session (in-TUI
    // /resume). It is the tiebreak `resolveSessionOwners` needs, and unlike the
    // pidfile's mutable `updatedAt` it never changes for a given process — so a
    // winner picked from it cannot flap between ticks.
    return {
      sessionId: j.sessionId,
      cwd: j.cwd ?? null,
      boundAt: typeof j.startedAt === "number" ? j.startedAt : null,
    };
  } catch {
    return null;
  }
}

// Resolve a live claude pid to its sessionId via the authoritative pidfile.
// Returns null until claude has written ~/.claude/sessions/<pid>.json.
export function sessionIdForPid(pid: number): string | null {
  return readPidSession(pid)?.sessionId ?? null;
}

function projectName(cwd: string | null): string {
  if (!cwd) return "—";
  return cwd.replace(/[/.]/g, "-").replace(/^-/, "");
}

// Title overrides, keyed by sessionId (~/.lfg/session-titles.json). Each row
// carries its provenance so the autopilot can rename sessions without ever
// clobbering a name the human chose — see `src/autopilot/titles.ts` for the
// record shape and the legacy-string upgrade.
export async function readTitleRecords(): Promise<TitleFile> {
  return (await readTitleFileStrict()).records;
}

/**
 * The read that a WRITER must use.
 *
 * `readTitleRecords` degrades an unreadable file to "no overrides", which is the
 * right call for display — a corrupt file should cost a title, not a request.
 * For a read-modify-write it is catastrophic: the writer would treat the file as
 * empty and then persist only its own row, silently destroying every other
 * override. `ok: false` lets the writer abort instead.
 */
async function readTitleFileStrict(): Promise<{ records: TitleFile; ok: boolean }> {
  const f = Bun.file(PATHS.sessionTitles);
  try {
    if (!(await f.exists())) return { records: {}, ok: true }; // absent ≠ corrupt
    return { records: parseTitleFile(await f.json()), ok: true };
  } catch {
    return { records: {}, ok: false };
  }
}

/** The flat `id → title` map the session list and search index consume. */
export async function readTitleOverrides(): Promise<Record<string, string>> {
  return flattenTitles(await readTitleRecords());
}

export async function setSessionTitle(
  sessionId: string,
  title: string,
  opts: { source?: TitleSource; basis?: string } = {},
): Promise<void> {
  await updateTitleRecord(sessionId, (prev) => {
    const t = title.trim();
    if (!t) return null; // empty title clears the override
    return {
      ...prev,
      title: t.slice(0, 200),
      // Defaults to "user": the only caller that doesn't pass a source is the
      // client's rename endpoint, and a human rename must pin the title.
      source: opts.source ?? "user",
      setAt: Date.now(),
      ...(opts.basis ? { basis: opts.basis } : {}),
    };
  });
}

/**
 * Read-modify-write one row. `mutate` returns the next record, or null to drop
 * the row; returning the previous record unchanged is a no-op write.
 *
 * Three things protect the other rows in this file, and every one of them is
 * load-bearing because a bad write here destroys titles the human chose:
 *
 *   1. In-process serialization (`titleWriteChain`). The autopilot updates many
 *      rows in a batch while the client's rename endpoint can land at any
 *      moment; without this the two read-modify-writes lose whichever wrote
 *      first.
 *   2. ATOMIC replace (temp file + rename). `Bun.write` truncates in place, so a
 *      reader — including the OTHER process, since `lfg autopilot` and `lfg
 *      serve` both write this file and a promise chain cannot span processes —
 *      can observe a half-written file. `rename(2)` is atomic within a
 *      filesystem, so a reader sees either the old file or the new one.
 *   3. Abort on an unreadable file (2). Truncation and clobbering compound: a
 *      reader that parses a partial file falls back to `{}` and the next write
 *      persists only its own row. Refusing to write is always recoverable;
 *      writing over everything is not.
 */
let titleWriteChain: Promise<unknown> = Promise.resolve();

export function updateTitleRecord(
  sessionId: string,
  mutate: (prev: Partial<TitleRecord>) => TitleRecord | null,
): Promise<void> {
  const run = titleWriteChain.catch(() => {}).then(async () => {
    const { records: all, ok } = await readTitleFileStrict();
    if (!ok) {
      throw new Error(
        `refusing to write ${PATHS.sessionTitles}: existing file is unreadable ` +
          `(writing would drop every other title override)`,
      );
    }
    const next = mutate(all[sessionId] ?? {});
    if (next) all[sessionId] = next;
    else delete all[sessionId];
    const tmp = `${PATHS.sessionTitles}.tmp-${process.pid}`;
    await Bun.write(tmp, JSON.stringify(all, null, 2));
    await rename(tmp, PATHS.sessionTitles);
  });
  titleWriteChain = run.catch(() => {});
  return run;
}

// Claude's /resume picker titles a session by its first real user prompt; mirror
// that. Scan from the top, skipping meta rows and command/caveat wrappers
// (which start with "<"), and return the first prose line, truncated.
async function firstPromptTitle(path: string): Promise<string | null> {
  try {
    const text = await Bun.file(path).slice(0, 256 * 1024).text();
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      let x: { type?: string; isMeta?: boolean; message?: { content?: unknown } };
      try {
        x = JSON.parse(line);
      } catch {
        continue;
      }
      const cm = normalizeCodexLine(line, createCodexNormalizationState())?.[0];
      if (cm?.role === "user" && cm.kind === "text") {
        const t = stripConversationPrefix(cm.text).trim().replace(/\s+/g, " ");
        if (t && !t.startsWith("<"))
          return t.length > TITLE_MAX ? t.slice(0, TITLE_MAX - 1) + "…" : t;
      }
      if (x.type !== "user" || x.isMeta) continue;
      const c = x.message?.content;
      let t: string | null = null;
      if (typeof c === "string") t = c;
      else if (Array.isArray(c)) {
        const p = (c as Array<{ type?: string; text?: string }>).find(
          (e) => e?.type === "text" && typeof e.text === "string",
        );
        t = p?.text ?? null;
      }
      if (!t) continue;
      t = stripHumanPrefix(t.trim().replace(/\s+/g, " "));
      if (!t || t.startsWith("<")) continue;
      return t.length > TITLE_MAX ? t.slice(0, TITLE_MAX - 1) + "…" : t;
    }
  } catch {}
  return null;
}

function candidateDirs(cwd: string): string[] {
  // claude maps cwd to a dir name by replacing path separators; try the
  // common encodings so bare sessions still resolve.
  const slash = cwd.replace(/\//g, "-");
  const dots = cwd.replace(/[/.]/g, "-");
  return [...new Set([slash, dots])];
}

async function findTranscriptById(id: string): Promise<string | null> {
  let dirs: string[];
  const projectsDir = claudeProjectsDir();
  try {
    dirs = await readdir(projectsDir);
  } catch {
    return null;
  }
  for (const d of dirs) {
    const p = join(projectsDir, d, `${id}.jsonl`);
    if (await Bun.file(p).exists()) return p;
  }
  return null;
}

async function codexRolloutFiles(): Promise<string[]> {
  const out: string[] = [];
  const root = codexSessionsDir();
  let years: string[];
  try {
    years = await readdir(root);
  } catch {
    return out;
  }
  for (const y of years) {
    let months: string[];
    try {
      months = await readdir(join(root, y));
    } catch {
      continue;
    }
    for (const m of months) {
      let days: string[];
      try {
        days = await readdir(join(root, y, m));
      } catch {
        continue;
      }
      for (const d of days) {
        let files: string[];
        try {
          files = await readdir(join(root, y, m, d));
        } catch {
          continue;
        }
        for (const f of files) {
          if (f.endsWith(".jsonl")) out.push(join(root, y, m, d, f));
        }
      }
    }
  }
  return out;
}

async function findCodexTranscriptById(id: string): Promise<string | null> {
  if (!UUID.test(id)) return null;
  for (const p of await codexRolloutFiles()) {
    if (p.includes(id)) return p;
  }
  return null;
}

export type CodexThread = {
  id: string;
  path: string;
  cwd: string | null;
  createdAt: number | null;
  fileCreatedAt?: number | null;
  updatedAt: number | null;
  firstUserText: string | null;
  forkedFromId: string | null;
};

async function codexThreads(): Promise<CodexThread[]> {
  const out: CodexThread[] = [];
  for (const path of await codexRolloutFiles()) {
    try {
      const first = (await Bun.file(path).slice(0, 128 * 1024).text()).split("\n")[0];
      if (!first) continue;
      const row = JSON.parse(first) as {
        type?: string;
        forked_from_id?: string;
        payload?: { id?: string; cwd?: string; timestamp?: string; forked_from_id?: string };
      };
      const id = row.payload?.id ?? path.match(UUID)?.[0] ?? null;
      if (row.type !== "session_meta" || !id) continue;
      let fileCreatedAt: number | null = null;
      let updatedAt: number | null = null;
      try {
        const stat = statSync(path);
        // `session_meta.payload.timestamp` is normally the rollout creation
        // time, but Codex can create an abandoned metadata-only rollout later
        // while preserving the parent TUI's original launch timestamp. Keep the
        // filesystem birth time as a second signal so that late file cannot
        // impersonate the rollout that actually appeared at process launch.
        fileCreatedAt = stat.birthtimeMs > 0 ? stat.birthtimeMs : null;
        updatedAt = stat.mtimeMs;
      } catch {}
      out.push({
        id,
        path,
        cwd: row.payload?.cwd ?? null,
        createdAt: row.payload?.timestamp ? Date.parse(row.payload.timestamp) : null,
        fileCreatedAt,
        updatedAt,
        firstUserText: await firstUserTextFromTop(path),
        forkedFromId: row.payload?.forked_from_id ?? row.forked_from_id ?? null,
      });
    } catch {}
  }
  return out;
}

function isInjectedCodexUserContext(text: string): boolean {
  const leading = text.trimStart();
  return (
    leading.startsWith("# AGENTS.md instructions") ||
    leading.startsWith("<INSTRUCTIONS>") ||
    leading.startsWith("<user_instructions>") ||
    leading.startsWith("<environment_context>")
  );
}

export async function firstUserTextFromTop(path: string): Promise<string | null> {
  let fallback: string | null = null;
  try {
    const text = await Bun.file(path).slice(0, CODEX_PROMPT_READ_BYTES).text();
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      let x: {
        type?: string;
        payload?: {
          type?: string;
          role?: string;
          message?: string;
          content?: unknown;
        };
      };
      try {
        x = JSON.parse(line);
      } catch {
        continue;
      }
      const p = x.payload;
      if (!p) continue;
      if (x.type === "event_msg" && p.type === "user_message" && p.message?.trim()) {
        return stripConversationPrefix(p.message.trim());
      }
      if (fallback || x.type !== "response_item" || p.type !== "message" || p.role !== "user")
        continue;
      const text = stripConversationPrefix(codexContentText(p.content).trim());
      if (text && !isInjectedCodexUserContext(text)) fallback = text;
    }
  } catch {}
  return fallback;
}

function decodeBackslashOctalEscapes(text: string): string {
  return text.replace(/\\([0-7]{3})/g, (_, octal: string) =>
    String.fromCharCode(Number.parseInt(octal, 8)),
  );
}

export function codexPromptFromCmd(cmd: string): string | null {
  const m = cmd.match(/\s--\s+([\s\S]+)$/);
  return m?.[1] ? decodeBackslashOctalEscapes(m[1]).trim() || null : null;
}

function samePrompt(a: string | null, b: string | null): boolean {
  if (!a || !b) return false;
  const clean = (s: string) => s.replace(/\s+/g, " ").trim();
  return clean(a) === clean(b);
}

// How far a rollout's createdAt may precede the process startedAt and still be
// trusted as that process's session (clock skew / rollout-before-first-poll).
const CODEX_BIND_SKEW_MS = 30_000;
// For a promptless (interactive) codex, the launch rollout normally appears
// within seconds, but large restored sessions can delay the file by nearly three
// minutes. Anything created much later in the same cwd belongs to a different,
// later session and must NOT be guess-bound. Five minutes covers the observed
// 170-second restore while the filesystem-birth signal still rejects the
// metadata-only phantom created 30 minutes after launch.
const CODEX_BIND_WINDOW_MS = 5 * 60_000;

// A rollout cannot belong to a process before the file itself existed. Codex's
// embedded timestamp can retain the original TUI launch time when it emits an
// abandoned metadata-only rollout much later, so use the later of the semantic
// timestamp and the filesystem birth time for live launch binding.
function codexBindingCreatedAt(thread: CodexThread): number | null {
  const times = [thread.createdAt, thread.fileCreatedAt].filter(
    (time): time is number => time != null && Number.isFinite(time) && time > 0,
  );
  return times.length > 0 ? Math.max(...times) : null;
}

// Bind a running tmux `codex` process to its rollout transcript. Two modes:
//   1. prompt — the process was launched with an inline `-- <prompt>`; match the
//      unclaimed same-cwd thread whose first user text equals it. When two live
//      sessions launched with the same prompt, bind by rollout-created proximity
//      to the process start; only fall back to freshest write when that signal is
//      missing or tied.
//   2. promptless — an interactive `codex` / `codex --yolo` has no prompt and no
//      resume id, so it is bound to the unclaimed same-cwd thread whose createdAt
//      is nearest the process startedAt (codex writes its rollout at launch). This
//      is the ONLY binding path for an interactive codex; without it sessionId
//      stays null and the client can never load the transcript (spins forever).
// Both require createdAt >= startedAt - CODEX_BIND_SKEW_MS so a stale unrelated
// rollout in the same cwd is never guess-bound. Promptless additionally caps the
// upper bound so a newer session's rollout can't be stolen.
export function pickCodexThread(
  proc: { cwd: string | null; startedAt: number | null; prompt: string | null },
  threads: CodexThread[],
  claimed: Set<string>,
): CodexThread | null {
  const { cwd, startedAt, prompt } = proc;
  if (!cwd) return null;
  const minTime = (startedAt ?? 0) - CODEX_BIND_SKEW_MS;
  const inCwd = threads.filter(
    (t) => t.cwd === cwd && !claimed.has(t.id) && (codexBindingCreatedAt(t) ?? 0) >= minTime,
  );
  if (inCwd.length === 0) return null;
  if (prompt) {
    const matches = inCwd.filter((t) => samePrompt(t.firstUserText, prompt));
    if (matches.length <= 1) return matches[0] ?? null;
    return matches.sort((a, b) => {
      const aCreatedAt = codexBindingCreatedAt(a);
      const bCreatedAt = codexBindingCreatedAt(b);
      if (startedAt != null && aCreatedAt != null && bCreatedAt != null) {
        const byCreatedProximity = Math.abs(aCreatedAt - startedAt) - Math.abs(bCreatedAt - startedAt);
        if (byCreatedProximity !== 0) return byCreatedProximity;
      }
      return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
    })[0] ?? null;
  }
  // Promptless: require a real startedAt (else "nearest to 0" is meaningless) and
  // bind the thread whose createdAt is closest to launch, within the window.
  if (startedAt == null) return null;
  return (
    inCwd
      .filter((t) => (codexBindingCreatedAt(t) ?? 0) <= startedAt + CODEX_BIND_WINDOW_MS)
      .sort(
        (a, b) =>
          Math.abs((codexBindingCreatedAt(a) ?? 0) - startedAt) -
          Math.abs((codexBindingCreatedAt(b) ?? 0) - startedAt),
      )[0] ?? null
  );
}

export function pickKnownCodexThread(
  sessionId: string | null | undefined,
  threads: CodexThread[],
  claimed: Set<string>,
): CodexThread | null {
  if (!sessionId || claimed.has(sessionId)) return null;
  return threads.find((t) => t.id === sessionId) ?? null;
}

export function pickCodexForkThread(
  proc: { forkedFromId: string | null; spawnedAt: number | null },
  threads: CodexThread[],
  claimed: Set<string>,
): CodexThread | null {
  const { forkedFromId, spawnedAt } = proc;
  if (!forkedFromId || spawnedAt == null) return null;
  return (
    threads
      .filter(
        (t) =>
          t.forkedFromId === forkedFromId &&
          !claimed.has(t.id) &&
          t.createdAt != null &&
          t.createdAt >= spawnedAt,
      )
      .sort((a, b) => (a.createdAt ?? 0) - (b.createdAt ?? 0))[0] ?? null
  );
}

function promptStartsWithTitle(prompt: string | null, title: string | null | undefined): boolean {
  if (!prompt || !title) return false;
  const clean = (s: string) => stripConversationPrefix(s).replace(/\s+/g, " ").trim();
  const p = clean(prompt);
  const t = clean(title);
  return !!t && (p === t || p.startsWith(t));
}

// How far an unclaimed transcript may lag the freshest transcript in the same
// cwd and still be trusted as a live process's current session. A running
// `claude` writes its transcript continuously, so the session a pid is on is
// (near) the freshest file in that cwd; a much older "newest unclaimed" file is
// almost certainly a stale, unrelated session and must NOT be guess-bound.
const FALLBACK_FRESHNESS_MS = 10 * 60_000;

// How recently a transcript must have been written for the REST `busy` baseline
// to read a pane session as mid-turn. Wider than the SSE poll cadence so a brief
// pause in output (a silent tool call) doesn't flap a non-streamed session to
// idle; small enough that a finished session reliably reads idle within seconds.
// Only used for sessions NOT covered by the live SSE busy (the client overrides
// with pane-scraped busy for streamed ones), so a little slack here is harmless.
const REST_BUSY_WINDOW_MS = 12_000;

async function newestUnclaimedInCwd(
  cwd: string,
  claimed: Set<string>,
): Promise<{ path: string; id: string } | null> {
  let best: { path: string; id: string; mtime: number } | null = null;
  let newestAny = 0; // freshest transcript regardless of claim status
  const projectsDir = claudeProjectsDir();
  for (const dir of candidateDirs(cwd)) {
    const abs = join(projectsDir, dir);
    let files: string[];
    try {
      files = await readdir(abs);
    } catch {
      continue;
    }
    for (const f of files) {
      if (!f.endsWith(".jsonl")) continue;
      let mtime = 0;
      try {
        mtime = statSync(join(abs, f)).mtimeMs;
      } catch {
        continue;
      }
      if (mtime > newestAny) newestAny = mtime;
      const id = f.replace(/\.jsonl$/, "");
      if (claimed.has(id)) continue;
      if (!best || mtime > best.mtime) best = { path: join(abs, f), id, mtime };
    }
  }
  if (!best) return null;
  // Don't silently bind a live pid to a stale, unrelated transcript — that
  // mis-attributes its pane (e.g. a "needs input" prompt) to the wrong session.
  if (newestAny - best.mtime > FALLBACK_FRESHNESS_MS) {
    console.warn(
      `[sessions] no confident session for cwd ${cwd}: newest unclaimed transcript ${best.id} is ${Math.round((newestAny - best.mtime) / 60000)}m staler than the freshest in this cwd — leaving unidentified`,
    );
    return null;
  }
  return { path: best.path, id: best.id };
}

function inferCodexThreadForHarness(
  e: { cwd: string; title?: string | null; createdAt: number },
  threads: CodexThread[],
  claimed: Set<string>,
): CodexThread | null {
  const minTime = (e.createdAt ?? 0) - 30_000;
  const matches = threads
    .filter(
      (t) =>
        t.cwd === e.cwd &&
        !claimed.has(t.id) &&
        (t.createdAt ?? 0) >= minTime &&
        promptStartsWithTitle(t.firstUserText, e.title),
    )
    .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
  return matches[0] ?? null;
}

// AI-SDK backed providers can persist a speaker prefix ("Human:" for Claude,
// "User:" for Codex). Strip it so cards and transcript user messages read like
// normal CLI sessions.
function stripHumanPrefix(text: string): string {
  return stripConversationPrefix(text);
}

function stripConversationPrefix(text: string): string {
  return text.replace(/^(?:Human|User):[ \t]+/i, "");
}

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    const parts = content
      .map((c: { type?: string; text?: string }) =>
        c?.type === "text" && typeof c.text === "string" ? c.text : "",
      )
      .filter(Boolean);
    if (parts.length) return parts.join("\n");
  }
  return "";
}

function codexContentText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return (content as Array<{ type?: string; text?: string }>)
    .map((c) =>
      (c?.type === "output_text" || c?.type === "input_text" || c?.type === "text") &&
      typeof c.text === "string"
        ? c.text
        : "",
    )
    .filter(Boolean)
    .join("\n");
}

function codexOutputText(output: unknown): string {
  if (typeof output === "string") return output.trim();
  const content = codexContentText(output).trim();
  if (content) return content;
  if (output == null) return "";
  try {
    return JSON.stringify(output);
  } catch {
    return String(output);
  }
}

type CodexCallDisposition = "show-output" | "hide-output";
type CodexCallInfo = {
  disposition: CodexCallDisposition;
  tool?: string;
  startedAt?: number | null;
};

export type CodexNormalizationState = {
  cwd: string | null;
  calls: Map<string, CodexCallInfo>;
};

export function createCodexNormalizationState(): CodexNormalizationState {
  return { cwd: null, calls: new Map() };
}

function stripCodeModeEnvelope(text: string): string {
  const trimmed = text.trim();
  const match = trimmed.match(
    /^Script (?:completed|failed|running with cell ID [^\n]+)\r?\nWall time [^\n]*\r?\nOutput:\s*\r?\n?([\s\S]*)$/,
  );
  return (match?.[1] ?? trimmed).trim();
}

function parseJsonObject(source: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(source);
    return value && typeof value === "object" && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function readJsString(source: string, start: number): { value: string; end: number } | null {
  const quote = source[start];
  if (quote !== '"' && quote !== "'" && quote !== "`") return null;
  let value = "";
  for (let i = start + 1; i < source.length; i++) {
    const ch = source[i];
    if (ch === quote) return { value, end: i + 1 };
    if (ch !== "\\") {
      value += ch;
      continue;
    }
    const next = source[++i];
    if (next == null) return null;
    const escapes: Record<string, string> = {
      n: "\n",
      r: "\r",
      t: "\t",
      b: "\b",
      f: "\f",
      v: "\v",
      "0": "\0",
      "\\": "\\",
      '"': '"',
      "'": "'",
      "`": "`",
    };
    if (next === "u" && /^[0-9a-fA-F]{4}$/.test(source.slice(i + 1, i + 5))) {
      value += String.fromCharCode(Number.parseInt(source.slice(i + 1, i + 5), 16));
      i += 4;
    } else if (next === "x" && /^[0-9a-fA-F]{2}$/.test(source.slice(i + 1, i + 3))) {
      value += String.fromCharCode(Number.parseInt(source.slice(i + 1, i + 3), 16));
      i += 2;
    } else {
      value += escapes[next] ?? next;
    }
  }
  return null;
}

function jsStringProperty(source: string, key: string, from = 0): string | null {
  const re = new RegExp(`(?:^|[,\\s{])(?:["']?${key}["']?)\\s*:\\s*`, "g");
  re.lastIndex = from;
  const match = re.exec(source);
  if (!match) return null;
  let start = re.lastIndex;
  while (/\s/.test(source[start] ?? "")) start++;
  return readJsString(source, start)?.value ?? null;
}

function jsStringArrayVariable(source: string, name: string): string[] {
  const match = new RegExp(`(?:const|let|var)\\s+${name}\\s*=\\s*\\[`).exec(source);
  if (!match) return [];
  const values: string[] = [];
  let cursor = (match.index ?? 0) + match[0].length;
  while (cursor < source.length) {
    while (/[,\s]/.test(source[cursor] ?? "")) cursor++;
    if (source[cursor] === "]") break;
    const value = readJsString(source, cursor);
    if (!value) break;
    values.push(value.value);
    cursor = value.end;
  }
  return values;
}

type InnerCodexToolCall = { name: string; argumentSource: string; args: Record<string, unknown> | null };

function innerCodexToolCalls(source: string): InnerCodexToolCall[] {
  const calls: InnerCodexToolCall[] = [];
  const marker = "tools.";
  let cursor = 0;
  const nextMarker = (from: number): number => {
    let quote: string | null = null;
    let escaped = false;
    for (let i = from; i < source.length; i++) {
      const ch = source[i];
      if (quote) {
        if (escaped) escaped = false;
        else if (ch === "\\") escaped = true;
        else if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'" || ch === "`") {
        quote = ch;
        continue;
      }
      if (source.startsWith(marker, i)) return i;
    }
    return -1;
  };
  while ((cursor = nextMarker(cursor)) >= 0) {
    const nameStart = cursor + marker.length;
    const nameMatch = source.slice(nameStart).match(/^[A-Za-z0-9_]+/);
    if (!nameMatch) {
      cursor = nameStart;
      continue;
    }
    const name = nameMatch[0];
    let open = nameStart + name.length;
    while (/\s/.test(source[open] ?? "")) open++;
    if (source[open] !== "(") {
      cursor = open;
      continue;
    }
    let quote: string | null = null;
    let escaped = false;
    let depth = 1;
    let end = open + 1;
    for (; end < source.length; end++) {
      const ch = source[end];
      if (quote) {
        if (escaped) escaped = false;
        else if (ch === "\\") escaped = true;
        else if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'" || ch === "`") quote = ch;
      else if (ch === "(") depth++;
      else if (ch === ")" && --depth === 0) break;
    }
    const argumentSource = source.slice(open + 1, end).trim();
    calls.push({ name, argumentSource, args: parseJsonObject(argumentSource) });
    cursor = Math.max(end + 1, open + 1);
  }
  return calls;
}

function shellSegments(command: string): string[] {
  const out: string[] = [];
  let start = 0;
  let quote: string | null = null;
  let escaped = false;
  for (let i = 0; i < command.length; i++) {
    const ch = command[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") quote = ch;
    else if (ch === ";" || (ch === "&" && command[i + 1] === "&")) {
      const part = command.slice(start, i).trim();
      if (part) out.push(part);
      if (ch === "&") i++;
      start = i + 1;
    }
  }
  const tail = command.slice(start).trim();
  if (tail) out.push(tail);
  return out;
}

function unquoteShell(value: string): string {
  return value.trim().replace(/^(['"])([\s\S]*)\1$/, "$2");
}

function exploreSummary(command: string): string | null {
  const cmd = command.trim();
  let match = cmd.match(/^(?:cat|head|tail)\b[\s\S]*?\s([^\s]+)\s*$/);
  if (match) return `Read ${unquoteShell(match[1])}`;
  match = cmd.match(/^sed\b[\s\S]*?\s([^\s]+)\s*$/);
  if (match) return `Read ${unquoteShell(match[1])}`;
  if (/^rg\s+--files\b/.test(cmd)) {
    const rest = cmd.replace(/^rg\s+--files\b/, "").trim();
    return `List${rest ? ` ${rest}` : " files"}`;
  }
  if (/^ls\b/.test(cmd)) {
    const rest = cmd.replace(/^ls\b/, "").replace(/(?:^|\s)-\S+/g, "").trim();
    return `List${rest ? ` ${rest}` : " files"}`;
  }
  if (/^find\b/.test(cmd)) {
    const root = unquoteShell(cmd.match(/^find\s+([^\s]+)/)?.[1] ?? ".");
    const pattern = cmd.match(/(?:^|\s)-name\s+(['"]?)([^\s'"]+)\1/)?.[2];
    return pattern ? `Search ${pattern} in ${root}` : `Search files in ${root}`;
  }
  if (/^rg\b/.test(cmd)) {
    const withoutFlags = cmd.replace(/^rg\b/, "").replace(/^\s+(?:--?\S+\s+)*/, "").trim();
    const quoted = withoutFlags.match(/^(['"])([\s\S]*?)\1(?:\s+([\s\S]+))?$/);
    const parts = quoted
      ? { query: quoted[2], path: quoted[3] }
      : { query: withoutFlags.split(/\s+/)[0], path: withoutFlags.split(/\s+/).slice(1).join(" ") };
    return `Search ${parts.query || "text"}${parts.path ? ` in ${parts.path}` : ""}`;
  }
  return null;
}

function commandCellText(command: string): string {
  const parts = shellSegments(command);
  const explored = parts.map(exploreSummary);
  if (parts.length > 0 && explored.every((part): part is string => part != null)) {
    return `Explored\n${explored.join("\n")}`;
  }
  return `Ran\n${command.trim()}`;
}

function planCellText(source: string, args: Record<string, unknown> | null): string {
  const explanation =
    (typeof args?.explanation === "string" ? args.explanation : null) ??
    jsStringProperty(source, "explanation");
  const rows: string[] = ["Updated Plan"];
  if (explanation?.trim()) rows.push(explanation.trim());
  const structured = Array.isArray(args?.plan) ? args.plan : null;
  const plan = structured
    ? structured
        .filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
        .map((item) => ({ step: item.step, status: item.status }))
    : Array.from(source.matchAll(/(?:^|[,\s{])step\s*:\s*/g)).map((match) => {
        const stepStart = (match.index ?? 0) + match[0].length;
        const step = readJsString(source, stepStart)?.value;
        const status = jsStringProperty(source, "status", stepStart);
        return { step, status };
      });
  if (plan.length === 0) rows.push("(no steps provided)");
  for (const item of plan) {
    if (typeof item.step !== "string" || !item.step.trim()) continue;
    rows.push(`${item.status === "completed" ? "✔" : "□"} ${item.step.trim()}`);
  }
  return rows.join("\n");
}

function displayCodexPath(path: string, cwd: string | null): string {
  if (!cwd || !path.startsWith("/")) return path;
  const rel = relative(cwd, path);
  return rel && !rel.startsWith("..") ? rel : path;
}

type CodexPatchChange = {
  type?: unknown;
  unified_diff?: unknown;
  content?: unknown;
  move_path?: unknown;
};

function lineCount(text: string): number {
  return text === "" ? 0 : text.split("\n").length - (text.endsWith("\n") ? 1 : 0);
}

function patchLineCounts(change: CodexPatchChange): { added: number; removed: number } {
  const type = typeof change.type === "string" ? change.type : "update";
  if (type === "add") return { added: lineCount(String(change.content ?? "")), removed: 0 };
  if (type === "delete") return { added: 0, removed: lineCount(String(change.content ?? "")) };
  const diff = typeof change.unified_diff === "string" ? change.unified_diff : "";
  let added = 0;
  let removed = 0;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+") && !line.startsWith("+++")) added++;
    else if (line.startsWith("-") && !line.startsWith("---")) removed++;
  }
  return { added, removed };
}

function codexPatchChangesText(changes: unknown, cwd: string | null): string {
  if (!changes || typeof changes !== "object" || Array.isArray(changes)) return "";
  const rows: Array<{
    path: string;
    type: string;
    added: number;
    removed: number;
    detail: string;
  }> = [];
  for (const [rawPath, raw] of Object.entries(changes).sort(([a], [b]) => a.localeCompare(b))) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const change = raw as CodexPatchChange;
    const type = typeof change.type === "string" ? change.type : "update";
    const path = displayCodexPath(rawPath, cwd);
    const moved =
      typeof change.move_path === "string"
        ? ` → ${displayCodexPath(change.move_path, cwd)}`
        : "";
    const detail =
      typeof change.unified_diff === "string"
        ? change.unified_diff.trim()
        : typeof change.content === "string"
          ? change.content.trim()
          : "";
    const counts = patchLineCounts(change);
    rows.push({ path: `${path}${moved}`, type, ...counts, detail });
  }
  if (rows.length === 0) return "";
  const totalAdded = rows.reduce((sum, row) => sum + row.added, 0);
  const totalRemoved = rows.reduce((sum, row) => sum + row.removed, 0);
  const counts = (added: number, removed: number) => `(+${added} -${removed})`;
  const header =
    rows.length === 1
      ? `${rows[0].type === "add" ? "Added" : rows[0].type === "delete" ? "Deleted" : "Edited"} ${rows[0].path} ${counts(rows[0].added, rows[0].removed)}`
      : `Edited ${rows.length} files ${counts(totalAdded, totalRemoved)}`;
  const details = rows.map((row) => {
    const rowHeader = rows.length === 1 ? "" : `${row.path} ${counts(row.added, row.removed)}`;
    return [rowHeader, row.detail].filter(Boolean).join("\n");
  });
  const body = details.filter(Boolean).join("\n\n");
  return body ? `${header}\n${body}` : header;
}

function blockId(id: string | null, idx: number): string | null {
  if (!id) return null;
  return idx === 0 ? id : `${id}#${idx}`;
}

// File extension for an attached content block's MIME type (best-effort).
function extForMediaType(mediaType: string | undefined, blockType: string | undefined): string {
  const map: Record<string, string> = {
    "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/gif": "gif",
    "image/webp": "webp", "image/heic": "heic", "image/bmp": "bmp", "image/tiff": "tiff",
    "application/pdf": "pdf", "text/plain": "txt", "text/markdown": "md", "text/csv": "csv",
    "application/json": "json", "application/zip": "zip",
    "video/mp4": "mp4", "video/quicktime": "mov",
  };
  const mt = (mediaType || "").toLowerCase();
  if (map[mt]) return map[mt];
  const sub = mt.split("/")[1]?.replace(/[^a-z0-9]/gi, "").slice(0, 5);
  if (sub) return sub;
  return blockType === "document" ? "pdf" : blockType === "image" ? "png" : "bin";
}

function describeInput(input: unknown): string {
  if (input == null) return "";
  if (typeof input === "string") return input;
  try {
    return JSON.stringify(input, null, 2);
  } catch {
    return String(input);
  }
}

// `SendUserFile` is the harness tool an agent calls when a file it produced IS
// the deliverable (a chart, a screenshot, a report). Rendered as a plain tool
// line it would be a blob of JSON with the paths buried inside — the one place
// the file must be tappable is the one place it wasn't. Turn the call into an
// assistant text block whose caption is prose and whose files are markdown
// references, so every client's existing media scanner surfaces them as
// attachments (image/PDF cards, inline video) with no client change.
//
// Images use image syntax on purpose: clients strip `![…](…)` from prose once
// it has become an attachment, so an image contributes no leftover text. Other
// types stay links, which read as a filename the user can also tap inline.
export function sendUserFileText(input: unknown): string | null {
  if (!input || typeof input !== "object") return null;
  const inp = input as { files?: unknown; caption?: unknown };
  if (!Array.isArray(inp.files)) return null;
  const files = inp.files.filter((f): f is string => typeof f === "string" && f.trim() !== "");
  if (files.length === 0) return null;
  const parts: string[] = [];
  const caption = typeof inp.caption === "string" ? inp.caption.trim() : "";
  if (caption) parts.push(caption);
  for (const file of files) {
    const path = file.trim();
    const name = basename(path) || path;
    const isImage = /\.(png|jpe?g|gif|webp|heic|bmp|tiff)$/i.test(path);
    parts.push(`${isImage ? "!" : ""}[${name}](${path})`);
  }
  return parts.join("\n\n");
}

// True for the `tool_result` turn that answers a `SendUserFile` call. Claude
// Code stamps the structured delivery record on the line, so this keys off that
// shape rather than the result prose. The result only restates the paths and
// their upload uuids directly beneath the attachments we just rendered, so it
// is dropped as duplicate noise.
function isSendUserFileResult(toolUseResult: unknown): boolean {
  if (!toolUseResult || typeof toolUseResult !== "object") return false;
  const r = toolUseResult as { attachments?: unknown };
  if (!Array.isArray(r.attachments) || r.attachments.length === 0) return false;
  return r.attachments.every(
    (a) => !!a && typeof a === "object" && typeof (a as { path?: unknown }).path === "string",
  );
}

function codexLineId(
  x: { timestamp?: string; type?: string; payload?: { type?: string; call_id?: string } },
  text: string,
): string | null {
  const ts = x.timestamp ?? "";
  const kind = x.payload?.type ?? x.type ?? "";
  const call = x.payload?.call_id ?? "";
  const body = text.slice(0, 48);
  return ts || kind || call || body ? `${ts}:${kind}:${call}:${body}` : null;
}

function codexMessage(
  x: { timestamp?: string; type?: string; payload?: { type?: string; call_id?: string } },
  role: string,
  kind: SessionMsg["kind"],
  text: string,
  ts: number | null,
  suffix?: number,
): SessionMsg {
  const id = codexLineId(x, text);
  return { id: suffix && id ? `${id}#${suffix}` : id, role, kind, text, ts };
}

function mcpResultText(result: unknown): string {
  if (!result || typeof result !== "object" || Array.isArray(result)) return "";
  const tagged = result as { Ok?: unknown; Err?: unknown };
  if (tagged.Err != null) return String(tagged.Err).trim();
  if (!tagged.Ok || typeof tagged.Ok !== "object" || Array.isArray(tagged.Ok)) return "";
  const ok = tagged.Ok as { content?: unknown; isError?: unknown };
  if (!Array.isArray(ok.content)) return "";
  return ok.content
    .map((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) return "";
      const block = item as { type?: unknown; text?: unknown; uri?: unknown };
      if (block.type === "text" && typeof block.text === "string") return block.text.trim();
      if (block.type === "image") return "<image content>";
      if (block.type === "audio") return "<audio content>";
      if (typeof block.uri === "string") return `link: ${block.uri}`;
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function webSearchCellText(payload: Record<string, unknown>): string {
  const query = typeof payload.query === "string" ? payload.query : "";
  const action =
    payload.action && typeof payload.action === "object" && !Array.isArray(payload.action)
      ? (payload.action as Record<string, unknown>)
      : null;
  let detail = query;
  if (action) {
    const type = action.type;
    if (type === "search") {
      if (typeof action.query === "string" && action.query) detail = action.query;
      else if (Array.isArray(action.queries) && typeof action.queries[0] === "string") {
        detail = `${action.queries[0]}${action.queries.length > 1 ? " ..." : ""}`;
      }
    } else if (type === "open_page" && typeof action.url === "string") detail = action.url;
    else if (type === "find_in_page") {
      const pattern = typeof action.pattern === "string" ? `'${action.pattern}'` : "";
      const url = typeof action.url === "string" ? action.url : "";
      detail = [pattern, url].filter(Boolean).join(" in ");
    }
  }
  return `Searched the web${detail ? ` for ${detail}` : ""}`;
}

const CODEX_COLLABORATION_TOOLS = new Set([
  "spawn_agent",
  "send_message",
  "followup_task",
  "wait_agent",
  "list_agents",
  "interrupt_agent",
]);

const CODEX_MCP_BUILTINS = new Set([
  "list_mcp_resources",
  "list_mcp_resource_templates",
  "read_mcp_resource",
]);

function codexActivityMessage(
  x: { timestamp?: string; type?: string; payload?: { type?: string; call_id?: string } },
  text: string,
  ts: number | null,
  suffix = 0,
): SessionMsg {
  const message = codexMessage(x, "assistant", "tool_use", text, ts);
  return x.payload?.call_id
    ? { ...message, id: `codex-activity:${x.payload.call_id}${suffix ? `#${suffix}` : ""}` }
    : message;
}

function normalizeToolCall(
  x: { timestamp?: string; type?: string; payload?: { type?: string; call_id?: string } },
  name: string,
  namespace: string | undefined,
  source: string,
  args: Record<string, unknown> | null,
  ts: number | null,
  state: CodexNormalizationState,
  suffix = 0,
): SessionMsg | null {
  const callID = x.payload?.call_id;
  const remember = (disposition: CodexCallDisposition) => {
    if (callID) state.calls.set(callID, { disposition, tool: name, startedAt: ts });
  };
  if (namespace?.startsWith("mcp__") || CODEX_MCP_BUILTINS.has(name)) {
    remember("hide-output");
    const server = namespace?.replace(/^mcp__/, "") ?? "codex";
    const argumentText = source.trim();
    return codexActivityMessage(
      x,
      `Called ${server}.${name}${argumentText ? `(${argumentText})` : ""}`,
      ts,
    );
  }
  if (name === "apply_patch") {
    remember("hide-output");
    return null;
  }
  if (name === "web__run") {
    remember("hide-output");
    return codexMessage(x, "assistant", "tool_use", "Searching the web", ts, suffix);
  }
  if (name === "wait_agent") {
    remember("show-output");
    return codexMessage(x, "assistant", "tool_use", "Waiting for agents", ts, suffix);
  }
  if (CODEX_COLLABORATION_TOOLS.has(name)) {
    remember("hide-output");
    return null;
  }
  if (name === "update_plan") {
    remember("hide-output");
    return codexMessage(x, "assistant", "tool_use", planCellText(source, args), ts, suffix);
  }
  if (name === "view_image") {
    remember("hide-output");
    const path =
      (typeof args?.path === "string" ? args.path : null) ?? jsStringProperty(source, "path") ?? "";
    return codexActivityMessage(
      x,
      `Viewed Image${path ? `\n${displayCodexPath(path, state.cwd)}` : ""}`,
      ts,
      suffix,
    );
  }
  if (name === "exec_command") {
    remember("show-output");
    const command =
      (typeof args?.cmd === "string" ? args.cmd : null) ?? jsStringProperty(source, "cmd") ?? "";
    return codexActivityMessage(x, commandCellText(command), ts, suffix);
  }
  if (name === "wait") {
    remember("show-output");
    return null;
  }
  if (name === "write_stdin") {
    remember("show-output");
    const chars =
      (typeof args?.chars === "string" ? args.chars : null) ?? jsStringProperty(source, "chars");
    const text = `Interacted with background terminal${chars ? `\n${chars}` : ""}`;
    return codexMessage(x, "assistant", "tool_use", text, ts, suffix);
  }
  remember("show-output");
  const server = namespace?.replace(/^mcp__/, "");
  const qualified = server ? `${server}.${name}` : name;
  const argumentText = source.trim();
  return codexMessage(
    x,
    "assistant",
    "tool_use",
    `Called ${qualified}${argumentText ? `(${argumentText})` : ""}`,
    ts,
    suffix,
  );
}

function normalizeCodexLine(
  line: string,
  state: CodexNormalizationState,
): SessionMsg[] | null {
  let x: {
    timestamp?: string;
    type?: string;
    payload?: {
      [key: string]: unknown;
      type?: string;
      role?: string;
      content?: unknown;
      message?: string;
      name?: string;
      arguments?: string;
      input?: unknown;
      output?: unknown;
      summary?: Array<{ text?: string }>;
      call_id?: string;
      phase?: string;
      success?: boolean;
      stdout?: string;
      stderr?: string;
      changes?: unknown;
      namespace?: string;
      cwd?: string;
      invocation?: unknown;
      result?: unknown;
      action?: unknown;
      query?: string;
      kind?: string;
      agent_path?: string;
      event_id?: string;
      status?: string;
      revised_prompt?: string;
      saved_path?: string;
    };
  };
  try {
    x = JSON.parse(line);
  } catch {
    return null;
  }
  const ts = x.timestamp ? Date.parse(x.timestamp) : null;
  const p = x.payload;
  const codexTopLevel = new Set([
    "session_meta",
    "turn_context",
    "world_state",
    "inter_agent_communication_metadata",
    "compacted",
  ]);
  if (x.type === "session_meta") {
    if (typeof p?.cwd === "string") state.cwd = p.cwd;
    return [];
  }
  if (codexTopLevel.has(x.type ?? "")) return [];
  if (!p) return null;

  if (x.type === "event_msg") {
    if (p.type === "user_message" && p.message?.trim()) {
      const text = stripConversationPrefix(p.message.trim());
      return [codexMessage(x, "user", "text", text, ts)];
    }
    if (p.type === "patch_apply_end") {
      if (p.success === false) {
        const detail = p.stderr?.trim() || p.stdout?.trim() || "Patch failed";
        const text = `Failed to apply patch\n${detail}`;
        return [codexMessage(x, "tool", "tool_result", text, ts)];
      }
      const text = codexPatchChangesText(p.changes, state.cwd);
      return text ? [codexMessage(x, "assistant", "tool_use", text, ts)] : [];
    }
    if (p.type === "exec_command_end") {
      const parts = Array.isArray(p.command)
        ? p.command.filter((part): part is string => typeof part === "string")
        : [];
      const command =
        parts.length >= 3 && /(?:^|\/)\w*(?:ba|z|fi)?sh$/.test(parts[0]) && parts[1] === "-lc"
          ? parts.slice(2).join(" ")
          : parts.join(" ");
      if (!command) return [];
      const startedAt = p.call_id ? state.calls.get(p.call_id)?.startedAt : null;
      if (p.call_id) {
        state.calls.set(p.call_id, {
          disposition: "show-output",
          tool: "exec_command",
          startedAt: startedAt ?? ts,
        });
      }
      return [codexActivityMessage(x, commandCellText(command), startedAt ?? ts)];
    }
    if (p.type === "view_image_tool_call") {
      const path = typeof p.path === "string" ? p.path : "";
      const startedAt = p.call_id ? state.calls.get(p.call_id)?.startedAt : null;
      if (p.call_id) {
        state.calls.set(p.call_id, {
          disposition: "hide-output",
          tool: "view_image",
          startedAt: startedAt ?? ts,
        });
      }
      return [
        codexActivityMessage(
          x,
          `Viewed Image${path ? `\n${displayCodexPath(path, state.cwd)}` : ""}`,
          startedAt ?? ts,
        ),
      ];
    }
    if (p.type === "web_search_end") {
      const text = webSearchCellText(p);
      return [codexMessage(x, "assistant", "tool_use", text, ts)];
    }
    if (p.type === "mcp_tool_call_end") {
      const invocation =
        p.invocation && typeof p.invocation === "object" && !Array.isArray(p.invocation)
          ? (p.invocation as Record<string, unknown>)
          : {};
      const server = typeof invocation.server === "string" ? invocation.server : "mcp";
      const tool = typeof invocation.tool === "string" ? invocation.tool : "tool";
      const args = invocation.arguments == null ? "" : JSON.stringify(invocation.arguments);
      const title = `Called ${server}.${tool}${args ? `(${args})` : ""}`;
      const result = mcpResultText(p.result);
      const startedAt = p.call_id ? state.calls.get(p.call_id)?.startedAt : null;
      if (p.call_id) {
        state.calls.set(p.call_id, {
          disposition: "hide-output",
          tool,
          startedAt: startedAt ?? ts,
        });
      }
      return [codexActivityMessage(x, `${title}${result ? `\n${result}` : ""}`, startedAt ?? ts)];
    }
    if (p.type === "context_compacted") {
      return [codexMessage(x, "assistant", "tool_use", "Context compacted", ts)];
    }
    if (p.type === "plan_update") {
      return [codexMessage(x, "assistant", "tool_use", planCellText(JSON.stringify(p), p), ts)];
    }
    if (p.type === "error" && p.message?.trim()) {
      return [codexMessage(x, "system", "tool_result", p.message.trim(), ts)];
    }
    if ((p.type === "warning" || p.type === "guardian_warning") && p.message?.trim()) {
      return [codexMessage(x, "system", "tool_result", `Warning\n${p.message.trim()}`, ts)];
    }
    if (p.type === "deprecation_notice") {
      const notice = p as Record<string, unknown>;
      const summary = typeof notice.summary === "string" ? notice.summary.trim() : "";
      const details = typeof p.details === "string" ? p.details.trim() : "";
      const text = [summary, details].filter(Boolean).join("\n");
      return text ? [codexMessage(x, "system", "tool_result", text, ts)] : [];
    }
    if (p.type === "entered_review_mode") {
      const hint = typeof p.user_facing_hint === "string" ? p.user_facing_hint.trim() : "";
      return [
        codexMessage(
          x,
          "system",
          "tool_result",
          `Code review started${hint ? `: ${hint}` : ""}`,
          ts,
        ),
      ];
    }
    if (p.type === "exited_review_mode") {
      return [codexMessage(x, "system", "tool_result", "Code review finished", ts)];
    }
    if (p.type === "turn_aborted") {
      const text =
        "Conversation interrupted - tell the model what to do differently. " +
        "Something went wrong? Hit `/feedback` to report the issue.";
      return [codexMessage(x, "system", "tool_result", text, ts)];
    }
    if (p.type === "sub_agent_activity") {
      const verbs: Record<string, string> = {
        started: "Started",
        interacted: "Interacted with",
        interrupted: "Interrupted",
      };
      const verb = verbs[p.kind ?? ""];
      if (!verb || !p.agent_path) return [];
      const text = `${verb} \`${p.agent_path}\``;
      return [codexMessage(x, "assistant", "tool_use", text, ts)];
    }
    if (p.type === "image_generation_end") {
      const failed = p.status === "failed";
      const detail = p.revised_prompt?.trim() || p.call_id || "";
      const saved = typeof p.saved_path === "string" ? `\nSaved to: ${p.saved_path}` : "";
      const text = `${failed ? "Image generation failed" : "Generated Image:"}${detail ? `\n${detail}` : ""}${saved}`;
      return [codexMessage(x, "assistant", "tool_use", text, ts)];
    }
    return [];
  }
  if (x.type !== "response_item") return null;

  if (p.type === "message") {
    const role = p.role || "assistant";
    if (role === "system" || role === "developer" || role === "user") return [];
    const text = codexContentText(p.content).trim();
    return text ? [codexMessage(x, role, "text", text, ts)] : [];
  }
  if (p.type === "reasoning") {
    const text = (p.summary ?? [])
      .map((s) => s.text)
      .filter((s): s is string => !!s?.trim())
      .join("\n")
      .trim();
    return text ? [codexMessage(x, "assistant", "thinking", text, ts)] : [];
  }
  if (p.type === "local_shell_call") {
    const action =
      p.action && typeof p.action === "object" && !Array.isArray(p.action)
        ? (p.action as Record<string, unknown>)
        : null;
    const command = Array.isArray(action?.command)
      ? action.command.filter((part): part is string => typeof part === "string").join(" ")
      : "";
    return command ? [codexMessage(x, "assistant", "tool_use", commandCellText(command), ts)] : [];
  }
  if (p.type === "function_call" || p.type === "custom_tool_call") {
    const source = p.type === "custom_tool_call" ? describeInput(p.input) : (p.arguments ?? "");
    if (p.type === "custom_tool_call" && p.name === "exec") {
      const calls = innerCodexToolCalls(source);
      const messages: SessionMsg[] = [];
      let showOutput = false;
      for (const [index, call] of calls.entries()) {
        // Code Mode's MCP wrapper has a different outer call id from the
        // durable mcp_tool_call_end event. Rendering both creates two cells for
        // the one CLI activity, so let the durable event own this block.
        if (call.name.startsWith("mcp__")) continue;
        const nestedX = { ...x, payload: { ...p, call_id: p.call_id } };
        const inferredArgs =
          call.name === "exec_command" && !call.args
            ? (() => {
                const commands = jsStringArrayVariable(source, "cmds");
                return commands.length ? { cmd: commands.join(" && ") } : null;
              })()
            : call.args;
        const message = normalizeToolCall(
          nestedX,
          call.name,
          undefined,
          call.argumentSource,
          inferredArgs,
          ts,
          state,
          index,
        );
        if (message) messages.push(message);
        if (call.name === "exec_command" || call.name === "wait" || call.name === "write_stdin") {
          showOutput = true;
        }
      }
      if (p.call_id) {
        state.calls.set(p.call_id, {
          disposition: showOutput ? "show-output" : "hide-output",
          tool: calls.length === 1 ? calls[0].name : undefined,
          startedAt: ts,
        });
      }
      return messages;
    }
    const args = parseJsonObject(source);
    const message = normalizeToolCall(
      x,
      p.name ?? "tool",
      p.namespace,
      source,
      args,
      ts,
      state,
    );
    return message ? [message] : [];
  }
  if (p.type === "function_call_output" || p.type === "custom_tool_call_output") {
    const info = p.call_id ? state.calls.get(p.call_id) : undefined;
    if (p.call_id) state.calls.delete(p.call_id);
    if (info?.disposition === "hide-output") return [];
    const text = stripCodeModeEnvelope(codexOutputText(p.output));
    if (info?.tool === "wait_agent") {
      let detail = text;
      try {
        const parsed = JSON.parse(text) as { timed_out?: unknown; message?: unknown };
        if (parsed.timed_out === true) detail = "No agents completed yet";
        else if (parsed.timed_out === false) detail = "";
        else if (typeof parsed.message === "string") detail = parsed.message;
      } catch {}
      const result = `Finished waiting${detail ? `\n${detail}` : ""}`;
      return [codexMessage(x, "tool", "tool_result", result, ts)];
    }
    if (!text) return [];
    return [codexMessage(x, "tool", "tool_result", text, ts)];
  }
  // tool_search_* is provider plumbing; web_search_call, image_generation_call,
  // and context_compaction have a corresponding durable event_msg cell.
  return [];
}

export function normalizeLine(line: string): SessionMsg | null {
  return normalizeLineMessages(line)[0] ?? null;
}

export function normalizeLineMessages(
  line: string,
  codexState: CodexNormalizationState = createCodexNormalizationState(),
): SessionMsg[] {
  try {
    return normalizeLineUnsafe(line, codexState);
  } catch {
    return [];
  }
}

function collapseCodexLifecycleMessages(messages: SessionMsg[]): SessionMsg[] {
  const collapsed: SessionMsg[] = [];
  const indexById = new Map<string, number>();
  for (const message of messages) {
    if (!message.id?.startsWith("codex-activity:")) {
      collapsed.push(message);
      continue;
    }
    const existing = indexById.get(message.id);
    if (existing == null) {
      indexById.set(message.id, collapsed.length);
      collapsed.push(message);
    } else {
      // Keep the activity at its original transcript position while replacing
      // the in-progress form with the latest completed/failed form.
      collapsed[existing] = message;
    }
  }
  return collapsed;
}

function normalizeLineUnsafe(line: string, codexState: CodexNormalizationState): SessionMsg[] {
  const codex = normalizeCodexLine(line, codexState);
  if (codex) return codex;

  let x: {
    type?: string;
    timestamp?: string;
    uuid?: string;
    isApiErrorMessage?: boolean;
    // Structured error identity Claude Code writes alongside isApiErrorMessage.
    error?: string;
    apiErrorStatus?: number;
    isMeta?: boolean;
    toolUseResult?: unknown;
    message?: { role?: string; content?: unknown };
  };
  try {
    x = JSON.parse(line);
  } catch {
    return [];
  }
  if (x.type !== "assistant" && x.type !== "user" && x.type !== "system")
    return [];
  // Skip system-injected turns. Claude Code stamps `isMeta: true` on the
  // user-role lines it synthesizes — the full body of a launched skill, an
  // expanded slash command, the "Caveat:" preamble, local-command stdout. These
  // aren't conversation; surfacing them dumped the entire SKILL.md into the
  // client as a giant user bubble (and polluted the "last message" preview).
  // The canonical Claude UI hides them; match that.
  if (x.isMeta === true) return [];
  const m = x.message;
  if (!m) return [];
  const ts = x.timestamp ? Date.parse(x.timestamp) : null;
  const id = x.uuid ?? null;
  const role = m.role || x.type;
  // Genuine upstream API-error turn (vs. prose that merely quotes an error).
  const apiError = x.isApiErrorMessage === true ? true : undefined;
  const errorCode = typeof x.error === "string" && x.error ? x.error : undefined;
  const apiErrorStatus = typeof x.apiErrorStatus === "number" ? x.apiErrorStatus : undefined;
  if (typeof m.content === "string") {
    if (!m.content.trim()) return [];
    const text = role === "user" ? stripHumanPrefix(m.content) : m.content;
    return [{ id, role, kind: "text", text, ts, apiError, errorCode, apiErrorStatus }];
  }
  if (Array.isArray(m.content)) {
    const arr = m.content as Array<{
      type?: string;
      text?: string;
      thinking?: string;
      name?: string;
      input?: unknown;
      content?: unknown;
    }>;
    const msgs: SessionMsg[] = [];
    // If a text block in this turn already references a file path (e.g. a client
    // appended an upload path), skip the duplicate base64 attachment block.
    const hasFilePathInText = arr.some(
      (c) =>
        c.type === "text" &&
        !!c.text &&
        /\/[^\s)]+\.(png|jpe?g|gif|webp|pdf|mov|mp4|m4v|md|txt|csv|json|zip|docx?|xlsx?|pptx?)\b/i.test(
          c.text,
        ),
    );
    arr.forEach((c, idx) => {
      if (c.type === "text" && c.text) {
        const text = role === "user" ? stripHumanPrefix(c.text) : c.text;
        msgs.push({ id: blockId(id, idx), role, kind: "text", text, ts, apiError, errorCode, apiErrorStatus });
        return;
      }
      if (c.type === "thinking") {
        msgs.push({
          id: blockId(id, idx),
          role,
          kind: "thinking",
          text: c.thinking || "(thinking)",
          ts,
        });
        return;
      }
      if (c.type === "tool_use") {
        // A file the agent handed over renders as content, not as a tool call.
        const handoff = c.name === "SendUserFile" ? sendUserFileText(c.input) : null;
        if (handoff) {
          msgs.push({ id: blockId(id, idx), role, kind: "text", text: handoff, ts });
          return;
        }
        const input = describeInput(c.input);
        msgs.push({
          id: blockId(id, idx),
          role,
          kind: "tool_use",
          text: input ? `${c.name ?? "tool"}: ${input}` : `${c.name ?? "tool"}`,
          ts,
        });
        return;
      }
      if (c.type === "tool_result") {
        // The delivery receipt for a SendUserFile call restates paths already
        // shown as attachments — drop it rather than echo them as raw text.
        if (isSendUserFileResult(x.toolUseResult)) return;
        msgs.push({
          id: blockId(id, idx),
          role,
          kind: "tool_result",
          text: extractText(c.content) || "(result)",
          ts,
        });
        return;
      }
      // Any attached file (image, PDF/document, …) pasted or sent through the
      // CLI on the box. The transcript stores it as a base64 content block;
      // persist it once to a served location and surface it as a markdown link
      // so every client renders it as a tappable file attachment (fetchable via
      // /api/file). Skipped when a sibling text block already carries the path
      // (avoids a duplicate attachment for clients that upload-then-reference).
      if ((c.type === "image" || c.type === "document" || c.type === "file") && !hasFilePathInText) {
        const blk = c as { source?: { type?: string; data?: string; media_type?: string; path?: string }; name?: string };
        const src = blk.source;
        let path: string | null = null;
        let label: string | null = null;
        if (typeof src?.path === "string" && src.path) {
          path = src.path;
          label = basename(src.path);
        } else if (src?.type === "base64" && src.data) {
          const ext = extForMediaType(src.media_type, c.type);
          const dir = join(tmpdir(), "lfg-uploads");
          const safeId = (id || "blk").replace(/[^a-zA-Z0-9-]/g, "");
          const fp = join(dir, `blk-${safeId}-${idx}.${ext}`);
          try {
            if (!existsSync(fp)) {
              mkdirSync(dir, { recursive: true });
              writeFileSync(fp, Buffer.from(src.data, "base64"));
            }
            path = fp;
            label = typeof blk.name === "string" && blk.name ? blk.name : `attachment.${ext}`;
          } catch {
            path = null;
          }
        }
        if (path) {
          msgs.push({ id: blockId(id, idx), role, kind: "text", text: `[${label || basename(path)}](${path})`, ts });
        }
        return;
      }
    });
    return msgs;
  }
  return [];
}

/**
 * How far back a card preview is worth hunting for a human turn.
 *
 * This `pick` `JSON.parse`s and codex-normalizes every line it sees, so an
 * unbounded walk costs the whole file when there is no human turn to find —
 * exactly the shape of a long autonomous Codex run, whose rollouts here reach
 * 511 MB. One `listResumable` poll over that corpus peaked at 1.2 GB, and the
 * supervisor kills `lfg serve` at 4 GB, taking every /api/events stream with it.
 *
 * 32 MB clears every Claude transcript in the corpus outright and covers the
 * recent tail of the huge Codex ones. Past it the row shows no preview line,
 * which is a cosmetic loss on a handful of sessions; the alternative was a host
 * that reads as "disconnected" on the phone every few minutes.
 */
const LAST_USER_TEXT_SCAN_BYTES = 32 * 1024 * 1024;

// Last genuine user prompt — scan the tail backwards, skipping meta rows and
// command/caveat wrappers (lines starting with "<"). Truncated for the card.
async function lastUserText(path: string): Promise<string | null> {
  return scanBack(path, (line) => {
    let x: { type?: string; isMeta?: boolean; message?: { content?: unknown } };
    try {
      x = JSON.parse(line);
    } catch {
      return null;
    }
    const cm = normalizeCodexLine(line, createCodexNormalizationState())?.[0];
    if (cm?.role === "user" && cm.kind === "text") {
      const t = stripConversationPrefix(cm.text).trim().replace(/\s+/g, " ");
      if (t && !t.startsWith("<")) return t.length > 140 ? t.slice(0, 139) + "…" : t;
    }
    if (x.type !== "user" || x.isMeta) return null;
    let t = extractText(x.message?.content);
    if (!t) return null;
    t = stripHumanPrefix(t.trim().replace(/\s+/g, " "));
    if (!t || t.startsWith("<")) return null;
    return t.length > 140 ? t.slice(0, 139) + "…" : t;
  }, { maxScanBytes: LAST_USER_TEXT_SCAN_BYTES });
}

/**
 * The last `n` genuine user turns, oldest-first, each truncated to `maxChars`.
 *
 * `lastUserText` answers "what did they say" for a card; this answers "what is
 * this conversation ABOUT NOW", which needs several turns — the subject of a
 * long session drifts, and one turn is as likely to be "yes do that" as to name
 * the topic.
 *
 * The window GROWS, and that is the whole difficulty. Human turns are sparse in
 * an agentic session: measured on this corpus, a 2.4 MB transcript from a busy
 * session had ZERO human turns in its last 192 KB — the tail is all assistant
 * output and tool results, and the human's last message is megabytes back. A
 * fixed window silently returns "nothing to judge" for exactly the long sessions
 * whose titles drift most. So this widens like `scanBack` until it has `n` turns,
 * bounded by `maxBytes` so a huge transcript can't turn one call into a full read.
 */
export async function recentUserTurns(
  path: string,
  n = 6,
  {
    maxChars = 240,
    startBytes = 256 * 1024,
    maxBytes = 4 * 1024 * 1024,
  }: { maxChars?: number; startBytes?: number; maxBytes?: number } = {},
): Promise<string[]> {
  let bytes = Math.min(startBytes, maxBytes);
  let best: string[] = [];
  while (true) {
    let window: Awaited<ReturnType<typeof tail>>;
    try {
      window = await tail(path, bytes);
    } catch {
      return best;
    }
    best = collectUserTurns(window.lines, n, maxChars);
    if (best.length >= n || window.atHead || bytes >= maxBytes) return best;
    bytes = Math.min(bytes * 4, maxBytes);
  }
}

/** Newest-last list of genuine human turns found in `lines`. */
function collectUserTurns(lines: string[], n: number, maxChars: number): string[] {
  const out: string[] = [];
  for (let i = lines.length - 1; i >= 0 && out.length < n; i--) {
    const line = lines[i];
    let x: {
      type?: string;
      isMeta?: boolean;
      toolUseResult?: unknown;
      message?: { content?: unknown };
    };
    try {
      x = JSON.parse(line);
    } catch {
      continue;
    }
    let t: string | null = null;
    const cm = normalizeCodexLine(line, createCodexNormalizationState())?.[0];
    if (cm?.role === "user" && cm.kind === "text") {
      t = stripConversationPrefix(cm.text).trim().replace(/\s+/g, " ");
    } else if (x.type === "user" && !x.isMeta) {
      // A tool result is recorded as a `user` turn. `extractText` drops the
      // `tool_result` blocks themselves, but a record can carry a stray text
      // block alongside — so exclude the record outright rather than trusting
      // the content shape. These outnumber real turns by an order of magnitude.
      if (x.toolUseResult !== undefined) continue;
      const raw = extractText(x.message?.content);
      t = raw ? stripHumanPrefix(raw.trim().replace(/\s+/g, " ")) : null;
    }
    // "<" opens the command/caveat wrappers Claude Code injects as user turns
    // (`<command-name>`, `<local-command-stdout>`); they are machinery, not the
    // human, and they'd otherwise dominate the digest of an active session.
    if (!t || t.startsWith("<")) continue;
    out.push(t.length > maxChars ? t.slice(0, maxChars - 1) + "…" : t);
  }
  return out.reverse();
}

// The full (untruncated) text of the last genuine user turn, whitespace-collapsed.
// Used to disambiguate the pane-scraped prompt "context": when the assistant
// preamble's "⏺" bullet has scrolled off, the block above the selector could be
// the preamble OR the user's own scrolled-off prompt — matching it against this
// tells them apart. Returns null when there's no user turn to compare.
export async function lastUserPromptText(path: string): Promise<string | null> {
  return scanBack(path, (line) => {
    let x: { type?: string; isMeta?: boolean; message?: { content?: unknown } };
    try {
      x = JSON.parse(line);
    } catch {
      return null;
    }
    const cm = normalizeCodexLine(line, createCodexNormalizationState())?.[0];
    if (cm?.role === "user" && cm.kind === "text") {
      const t = stripConversationPrefix(cm.text).trim().replace(/\s+/g, " ");
      if (t && !t.startsWith("<")) return t;
    }
    if (x.type !== "user" || x.isMeta) return null;
    let t = extractText(x.message?.content);
    if (!t) return null;
    t = stripHumanPrefix(t.trim().replace(/\s+/g, " "));
    if (!t || t.startsWith("<")) return null;
    return t;
  });
}

// Collapse a full model id (e.g. "claude-opus-5", "claude-haiku-4-5") to
// the short alias lfg uses everywhere (the same tokens the `/model` command
// and the model picker speak). Returns the raw value if it matches no family.
function modelAlias(id: string | null | undefined): string | null {
  if (!id) return null;
  const m = id.toLowerCase();
  if (m.includes("opus")) return "opus";
  if (m.includes("sonnet")) return "sonnet";
  if (m.includes("haiku")) return "haiku";
  if (m.includes("fable")) return "fable";
  return id;
}

export function managedFieldsForTmuxName(
  tmuxName: string | null | undefined,
  managedByName: Map<string, ManagedSession>,
): { managed: boolean; parentSessionId?: string } {
  const rec = tmuxName ? managedByName.get(tmuxName) : undefined;
  return rec?.parentSessionId
    ? { managed: !!rec, parentSessionId: rec.parentSessionId }
    : { managed: !!rec };
}

// The model of the most recent assistant turn. Claude stamps every assistant
// line with `message.model`, so the tail tells us the *live* model even after a
// mid-session `/model` switch (the launch `--model` arg goes stale). Returns
// null for a session that hasn't produced an assistant turn yet.
async function lastAssistantModel(path: string): Promise<string | null> {
  return scanBack(path, (line) => {
    let x: { type?: string; message?: { model?: string } };
    try {
      x = JSON.parse(line);
    } catch {
      return null;
    }
    return x.type === "assistant" && x.message?.model ? x.message.model : null;
  });
}

// The model a codex rollout is running on. Codex writes no per-message model
// (unlike Claude's `message.model`) — it stamps one `turn_context` row per turn
// carrying the model that turn used, so the newest one is the live model even
// after a mid-session `/model` switch. A TUI codex launched with no `--model`
// arg (the common case: `codex --yolo`) has NOTHING else to read it from, which
// is why the list row showed no model at all for codex sessions. Returns null
// before the first turn — the launch arg is the caller's fallback.
export async function lastCodexModel(path: string): Promise<string | null> {
  return scanBack(path, (line) => {
    let x: { type?: string; payload?: { model?: string } };
    try {
      x = JSON.parse(line);
    } catch {
      return null;
    }
    return x.type === "turn_context" && x.payload?.model ? x.payload.model : null;
  });
}

// The short model alias (opus/sonnet/…) a now-closed session last ran on, read
// straight from its transcript. Used when auto-resuming a session on a send so
// it relaunches on the same model the conversation was using rather than the
// opus default. null when the transcript has no assistant turn yet.
export async function modelAliasForTranscript(path: string): Promise<string | null> {
  return modelAlias(await lastAssistantModel(path));
}

async function previewLast(path: string): Promise<SessionMsg | null> {
  return scanBack(path, (line) => {
    const msgs = normalizeLineMessages(line);
    return msgs.length ? msgs[msgs.length - 1] : null;
  });
}

// The newest ASSISTANT turn — what `computeStatus` classifies. Separate from
// `previewLast` (newest message of any role, which is what the list previews)
// because the two answer different questions and conflating them is what let a
// user row erase a session's blocked status. `scanBack` grows its window on a
// miss, so this reaches past a run of user/attachment rows.
async function lastAssistantMsg(path: string): Promise<SessionMsg | null> {
  return scanBack(path, (line) => {
    const msgs = normalizeLineMessages(line);
    for (let i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role === "assistant") return msgs[i];
    }
    return null;
  });
}

// Coalesce + briefly cache the session scan. The whole enrichment pass is a
// burst of synchronous `ps`/`lsof`/`tmux` spawns that freeze the single event
// loop; every poll AND every mutating route (send/resume/model) triggers it.
// Without coalescing, an in-flight poll and a concurrent send each launch the
// storm and pile up — the send's HTTP round-trip blows past the client timeout
// and the message appears to hang ("can't send to an idle session"). This
// returns the in-flight promise to concurrent callers and reuses a fresh result
// for a short window, so overlapping requests share one scan.
// How long a COMPLETED scan is served before a new one runs. Measured from the
// moment the scan settles, not the moment it starts: stamping the start meant a
// scan slower than the TTL burned its own cache window, so the cache never once
// served a finished result and a fresh overlapping scan launched every TTL
// forever. On a busy host (49 sessions) that was ~6 concurrent scans, each
// re-running the whole ps/lsof/tmux fan-out and slowing the others.
const LIST_TTL_MS = 1_500;
// Backstop for a scan that never settles (a wedged `tmux`/`lsof` child). Callers
// share an in-flight scan with no TTL — that's what kills the pile-up — so a hang
// would otherwise block every caller forever with no way to retry. Past this, a
// new caller is allowed to start a fresh scan.
const LIST_INFLIGHT_MAX_MS = 15_000;
type ListCacheEntry = {
  startedAt: number;
  /** null while the scan is in flight; set when it settles (ok or error). */
  settledAt: number | null;
  promise: Promise<Session[]>;
};
let listCache: ListCacheEntry | null = null;
// Last successful scan. The enrichment fans out dozens of synchronous
// `Bun.spawnSync` calls (ps/lsof/tmux), and under a spawn storm — many SSE
// pollers + a list request landing on the single event loop at once — spawnSync
// can throw `RangeError: Maximum call stack size exceeded`. At the stack limit
// that error escapes the inner try/catch in spawnText(), so the whole scan
// rejects. Serving the last good result (rather than propagating) keeps the
// list view from flashing a 500 during a transient storm; the next poll, a few
// hundred ms later, almost always succeeds.
let lastGood: Session[] | null = null;
export function listSessions(): Promise<Session[]> {
  const now = Date.now();
  if (listCache) {
    // In flight → always share it, regardless of TTL. Two scans of the same host
    // can only make each other slower, and the old start-stamped TTL guaranteed
    // exactly that once a scan outran it.
    if (listCache.settledAt == null) {
      if (now - listCache.startedAt < LIST_INFLIGHT_MAX_MS) return listCache.promise;
      // Wedged past the backstop — fall through and start a fresh scan.
    } else if (now - listCache.settledAt < LIST_TTL_MS) {
      // Settled and still fresh → resolved promise, returns immediately.
      return listCache.promise;
    }
  }
  // A rejected scan must not be served stale for the whole TTL — drop the cache
  // so the next caller retries — but don't surface the throw to the client if we
  // have a recent good result to fall back to. The cache holds this guarded
  // promise so overlapping callers share the same fallback.
  const entry = { startedAt: now, settledAt: null } as ListCacheEntry;
  entry.promise = listSessionsUncached()
    .then((sessions) => {
      lastGood = sessions;
      return sessions;
    })
    .catch((e) => {
      if (listCache === entry) listCache = null;
      if (lastGood) return lastGood;
      throw e;
    })
    .finally(() => {
      entry.settledAt = Date.now();
    });
  listCache = entry;
  return entry.promise;
}

async function listSessionsUncached(): Promise<Session[]> {
  // Drop just-closed sessions up front (see closing.ts): /close kills the
  // process but it lingers for a poll or two, so without this a stopped session
  // flickers back into the list until pgrep stops seeing it.
  // Live "aisdk" harness sessions (the AI-SDK driven kind). Each harness drives a
  // child `claude` process via the SDK, which pgrep would otherwise surface as a
  // phantom duplicate session — filter those out by parent pid (and, as a
  // backstop, by the aisdk sessionId) so only the single aisdk session shows.
  // Refresh the ps snapshot off the event loop before anything reads it (the
  // ppidOf filter below, then listProcs/startTimeMsOf/commOf). Keeps the one
  // per-scan `ps` from blocking HTTP while a cold scan runs under load.
  await primeProcSnapshot();
  const aisdkEntries = listAisdkEntries().filter((e) => isPidAlive(e.harnessPid));
  const harnessPids = new Set(aisdkEntries.map((e) => e.harnessPid));
  const aisdkSessionIds = new Set(aisdkEntries.map((e) => e.sessionId));
  const claudeProcs = listClaudeProcs().filter(
    (p) => !isClosing(p.pid) && !harnessPids.has(ppidOf(p.pid) ?? -1),
  );
  // Batch-prime every candidate proc's cwd with a single `lsof` so the per-pid
  // cwdOf() calls in the claude + codex enrichment below hit the cache instead
  // of each spawning their own lsof — the largest single contributor to the
  // synchronous spawn storm. Codex pids are cheap to enumerate here (they read
  // the shared ps snapshot, no extra spawn).
  await primeCwds([
    ...claudeProcs.map((p) => p.pid),
    ...listCodexProcs().map((p) => p.pid),
  ]);
  const enriched = await Promise.all(
    claudeProcs.map(async (p) => {
      let cwd: string | null = await cwdOf(p.pid);
      let startedAt: number | null = startTimeMsOf(p.pid);
      // Prefer the authoritative ~/.claude/sessions/<pid>.json; the --resume
      // arg is stale and the newest-unclaimed heuristic can't disambiguate
      // multiple concurrent sessions sharing one cwd.
      const ps = readPidSession(p.pid);
      let sessionId: string | null = ps?.sessionId ?? null;
      // Authoritative = pid→sessionId came from the pidfile, so the live pane
      // we resolve for this pid is *known* to be running this session. The
      // --resume arg and the newest-unclaimed heuristic are guesses: the pane
      // may actually be running a different session (e.g. a long-lived
      // bare-`claude` that has moved on to other work). We only trust the
      // tmux target — for prompt detection and send-keys — when authoritative.
      const authoritative = !!ps?.sessionId;
      if (!sessionId) {
        const sm = p.cmd.match(
          new RegExp(`(?:--resume|-r)\\s+(${UUID.source})`),
        );
        sessionId = sm ? sm[1] : null;
      }
      if (ps?.cwd) cwd = ps.cwd;
      return { ...p, cwd, startedAt, sessionId, authoritative, boundAt: ps?.boundAt ?? null };
    }),
  );

  const claimed = new Set<string>(
    enriched.filter((e) => e.sessionId).map((e) => e.sessionId as string),
  );
  // Reserve aisdk transcripts so the newest-unclaimed-in-cwd heuristic can't
  // bind an unrelated bare `claude` in the same cwd to an aisdk session's
  // (freshly written) transcript — which would surface it as a phantom claude
  // duplicate of the aisdk session.
  for (const id of aisdkSessionIds) claimed.add(id);

  // pid → how that process came by its sessionId, for the collision tiebreak in
  // resolveSessionOwners. Kept as a side map rather than a Session field so the
  // REST payload stays byte-identical for clients.
  const claimByPid = new Map<number, SessionClaim>();
  for (const e of enriched) {
    claimByPid.set(e.pid, { authoritative: e.authoritative, boundAt: e.boundAt });
  }

  const overrides = await readTitleOverrides();
  const assigns = userAssignments();
  const delegatedSessionIds = codexDelegationSessionIds();
  const managedByName = new Map(listManaged().map((m) => [m.tmuxName, m] as const));
  const out: Session[] = [];
  for (const e of enriched) {
    let transcriptPath: string | null = null;
    let sessionId = e.sessionId;
    // Backstop for the phantom-child filter above: if this claude proc resolved
    // to an aisdk session's id, it's the harness's child — skip it (the aisdk
    // session is added separately with its own control plane).
    if (sessionId && aisdkSessionIds.has(sessionId)) continue;
    if (sessionId) {
      transcriptPath = await findTranscriptById(sessionId);
    } else if (e.cwd) {
      const r = await newestUnclaimedInCwd(e.cwd, claimed);
      if (r) {
        transcriptPath = r.path;
        sessionId = r.id;
        claimed.add(r.id);
      }
    }
    let last: SessionMsg | null = null;
    let lastAssistant: SessionMsg | null = null;
    let lastActivityAt: number | null = null;
    let lastUser: string | null = null;
    let liveModel: string | null = null;
    if (transcriptPath) {
      // lastActivityAt means CONVERSATION activity, so it comes from the last
      // message's timestamp, not the file mtime. The transcript dir is synced
      // between hosts and the sync daemon rewrites mtimes hourly with no
      // content change (see .claude/diagnosis-idle-sessions-show-unread.md),
      // which made idle sessions resurface as Unread and flash busy for 12s.
      // mtime remains the fallback for a transcript with no parseable message.
      let mtimeMs: number | null = null;
      try {
        mtimeMs = statSync(transcriptPath).mtimeMs;
      } catch {}
      last = await previewLast(transcriptPath).catch(() => null);
      lastActivityAt = last?.ts ?? mtimeMs;
      lastUser = await lastUserText(transcriptPath).catch(() => null);
      liveModel = await lastAssistantModel(transcriptPath).catch(() => null);
      lastAssistant = await lastAssistantMsg(transcriptPath).catch(() => null);
    }
    // Prefer the transcript's live model; fall back to the launch `--model` arg
    // (always present on a lfg-managed session, so the badge shows instantly
    // before the first assistant turn).
    const model = modelAlias(liveModel) ?? modelAlias(e.cmd.match(/--model\s+(\S+)/)?.[1]);
    const health = computeStatus(lastAssistant, liveModel);
    const project = projectName(e.cwd);
    let title = (sessionId && overrides[sessionId]) || null;
    if (!title && transcriptPath) title = await firstPromptTitle(transcriptPath);
    if (!title) title = e.cwd ? basename(e.cwd) : project;
    const tmuxTarget =
      isHeadless(e.cmd) || !e.authoritative ? null : tmuxTargetForPid(e.pid);
    const tmuxName = tmuxTarget ? tmuxTarget.split(":")[0] : null;
    const transcriptRecent =
      lastActivityAt != null && Date.now() - lastActivityAt < REST_BUSY_WINDOW_MS;
    const delegated = sessionId ? delegatedSessionIds.has(sessionId) : false;
    const paneBusy = sessionId ? lastPaneBusy(sessionId) : null;
    // The agent's own turn boundary beats the pane scrape when it has an opinion
    // (see turn-state.ts — the pane can be spoofed by an agent's own output).
    // Pane-backed sessions ONLY: a live pane is the proof the process still
    // exists. Without it, a transcript that simply ends mid-turn — crashed, or a
    // stale row sitting on a recycled pid — would read "running" forever, which
    // is the exact latch this change exists to remove.
    //
    // `sessionTurnState`, not `transcriptTurnState`: this site used to read the
    // transcript alone while `journal-pump.ts` read hook+transcript, so the REST
    // baseline and the SSE journal derived `busy` from different inputs and could
    // disagree about the same session. It also carries the stall guard, and a
    // guard only one of the two consumers has is not a guard.
    const turn =
      tmuxTarget && transcriptPath
        ? await sessionTurnState({ sessionId, transcriptPath })
        : null;
    out.push({
      agent: "claude",
      pid: e.pid,
      cmd: e.cmd,
      cwd: e.cwd,
      project,
      title,
      lastUserText: lastUser,
      sessionId,
      startedAt: e.startedAt,
      transcriptPath,
      lastActivityAt,
      busy: resolveBusy({ verdict: turn, paneBusy: paneBusy ?? transcriptRecent, delegated }),
      last,
      // A headless `claude -p` (the report runner, or a dispatched agent
      // before it moved to its own tmux session) is a *descendant* of
      // whatever pane lfg runs in, so walking its parent chain resolves to
      // that unrelated pane. It has no TUI to drive — never give it a target.
      // We also withhold the target when the sessionId was *guessed* (no
      // pidfile): the resolved transcript and the live pane can be two
      // different conversations, so a prompt read from / message sent to that
      // pane would hit the wrong session.
      tmuxTarget,
      tmuxName,
      ...managedFieldsForTmuxName(tmuxName, managedByName),
      assignedUser: tmuxName ? (assigns[tmuxName] ?? null) : null,
      model,
      status: health.status,
      statusReason: health.statusReason,
      statusDetail: health.statusDetail,
    });
  }

  const codex = await codexThreads();
  const claimedCodex = new Set<string>();
  // codex-aisdk harnesses each spawn a `codex app-server --listen stdio://`
  // child that pgrep WILL surface (basename is `codex`). It's the AI-SDK
  // session's engine, not a standalone TUI codex — so (1) skip the app-server
  // process below, and (2) reserve the codex-aisdk threadIds here so the
  // cwd+prompt fallback can't bind one of their rollout transcripts to an
  // unrelated bare codex in the same cwd. Both guard against the codex-aisdk
  // session being listed twice (once here as a phantom, once via the registry).
  for (const e of aisdkEntries) {
    if (e.agent === "codex" && e.threadId) claimedCodex.add(e.threadId);
  }
  for (const p of listCodexProcs()) {
    if (isClosing(p.pid)) continue; // just-closed — keep it out of the list
    // The app-server child of a codex-aisdk harness — not a user-facing codex
    // session. Its argv is `codex app-server --listen stdio://` (no resume id,
    // no `--` prompt), so it would otherwise show as a bare, transcript-less
    // phantom alongside the registry-driven codex-aisdk entry.
    if (/\bapp-server\b/.test(p.cmd)) continue;

    let cwd: string | null = await cwdOf(p.pid);
    let startedAt: number | null = startTimeMsOf(p.pid);
    const tmuxTarget = tmuxTargetForPid(p.pid);
    const tmuxName = tmuxTarget ? tmuxTarget.split(":")[0] : null;
    const managedRec = tmuxName ? managedByName.get(tmuxName) : undefined;
    const managedCodex = managedRec?.agent === "codex" ? managedRec : undefined;
    const resumeId =
      managedCodex?.sessionId ??
      p.cmd.match(new RegExp(`(?:^|\\s)resume\\s+(${UUID.source})`))?.[1] ??
      null;
    const forkedFromId =
      managedCodex && !managedCodex.sessionId
        ? managedCodex.forkedFrom ?? null
        : p.cmd.match(new RegExp(`(?:^|\\s)fork\\s+(${UUID.source})`))?.[1] ?? null;
    // Codex resume appends to an old rollout, so it MUST bind by the id we
    // already know. Falling through to pickCodexThread would reject that rollout
    // on the createdAt skew guard and make the live session disappear on re-scan.
    let sessionId = resumeId;
    let thread = pickKnownCodexThread(sessionId, codex, claimedCodex);
    // Codex fork mints a new rollout whose session_meta links back to the
    // source id. Bind that exact parent link before any cwd/prompt heuristic;
    // two forks from one parent disambiguate by each pane's spawn time plus the
    // claimed set.
    if (!thread) {
      thread = pickCodexForkThread(
        { forkedFromId, spawnedAt: managedCodex?.createdAt ?? startedAt },
        codex,
        claimedCodex,
      );
      if (thread) {
        sessionId = thread.id;
        if (managedCodex && !managedCodex.sessionId) {
          patchManaged(managedCodex.tmuxName, { sessionId: thread.id });
        }
      }
    }
    const prompt = codexPromptFromCmd(p.cmd);
    if (!thread) {
      thread = pickCodexThread({ cwd, startedAt, prompt }, codex, claimedCodex);
      if (thread) sessionId = thread.id;
    }
    if (thread) {
      claimedCodex.add(thread.id);
      if (thread.cwd) cwd = thread.cwd;
    }

    const transcriptPath = thread?.path ?? (sessionId ? await findCodexTranscriptById(sessionId) : null);
    let last: SessionMsg | null = null;
    let lastActivityAt: number | null = null;
    let lastUser: string | null = null;
    let liveModel: string | null = null;
    if (transcriptPath) {
      // Conversation activity from the last message's ts, mtime only as
      // fallback — same rationale as the claude site above (synced mtimes lie).
      let mtimeMs: number | null = null;
      try {
        mtimeMs = statSync(transcriptPath).mtimeMs;
      } catch {}
      last = await previewLast(transcriptPath).catch(() => null);
      lastActivityAt = last?.ts ?? mtimeMs;
      lastUser = await lastUserText(transcriptPath).catch(() => null);
      liveModel = await lastCodexModel(transcriptPath).catch(() => null);
    }
    const project = projectName(cwd);
    let title = (sessionId && overrides[sessionId]) || null;
    if (!title && transcriptPath) title = await firstPromptTitle(transcriptPath);
    if (!title) title = cwd ? basename(cwd) : project;
    const transcriptRecent =
      lastActivityAt != null && Date.now() - lastActivityAt < REST_BUSY_WINDOW_MS;
    const delegated = sessionId ? delegatedSessionIds.has(sessionId) : false;
    const paneBusy = sessionId ? lastPaneBusy(sessionId) : null;
    // Match the journal pump's turn-state stack. In particular, Codex's pane can
    // briefly scrape as idle while its rollout still has an open `task_started`.
    // Letting that raw false become the REST baseline made the iOS client's next
    // poll fight the live journal and flip a genuinely running turn to Idle.
    const turn =
      tmuxTarget && transcriptPath
        ? await sessionTurnState({ sessionId, transcriptPath })
        : null;
    out.push({
      agent: "codex",
      pid: p.pid,
      cmd: p.cmd,
      cwd,
      project,
      title,
      lastUserText: lastUser,
      sessionId,
      startedAt,
      transcriptPath,
      lastActivityAt,
      busy: resolveBusy({ verdict: turn, paneBusy: paneBusy ?? transcriptRecent, delegated }),
      last,
      tmuxTarget,
      tmuxName,
      ...managedFieldsForTmuxName(tmuxName, managedByName),
      assignedUser: tmuxName ? (assigns[tmuxName] ?? null) : null,
      // Prefer the rollout's live model (`turn_context`), fall back to the
      // launch arg — a TUI codex is usually started bare (`codex --yolo`), so
      // the arg alone left the row with no model at all. Names are surfaced
      // verbatim: codex slugs are catalog-driven, not the Claude aliases.
      model: liveModel ?? p.cmd.match(/--model\s+(\S+)/)?.[1] ?? null,
      ...computeStatus(last, null),
    });
  }

  // "aisdk" sessions: headless AI-SDK harnesses. Discovery is registry-driven
  // (not pgrep) — the harness owns the control plane and the SDK writes the same
  // transcript JSONL as a normal claude session, so the live view reads it as-is.
  // tmuxName is set (supervisor → kill + managed badge) but tmuxTarget is null
  // (send/interrupt route through the command file, not the pane).
  for (const e of aisdkEntries) {
    const isCodex = e.agent === "codex";
    // opencode entries own a SELF-WRITTEN Claude-shaped transcript named by the
    // control-plane key (the harness writes no codex rollout) — so they discover
    // exactly like a Claude aisdk entry: transcript by sessionId, raw model.
    const isOpencode = e.agent === "opencode";
    // Claude/opencode entries name their transcript by the (deterministic)
    // sessionId. Codex entries persist a rollout under ~/.codex/sessions keyed by
    // the app-server threadId, which we only know after turn 1 — so the transcript
    // is null until then, and the live-view id is the threadId once available
    // (deep-links straight to the rollout) else the control-plane key.
    let codexThreadId = isCodex ? (e.threadId ?? null) : null;
    if (isCodex && !codexThreadId) {
      const inferred = inferCodexThreadForHarness(e, codex, claimedCodex);
      if (inferred) {
        codexThreadId = inferred.id;
        claimedCodex.add(inferred.id);
        patchAisdkEntry(e.sessionId, { threadId: inferred.id });
      }
    }
    const transcriptPath = isCodex
      ? codexThreadId
        ? await findCodexTranscriptById(codexThreadId)
        : null
      : await findTranscriptById(e.sessionId);
    const sessionId = isCodex ? (codexThreadId ?? e.sessionId) : e.sessionId;
    let last: SessionMsg | null = null;
    let lastActivityAt: number | null = null;
    let lastUser: string | null = null;
    if (transcriptPath) {
      // Conversation activity from the last message's ts, mtime only as
      // fallback — same rationale as the claude site above (synced mtimes lie).
      let mtimeMs: number | null = null;
      try {
        mtimeMs = statSync(transcriptPath).mtimeMs;
      } catch {}
      // The transcript helpers handle BOTH claude JSONL and codex rollouts
      // (normalizeCodexLine is tried first inside each), so they're safe for a
      // codex rollout path too. Guarded with .catch — never throw out of here.
      last = await previewLast(transcriptPath).catch(() => null);
      lastActivityAt = last?.ts ?? mtimeMs;
      lastUser = await lastUserText(transcriptPath).catch(() => null);
    }
    const project = projectName(e.cwd);
    let title = overrides[sessionId] || null;
    if (!title && transcriptPath)
      title = await firstPromptTitle(transcriptPath).catch(() => null);
    if (!title) title = e.title || (e.cwd ? basename(e.cwd) : project);
    let startedAt: number | null = startTimeMsOf(e.harnessPid) ?? e.createdAt;
    const delegated = delegatedSessionIds.has(sessionId);
    out.push({
      agent: isCodex ? "codex-aisdk" : isOpencode ? "opencode" : "aisdk",
      pid: e.harnessPid,
      cmd: isCodex
        ? `lfg codex-aisdk-session --model ${e.model}`
        : isOpencode
          ? `lfg opencode-aisdk-session --model ${e.model}`
          : `lfg aisdk-session --model ${e.model}`,
      cwd: e.cwd,
      project,
      title,
      lastUserText: lastUser,
      sessionId,
      startedAt,
      transcriptPath,
      lastActivityAt,
      // Headless harness: the registry tracks an accurate per-turn busy flag.
      busy: e.busy || delegated,
      last,
      // No pane I/O — but keep the supervisor name so kill + managed badge work.
      tmuxTarget: null,
      tmuxName: e.tmuxName || null,
      ...managedFieldsForTmuxName(e.tmuxName, managedByName),
      assignedUser: e.tmuxName ? (assigns[e.tmuxName] ?? null) : null,
      // Codex slugs and opencode "provider/model" ids aren't Claude aliases —
      // pass them through raw. modelAlias would leave them unchanged anyway, but
      // be explicit about intent.
      model: isCodex || isOpencode ? e.model : modelAlias(e.model),
      ...computeStatus(last, null),
    });
  }
  // Order by start time (stable), not recency: sorting by lastActivityAt made
  // panes reshuffle every time a session became the most-active one. startedAt
  // never changes for a live session, so positions stay put and a new session
  // just appends at the end. sessionId breaks ties deterministically.
  out.sort(
    (a, b) =>
      (a.startedAt ?? 0) - (b.startedAt ?? 0) ||
      (a.sessionId ?? "").localeCompare(b.sessionId ?? ""),
  );
  const deduped = resolveSessionOwners(out, (pid) => claimByPid.get(pid) ?? null);
  resolvePaneOwners(deduped);
  return deduped;
}

/**
 * One sessionId, one row. Drops every row but the rightful owner when two live
 * processes claim the same session.
 *
 * THIS IS NOT HYPOTHETICAL, and it is not the pane collision `resolvePaneOwners`
 * handles — these are different pids in different panes, each with its own
 * authoritative `~/.claude/sessions/<pid>.json` naming the same sessionId (an
 * in-TUI `/resume` of a session another live process is already on will do it).
 *
 * A duplicate id is corrupting rather than merely untidy, because sessionId is
 * the key for essentially everything downstream: the push watcher's per-session
 * `prior` map, journal delta baselines, unread state, leases, sendq. In the push
 * watcher the two rows overwrite each other's memory every tick, so their
 * differing observations read as a state change — one pane idle at the composer
 * and one pane sitting on an AskUserQuestion produced a "needs input" push every
 * ~12s, forever, for a session nobody had asked anything of.
 *
 * There are two collision shapes and they want OPPOSITE tiebreaks, which is why
 * this takes the claim and not just a timestamp:
 *
 *  - Both claims AUTHORITATIVE (each pid's own pidfile names the id). The later
 *    binding is the live one — a `/resume` takes the session over — so newest
 *    `boundAt` wins. This is the reelly case.
 *  - Claims GUESSED (no readable pidfile yet, so the id came from the `--resume`
 *    arg or newest-unclaimed-in-cwd). `claude --resume X --fork-session` forks
 *    carry X on the command line while genuinely owning a *different* id, so for
 *    the first moments of a fork's life every fork looks like the parent. Here
 *    the OLDEST process is the real owner and the newcomers are the forks, so
 *    oldest `startedAt` wins — and a guess never beats an authoritative claim.
 *
 * Every term is immutable for a given process, so the winner cannot flap between
 * ticks — which matters, since a flapping winner would recreate the exact
 * phantom-transition storm this exists to remove. Exported for tests.
 */
export type SessionClaim = { authoritative: boolean; boundAt: number | null };

export function resolveSessionOwners(
  sessions: Session[],
  claimOf: (pid: number) => SessionClaim | null = () => null,
): Session[] {
  const byId = new Map<string, Session[]>();
  for (const s of sessions) {
    if (!s.sessionId) continue;
    const g = byId.get(s.sessionId);
    if (g) g.push(s);
    else byId.set(s.sessionId, [s]);
  }
  const losers = new Set<Session>();
  for (const [sessionId, group] of byId) {
    if (group.length <= 1) continue;
    // Ranked descending: bigger tuple wins. `startedAt` is NEGATED for guesses so
    // the same "bigger wins" comparison expresses oldest-first for them.
    const rank = (s: Session): [number, number, number] => {
      const claim = claimOf(s.pid);
      return claim?.authoritative
        ? [1, claim.boundAt ?? s.startedAt ?? 0, -s.pid]
        : [0, -(s.startedAt ?? 0), -s.pid];
    };
    const winner = group.reduce((a, b) => {
      const ra = rank(a);
      const rb = rank(b);
      for (let i = 0; i < ra.length; i++) if (rb[i]! !== ra[i]!) return rb[i]! > ra[i]! ? b : a;
      return a;
    });
    console.warn(
      `[sessions] ${group.length} live processes claim session ${sessionId} (pids ${group
        .map((g) => g.pid)
        .join(", ")}) — keeping pid ${winner.pid}`,
    );
    for (const s of group) if (s !== winner) losers.add(s);
  }
  return losers.size ? sessions.filter((s) => !losers.has(s)) : sessions;
}

// One pane, one sendable session. Several pids routinely resolve to the same
// pane — a Claude TUI spawns a transient daemon, bg-pty-host/bg-spare workers,
// and (in branch view) the detached child that actually fronts the pane, all
// descendants of the pane's process.
//
// This used to drop the target from ALL of them rather than guess, which made
// the pane unsendable and 409'd every follow-up with no explanation. Guessing
// is in fact strictly better than refusing: the keys land in whatever the pane
// fronts either way, so the only thing at stake is which row we label sendable
// and which transcript deliver() confirms against — and a wrong guess merely
// leaves the send unconfirmed ("queued") instead of blocking it outright.
//
// The fronted conversation is the one being written to, so rank by transcript
// recency and keep the newest. Workers (no sessionId, no activity) can never
// win. Exported for tests.
export function resolvePaneOwners(sessions: Session[]): void {
  const byTarget = new Map<string, Session[]>();
  for (const s of sessions) {
    if (!s.tmuxTarget) continue;
    const g = byTarget.get(s.tmuxTarget);
    if (g) g.push(s);
    else byTarget.set(s.tmuxTarget, [s]);
  }
  for (const [target, group] of byTarget) {
    if (group.length <= 1) continue;
    // A real conversation has both an id and a transcript that has been written
    // to; the daemon's helper processes have neither.
    const live = group.filter((s) => s.sessionId && s.lastActivityAt != null);
    let winner: Session | undefined;
    if (live.length > 0) {
      winner = live.reduce((a, b) =>
        (b.lastActivityAt ?? 0) > (a.lastActivityAt ?? 0) ? b : a,
      );
    } else {
      // Nothing looks live — fall back to whoever holds the pane's terminal.
      const paneTty = paneTtyForTarget(target);
      winner = group.find((s) => paneTty != null && ttyOf(s.pid) === paneTty);
    }
    console.warn(
      `[sessions] ${group.length} sessions map to pane ${target} (pids ${group
        .map((g) => g.pid)
        .join(", ")}) — fronting ${winner ? `pid ${winner.pid}` : "none"}`,
    );
    for (const s of group) if (s !== winner) s.tmuxTarget = null;
  }
}

// `claude -p` / `--print` runs headless (no TUI). pgrep gives us the full
// argv, so match the flag as a whole token.
function isHeadless(cmd: string): boolean {
  return /(^|\s)(-p|--print)(\s|$)/.test(cmd);
}

// Parent pid (Linux: /proc/<pid>/stat field 4; macOS: ps -o ppid=). The
// platform branch lives in ./procinfo.
function ppidOf(pid: number): number | null {
  return procPpidOf(pid);
}

export async function resolveTranscript(sessionId: string): Promise<string | null> {
  if (!UUID.test(sessionId)) return null;
  const entry = findAisdkEntryByAnyId(sessionId);
  let id = entry?.agent === "codex" && entry.threadId ? entry.threadId : sessionId;
  if (entry?.agent === "codex" && !entry.threadId) {
    const inferred = inferCodexThreadForHarness(entry, await codexThreads(), new Set());
    if (inferred) {
      id = inferred.id;
      patchAisdkEntry(entry.sessionId, { threadId: inferred.id });
    }
  }
  return (await findTranscriptById(id)) ?? findCodexTranscriptById(id);
}

// The cwd a claude transcript was recorded in. Every claude JSONL line carries a
// top-level `cwd`, so the first parseable line tells us where to relaunch a
// resumed session. Read only the head — the cwd is stable for the whole file.
export async function cwdForTranscript(path: string): Promise<string | null> {
  try {
    const text = await Bun.file(path).slice(0, 64 * 1024).text();
    for (const line of text.split("\n")) {
      if (!line.trim()) continue;
      try {
        const x = JSON.parse(line) as {
          type?: string;
          cwd?: string;
          payload?: { cwd?: string };
        };
        if (typeof x.cwd === "string" && x.cwd) return x.cwd;
        if (x.type === "session_meta" && typeof x.payload?.cwd === "string" && x.payload.cwd)
          return x.payload.cwd;
      } catch {}
    }
  } catch {}
  return null;
}

export type ResumableSession = {
  agent: "claude" | "codex";
  sessionId: string;
  cwd: string | null;
  project: string;
  title: string;
  lastActivityAt: number | null;
  lastUserText: string | null;
  /**
   * Server-computed session state, alongside `busy` and `status`: this transcript
   * has no live process **on this host**. `listResumable` establishes it by
   * excluding the live-session ids, so it is a derivation, not a constant.
   *
   * Scope matters, and it is not the server's to widen: `~/.claude/projects` is
   * SYNCED between hosts and a server has no peer awareness (hosts are
   * client-side config), so host B enumerates host A's transcripts and would
   * call A's *running* session closed. Only a client, which polls every host,
   * can drop that phantom — see `MultiHost.reconcileResumable`. Read this field
   * as "closed here", and let the client's cross-host merge decide "closed".
   */
  closed: true;
};

export type ResumablePage = {
  sessions: ResumableSession[];
  nextBefore: number | null;
};

// Recently-active claude sessions that are NOT currently live — the closed /
// rebooted-away conversations a user can bring back with `claude --resume`.
// pgrep-based listSessions() only ever shows running procs, so after the box
// reboots (tmux server + every claude proc gone) the live list is empty even
// though all the transcripts survive on disk. This reads those transcripts so
// the UI can offer to resume one. Newest first, cursor-paged — enriching every
// historical transcript in a single response would be needlessly slow.
export type ResumableCandidate = {
  agent: "claude" | "codex";
  id: string;
  path: string;
  mtime: number;
  cwdHint?: string | null;
  firstUserText?: string | null;
};

/**
 * Make every session this host can currently see hold a current lease.
 *
 * This is the precondition behind the ONE definition of closed: nothing holds a
 * fresh lease. There is no second liveness input — no caller-supplied live-id
 * set, no local process check. Without refreshing leases here the invariant "a
 * live session is never returned as closed" would depend on a 30s background
 * loop having already run, and the failure direction is the bad one: hiding a
 * live agent and offering a resume that would double-spawn.
 *
 * Neither caller is hot (they back the resumable page and search, not the
 * session list), so an enumeration plus N stat-sized lease ops is the right
 * price for removing a whole class of disagreement.
 */
export function mayRefreshLiveLease(
  sessionId: string | null,
  pid: number,
  closing: (pid: number) => boolean = isClosing,
): boolean {
  return !!sessionId && !closing(pid);
}

async function refreshLeasesForLiveSessions(): Promise<void> {
  try {
    for (const s of await listSessions()) {
      // listSessions is briefly cached. A close can tombstone the pid after the
      // cached row was produced but before resumable search refreshes leases.
      // Re-check at the side effect boundary or that stale row recreates the
      // lease releaseLease just removed, hiding the newly closed session for the
      // full 90-second freshness window.
      if (mayRefreshLiveLease(s.sessionId, s.pid)) await ensureLease(s.sessionId!, s.pid);
    }
  } catch {
    // Enumeration failed: fall through and read whatever leases exist. A stale
    // lease is still fresh for up to LEASE_FRESH_MS, so a transient failure
    // cannot flip a running session to closed.
  }
}

/**
 * Every transcript on this host as an unenriched candidate, newest first.
 *
 * Cheap by construction — a readdir plus one stat per file — so callers only pay
 * the title/cwd read cost for the rows they actually return. A synced transcript
 * can exist under more than one encoded project directory; sessionId is
 * authoritative and the newest copy wins, so pagination never returns the same
 * conversation twice.
 */
export async function collectResumableCandidates(): Promise<ResumableCandidate[]> {
  let dirs: string[] = [];
  const projectsDir = claudeProjectsDir();
  try {
    dirs = await readdir(projectsDir);
  } catch {}
  const byId = new Map<string, ResumableCandidate>();
  for (const d of dirs) {
    let files: string[];
    try {
      files = await readdir(join(projectsDir, d));
    } catch {
      continue;
    }
    for (const f of files) {
      if (!f.endsWith(".jsonl")) continue;
      const id = f.replace(/\.jsonl$/, "");
      // Whole-name UUID match, not UUID.test: a Syncthing conflict copy
      // ("<uuid>.sync-conflict-<stamp>.jsonl") contains a UUID substring but is
      // a duplicate of the real transcript and can't be `--resume`d by its name.
      if (!UUID_EXACT.test(id)) continue;
      const path = join(projectsDir, d, f);
      let mtime = 0;
      try {
        mtime = statSync(path).mtimeMs;
      } catch {
        continue;
      }
      const prev = byId.get(id);
      if (!prev || mtime > prev.mtime) byId.set(id, { agent: "claude", id, path, mtime });
    }
  }
  for (const thread of await codexThreads()) {
    if (!UUID_EXACT.test(thread.id)) continue;
    const mtime = thread.updatedAt ?? thread.createdAt ?? 0;
    const prev = byId.get(thread.id);
    if (!prev || mtime > prev.mtime) {
      byId.set(thread.id, {
        agent: "codex",
        id: thread.id,
        path: thread.path,
        mtime,
        cwdHint: thread.cwd,
        firstUserText: thread.firstUserText,
      });
    }
  }
  const candidates = [...byId.values()];
  candidates.sort((a, b) => b.mtime - a.mtime);
  return candidates;
}

/** Read a candidate's searchable/displayable metadata off its transcript. */
async function enrichCandidate(
  c: ResumableCandidate,
  overrides: Record<string, string>,
): Promise<ResumableSession> {
  const cwd = c.cwdHint ?? (await cwdForTranscript(c.path).catch(() => null));
  let title = overrides[c.id] || null;
  if (!title) title = await firstPromptTitle(c.path).catch(() => null);
  if (!title) title = c.firstUserText?.slice(0, TITLE_MAX) ?? null;
  if (!title) title = cwd ? basename(cwd) : "—";
  return {
    agent: c.agent,
    sessionId: c.id,
    cwd,
    project: projectName(cwd),
    title,
    lastActivityAt: c.mtime,
    lastUserText: await lastUserText(c.path).catch(() => null),
    // Earned, not assumed: nothing holds a fresh lease on this session.
    closed: true,
  };
}

export async function listResumable(
  opts: { limit?: number; before?: number | null } = {},
): Promise<ResumablePage> {
  const limit = Math.max(1, Math.min(100, opts.limit ?? 30));
  await refreshLeasesForLiveSessions();
  const before = typeof opts.before === "number" && Number.isFinite(opts.before) ? opts.before : null;
  const candidates = (await collectResumableCandidates()).filter(
    (c) => before == null || c.mtime < before,
  );
  const page: ResumableCandidate[] = [];
  let nextBefore: number | null = null;
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    // THE definition of closed: nothing holds a fresh lease on this session.
    // Was `foreignFreshAt` — a peer-only question that relied on `exclude` to
    // cover local liveness. `ensureLease` now writes a lease for every session
    // this host enumerates, so local and remote are the same fact and get the
    // same question.
    if (await anyFreshAt(c.id, c.path)) continue;
    page.push(c);
    if (page.length >= limit) {
      nextBefore = candidates.length > i + 1 ? c.mtime : null;
      break;
    }
  }
  const overrides = await readTitleOverrides();
  const out: ResumableSession[] = [];
  for (const c of page) out.push(await enrichCandidate(c, overrides));
  return { sessions: out, nextBefore };
}

// ---------------------------------------------------------------------------
// Search across EVERY session, not just the page the client has loaded.
// ---------------------------------------------------------------------------
//
// `listResumable` enriches only the newest `limit` transcripts, which is why the
// client's search could only ever see what it had already paged in. Search needs
// the searchable fields for the whole corpus, so it keeps a metadata index
// (`src/session-index.ts`) and refreshes it incrementally: a stat pass over
// every transcript, then a read of only the ones whose (path, mtime) changed.
//
// Measured on the real corpus (5,318 transcripts, 1.4 GB): enumerate 10 ms, full
// cold build 431 ms at concurrency 24, steady-state refresh a stat pass plus a
// handful of reads. That is cheap enough to run inline on a search request —
// which is deliberate. A background `setInterval` over a growing collection is
// exactly the fan-out this repo bans on the single Bun event loop.

// Exported for tests: `PATHS.data` is resolved when `config.ts` is first
// imported, so a test that recomputes this path from its own env can disagree
// with the module under test depending on file load order.
export const SEARCH_INDEX_PATH = join(PATHS.data, "session-search-index.json");
/** How many transcripts to enrich at once. Bounded so a cold build yields. */
const SEARCH_ENRICH_CONCURRENCY = 24;

/**
 * How long a just-refreshed index is served without re-checking the disk.
 *
 * Search is typed, so one query is a BURST of requests, and the enumeration is
 * not free even when nothing changed: `codexThreads()` reads the head of every
 * rollout file, measured at ~170 ms on the real corpus. Paying that per
 * keystroke would stall the single Bun event loop that serves all HTTP. Results
 * being up to this stale is invisible — a session that ended two seconds ago is
 * still in the live list.
 *
 * Zero under `bun test` so fixtures written mid-test are seen immediately.
 */
let searchIndexTtlMs = process.env.NODE_ENV === "test" ? 0 : 3_000;

let searchIndexCache: IndexEntry[] | null = null;
let searchIndexFreshUntil = 0;
let searchRefreshInFlight: Promise<IndexEntry[]> | null = null;

async function loadSearchIndex(): Promise<IndexEntry[]> {
  if (searchIndexCache) return searchIndexCache;
  try {
    const f = Bun.file(SEARCH_INDEX_PATH);
    searchIndexCache = (await f.exists()) ? parseIndexFile(await f.json()) : [];
  } catch {
    // A truncated or half-written index costs one rebuild, never a failed search.
    searchIndexCache = [];
  }
  return searchIndexCache;
}

async function persistSearchIndex(entries: IndexEntry[]): Promise<void> {
  try {
    await Bun.write(SEARCH_INDEX_PATH, JSON.stringify(serializeIndex(entries)));
  } catch {
    // Persisting is an optimization; an unwritable data dir must not fail a search.
  }
}

/**
 * Bring the index up to date with the transcripts on disk and return it.
 *
 * Coalesced: concurrent searches (a client types four characters) share one
 * refresh rather than each walking the corpus.
 */
async function refreshSearchIndex(): Promise<IndexEntry[]> {
  if (searchIndexCache && Date.now() < searchIndexFreshUntil) return searchIndexCache;
  if (searchRefreshInFlight) return searchRefreshInFlight;
  const run = (async () => {
    const prev = await loadSearchIndex();
    const candidates = await collectResumableCandidates();
    const plan = planRefresh(
      prev,
      candidates.map((c) => ({ agent: c.agent, sessionId: c.id, path: c.path, mtime: c.mtime })),
    );
    if (plan.stale.length === 0 && plan.dropped === 0) {
      searchIndexFreshUntil = Date.now() + searchIndexTtlMs;
      return prev;
    }

    const byId = new Map(candidates.map((c) => [c.id, c]));
    const enriched: IndexEntry[] = [];
    // No title overrides here: they live in their own file and change without
    // touching the transcript, so baking one in would freeze a renamed session's
    // old title into the index. They are overlaid at query time instead.
    const noOverrides: Record<string, string> = {};
    let next = 0;
    await Promise.all(
      Array.from({ length: Math.min(SEARCH_ENRICH_CONCURRENCY, plan.stale.length) }, async () => {
        while (next < plan.stale.length) {
          const item = plan.stale[next++];
          const candidate = byId.get(item.sessionId);
          if (!candidate) continue;
          try {
            const s = await enrichCandidate(candidate, noOverrides);
            enriched.push({
              agent: item.agent,
              sessionId: item.sessionId,
              path: item.path,
              mtime: item.mtime,
              cwd: s.cwd,
              project: s.project,
              title: s.title,
              lastUserText: s.lastUserText,
            });
          } catch {
            // A transcript that vanished mid-refresh (Syncthing churn) simply
            // doesn't enter the index; the next refresh picks it up if it returns.
          }
        }
      }),
    );

    const merged = [...plan.reuse, ...enriched];
    searchIndexCache = merged;
    searchIndexFreshUntil = Date.now() + searchIndexTtlMs;
    await persistSearchIndex(merged);
    return merged;
  })();
  searchRefreshInFlight = run;
  try {
    return await run;
  } finally {
    if (searchRefreshInFlight === run) searchRefreshInFlight = null;
  }
}

/**
 * Closed sessions matching `q`, drawn from the entire corpus, newest first and
 * cursor-paged exactly like `listResumable` — same page shape, same `before` /
 * `nextBefore` contract, same "closed = nothing holds a fresh lease" rule. The
 * client can therefore feed the result through the same cross-host reconcile.
 */
export async function searchResumable(
  opts: { q: string; limit?: number; before?: number | null },
): Promise<ResumablePage> {
  const limit = Math.max(1, Math.min(100, opts.limit ?? 30));
  const before =
    typeof opts.before === "number" && Number.isFinite(opts.before) ? opts.before : null;
  const terms = queryTerms(opts.q ?? "");
  if (terms.length === 0) return listResumable({ limit, before });

  await refreshLeasesForLiveSessions();
  const overrides = await readTitleOverrides();
  const index = applyTitleOverrides(await refreshSearchIndex(), overrides);
  const matches = matchingEntries(index, terms, before);

  const page: IndexEntry[] = [];
  let nextBefore: number | null = null;
  for (let i = 0; i < matches.length; i++) {
    const m = matches[i];
    if (await anyFreshAt(m.sessionId, m.path)) continue;
    page.push(m);
    if (page.length >= limit) {
      nextBefore = matches.length > i + 1 ? m.mtime : null;
      break;
    }
  }

  return {
    sessions: page.map((m) => ({
      agent: m.agent,
      sessionId: m.sessionId,
      cwd: m.cwd,
      project: m.project,
      title: m.title,
      lastActivityAt: m.mtime,
      lastUserText: m.lastUserText,
      closed: true,
    })),
    nextBefore,
  };
}

/** Test seam: drop the in-process index so the next search rereads from disk. */
export function resetSearchIndexCacheForTests(): void {
  searchIndexCache = null;
  searchIndexFreshUntil = 0;
  searchRefreshInFlight = null;
}

/** Test seam: exercise the burst-coalescing window, which is 0 under `bun test`. */
export function setSearchIndexTtlForTests(ms: number): void {
  searchIndexTtlMs = ms;
  searchIndexFreshUntil = 0;
}

/**
 * Normalize a whole JSONL transcript without ever holding it in memory at once.
 *
 * The bounded tail path can afford `slice().text()`; an unbounded read cannot.
 * One string of a 511 MB Codex rollout, plus the line array `split` makes from
 * it, peaked at ~2 GB of RSS for a page of 220 messages — two concurrent calls
 * put the host over its 4 GB ceiling, and every ceiling kill drops all
 * `/api/events` streams. Streaming keeps peak at O(chunk + kept messages);
 * the messages themselves are what the caller asked for.
 */
async function streamNormalizedMessages(
  file: ReturnType<typeof Bun.file>,
  codexState: CodexNormalizationState,
): Promise<SessionMsg[]> {
  const msgs: SessionMsg[] = [];
  const decoder = new TextDecoder();
  // Carry BYTES, not a string. Appending each chunk to a `carry` string and
  // scanning it re-flattens a growing rope on every chunk: measured on the
  // 511 MB rollout that was slower AND hungrier than reading the whole file.
  // Rows here average ~137 KB, so a line routinely spans several chunks.
  let pending: Uint8Array[] = [];
  let pendingLen = 0;

  const take = (line: string) => {
    if (line) msgs.push(...normalizeLineMessages(line, codexState));
  };

  // Join the carried head of a record to its tail and decode the whole row at
  // once. A UTF-8 scalar can never straddle the `\n` these are split on, so
  // every other subarray is safe to decode on its own, uncopied.
  const joinPending = (tail: Uint8Array): string => {
    const buf = new Uint8Array(pendingLen + tail.length);
    let at = 0;
    for (const part of pending) {
      buf.set(part, at);
      at += part.length;
    }
    buf.set(tail, at);
    pending = [];
    pendingLen = 0;
    return decoder.decode(buf);
  };

  for await (const chunk of file.stream()) {
    let from = 0;
    let nl = chunk.indexOf(0x0a, from);
    while (nl >= 0) {
      const body = chunk.subarray(from, nl);
      take(pendingLen > 0 ? joinPending(body) : decoder.decode(body));
      from = nl + 1;
      nl = chunk.indexOf(0x0a, from);
    }
    if (from < chunk.length) {
      // Copy before retaining: a stream may hand back a reused buffer.
      const rest = chunk.subarray(from);
      const kept = new Uint8Array(rest.length);
      kept.set(rest);
      pending.push(kept);
      pendingLen += kept.length;
    }
  }
  // A transcript whose final row has no trailing newline still has that row.
  if (pendingLen > 0) take(joinPending(new Uint8Array(0)));
  return msgs;
}

// Recent normalized messages for an initial render (tail of the file).
export async function recentMessages(
  path: string,
  limit = 40,
  opts: { maxBytes?: number | null } = {},
): Promise<SessionMsg[]> {
  const file = Bun.file(path);
  const size = file.size;
  const maxBytes = opts.maxBytes === undefined ? 256 * 1024 : opts.maxBytes;
  if (maxBytes == null) {
    const msgs = await streamNormalizedMessages(file, createCodexNormalizationState());
    const collapsed = collapseCodexLifecycleMessages(msgs);
    return limit > 0 ? collapsed.slice(-limit) : collapsed;
  }
  const start = Math.max(0, size - maxBytes);
  const text = await file.slice(start).text();
  const lines = text.split("\n").filter(Boolean);
  const msgs: SessionMsg[] = [];
  const codexState = createCodexNormalizationState();
  // A tail window normally excludes the rollout's opening session_meta row.
  // Seed it from the header so CLI-relative paths stay relative even when the
  // patch itself is served from deep in a long transcript.
  if (start > 0) {
    const header = await file.slice(0, Math.min(size, 64 * 1024)).text();
    const firstLine = header.split("\n", 1)[0];
    if (firstLine) normalizeLineMessages(firstLine, codexState);
  }
  for (const l of lines) {
    msgs.push(...normalizeLineMessages(l, codexState));
  }
  const collapsed = collapseCodexLifecycleMessages(msgs);
  return limit > 0 ? collapsed.slice(-limit) : collapsed;
}

// Messages from the first `maxBytes` bytes of a transcript. Used for forked
// sessions before Claude materializes the fork's own file: if the byte cap cuts
// through a JSONL row, drop that trailing partial row rather than trying to parse
// a corrupt message or leaking source turns written after the fork point.
export async function snapshotMessages(
  path: string,
  limit = 40,
  opts: { maxBytes: number | null },
): Promise<SessionMsg[]> {
  const file = Bun.file(path);
  const size = file.size;
  const cap = opts.maxBytes == null ? size : Math.max(0, Math.min(size, Math.floor(opts.maxBytes)));
  let text = await file.slice(0, cap).text();
  if (cap < size && text && !text.endsWith("\n")) {
    const lastNewline = text.lastIndexOf("\n");
    text = lastNewline >= 0 ? text.slice(0, lastNewline + 1) : "";
  }
  const msgs: SessionMsg[] = [];
  const codexState = createCodexNormalizationState();
  for (const l of text.split("\n").filter(Boolean)) {
    msgs.push(...normalizeLineMessages(l, codexState));
  }
  const collapsed = collapseCodexLifecycleMessages(msgs);
  return limit > 0 ? collapsed.slice(-limit) : collapsed;
}

// A prompt read straight from the transcript's structured AskUserQuestion
// tool_use block. Shape-compatible with tmux.ts's PanePrompt (question +
// numbered options) so the SSE prompt event and the client render it
// identically — the extra fields are additive and safely ignored by older
// clients.
export type PendingPrompt = {
  // Always "transcript" here — lets a consumer tell a structured prompt apart
  // from a pane-scraped one for debugging/telemetry.
  source: "transcript";
  question: string;
  header?: string;
  multiSelect?: boolean;
  options: Array<{
    index: number; // 1-based — matches the digit you'd press in the TUI
    label: string;
    selected: boolean;
    description?: string;
  }>;
};

// Detect an AskUserQuestion that is still waiting for the user, read from the
// transcript's structured tool_use block rather than scraped from the tmux
// pane. This is dramatically more reliable: AskUserQuestion with option
// previews renders a side-by-side box layout (and multi-select / wrapped
// descriptions) that the pane parser mangles — or misses entirely, because in
// the preview layout no option line carries the `❯` cursor the scraper keys
// off, so no prompt surfaces at all. The transcript carries the exact question
// text and option labels with no ANSI or box-art.
//
// Scoped to AskUserQuestion on purpose: ExitPlanMode and permission/trust
// dialogs scrape cleanly (simple contiguous selectors with a live cursor) and
// their option set is TUI-generated — not in the transcript — so the pane stays
// the right source for those.
export async function pendingToolPrompt(
  path: string,
): Promise<PendingPrompt | null> {
  // Tail only, and deliberately NOT scanBack: this walks *forward* pairing
  // tool_use ids with their tool_results, so it needs a contiguous window in
  // order rather than a newest-first scan. 128KB comfortably spans the last
  // tool_use plus any tool_results after it, and a pending prompt is always
  // near the end.
  const { lines: promptLines } = await tail(path, 128 * 1024);
  // Walk forward tracking open AskUserQuestion tool_use ids; an id clears when
  // its tool_result lands. Whatever is still open at the end is unanswered.
  const open = new Map<string, unknown>();
  for (const l of promptLines) {
    let x: { message?: { content?: unknown } };
    try {
      x = JSON.parse(l);
    } catch {
      continue;
    }
    const content = x?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const c of content as Array<Record<string, unknown>>) {
      if (c?.type === "tool_use" && c?.name === "AskUserQuestion") {
        if (typeof c.id === "string") open.set(c.id, c.input);
      } else if (c?.type === "tool_result" && typeof c?.tool_use_id === "string") {
        open.delete(c.tool_use_id);
      }
    }
  }
  if (!open.size) return null;
  // The most-recently-opened still-pending question is the live one.
  const input = [...open.values()].pop() as
    | { questions?: Array<Record<string, unknown>> }
    | undefined;
  // AskUserQuestion can bundle several questions, surfaced one at a time; the
  // first is the one on screen for an unanswered call.
  const q = input?.questions?.[0];
  const options = Array.isArray(q?.options) ? q.options : null;
  if (!q || !options || !options.length) return null;
  return {
    source: "transcript",
    question: typeof q.question === "string" ? q.question : "",
    header: typeof q.header === "string" ? q.header : undefined,
    multiSelect: !!q.multiSelect,
    options: (options as Array<Record<string, unknown>>).map((o, i) => ({
      index: i + 1,
      label: typeof o?.label === "string" ? o.label : String(o ?? ""),
      selected: false,
      description: typeof o?.description === "string" ? o.description : undefined,
    })),
  };
}

export async function messagePage(
  path: string,
  opts: { before?: number | null; limit?: number } = {},
): Promise<{
  messages: SessionMsg[];
  nextBefore: number | null;
  total: number;
}> {
  const all = await recentMessages(path, 0, { maxBytes: null });
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
