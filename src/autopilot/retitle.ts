// The retitle task: keep a session's title describing what it is ACTUALLY
// working on, not whatever was typed first.
//
// The problem it solves is specific to long sessions. Claude's `/resume` picker
// titles a conversation by its first real user prompt, and lfg mirrors that. But
// a session that ran for six hours has usually changed subject several times, so
// the title ends up naming a thing that finished before lunch — which makes both
// the session list and search actively misleading.
//
// Three constraints shape the whole design:
//
//   1. NEVER overwrite a human-set title. Provenance is recorded at rename time
//      (`titles.ts`), so this is a lookup, not a heuristic.
//   2. ONE LLM call per run, covering every candidate. This repo bans
//      `setInterval` fan-out over a growing collection on the single Bun event
//      loop; a per-session call would be exactly that, and the collection here
//      grows with every session Eugene starts.
//   3. ONE host per session. `~/.claude/projects` is synced between the Pro and
//      the Air, but `~/.lfg` is per-machine — so without a host filter both
//      boxes would independently retitle the same transcript and disagree. The
//      lease file (synced, next to the transcript, carrying `hostId`) is the
//      ownership signal that already exists for exactly this class of question.

import { basename, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { PATHS } from "../config.ts";
import { hostInfo } from "../hostinfo.ts";
import { ensureLease, leasePathForTranscript, parseLease } from "../leases.ts";
import {
  collectResumableCandidates,
  listSessions,
  allUserTurns,
  readTitleRecords,
  setSessionTitle,
  type ResumableCandidate,
} from "../sessions.ts";
import { autopilotMayRename, type TitleFile } from "./titles.ts";
import { askJson, extractJson } from "./claude.ts";
import {
  parseCheckpoints,
  pruneCheckpoints,
  type CheckpointFile,
} from "./checkpoints.ts";
import type { AutopilotStep, TaskContext, TaskResult } from "./registry.ts";

export const CHECKPOINTS_PATH = join(PATHS.data, "autopilot-retitle.json");

/** How far back a transcript counts as "recently active". */
export const RECENT_WINDOW_MS = Number(
  process.env.LFG_RETITLE_WINDOW_MS ?? 7 * 24 * 60 * 60 * 1000,
);
/** Hard cap on sessions per run — bounds the single LLM call's prompt size. */
export const MAX_PER_RUN = Number(process.env.LFG_RETITLE_MAX ?? 12);
/** A session needs this many user turns before "drift" is even a coherent idea. */
export const MIN_USER_TURNS = 3;
/** Growth since the last look, below which there's nothing new to read. */
export const MIN_NEW_BYTES = 2 * 1024;


/** What candidate selection needs to know about one session. */
export type RetitleCandidate = {
  sessionId: string;
  path: string;
  mtime: number;
  bytes: number;
  cwd: string | null;
  /** The title showing today. */
  title: string;
  /** true when a process is running it on this host right now. */
  live: boolean;
  /** hostId from the lease, or null when the session has no lease record. */
  leaseHost: string | null;
};

/**
 * Which sessions this run should examine.
 *
 * Ordered by "least recently examined first" so a corpus larger than
 * `MAX_PER_RUN` round-robins across runs instead of the same head of the list
 * winning every time. Live sessions sort first regardless — they're the ones
 * Eugene is looking at.
 */
export function selectRetitleCandidates(
  candidates: RetitleCandidate[],
  titles: TitleFile,
  checkpoints: CheckpointFile,
  now: number,
  opts: { hostId: string; max?: number; windowMs?: number } = { hostId: "" },
): RetitleCandidate[] {
  const max = opts.max ?? MAX_PER_RUN;
  const windowMs = opts.windowMs ?? RECENT_WINDOW_MS;

  const eligible = candidates.filter((c) => {
    // A human named it. That decision outranks anything the model would say.
    if (!autopilotMayRename(titles[c.sessionId])) return false;

    // The lease decides ownership for EVERY session, live ones included.
    //
    // An earlier version exempted live sessions, reasoning they were "on this
    // host by construction". They are not: `~/.claude` is synced, so one
    // sessionId can read as live on both boxes at once — observed on
    // 01e32dd7, which the Pro and the Air each retitled, to different names.
    // `ensureLease` is the existing mutual-exclusion primitive (it refuses when
    // another host holds a fresh lease), so asking it is both correct and the
    // answer the rest of lfg already uses.
    //
    // No lease at all means no host has claimed it — skipped rather than
    // guessed, because "unclaimed here" is equally unclaimed on the peer and
    // both boxes would otherwise take it.
    if (c.leaseHost !== opts.hostId) return false;
    if (!c.live && now - c.mtime > windowMs) return false;

    // Nothing new written since the last look — re-reading it would cost an LLM
    // slot to reach the same conclusion.
    const cp = checkpoints[c.sessionId];
    if (cp && c.bytes - cp.bytes < MIN_NEW_BYTES) return false;
    return true;
  });

  eligible.sort((a, b) => {
    if (a.live !== b.live) return a.live ? -1 : 1;
    const aC = checkpoints[a.sessionId]?.at ?? 0;
    const bC = checkpoints[b.sessionId]?.at ?? 0;
    if (aC !== bC) return aC - bC; // never-checked (0) first
    return b.mtime - a.mtime;
  });

  return eligible.slice(0, max);
}

/** One session as the model sees it. */
export type RetitleDigest = {
  sessionId: string;
  title: string;
  project: string;
  turns: string[];
};

export function buildRetitlePrompt(digests: RetitleDigest[]): string {
  const blocks = digests.map((d, i) => {
    const turns = d.turns.map((t) => `  - ${t}`).join("\n");
    return [
      `### Session ${i + 1}`,
      `id: ${d.sessionId}`,
      `current_title: ${d.title}`,
      `project: ${d.project}`,
      `all_user_messages (oldest → newest):`,
      turns || "  (none)",
    ].join("\n");
  });

  return `You are maintaining the session list of a coding-agent dashboard.

Each session below shows its CURRENT title (usually taken from the first thing
the user typed) and ALL genuine user messages in chronological order. Judge the
conversation as a whole. Do not infer the session topic from the newest message
alone.

For each session, first decide whether the messages show a sustained semantic
shift to a different workstream. A follow-up, clarification, implementation
step, bug found while doing the work, verification request, or change in tactics
within the same goal is NOT topic drift.

- If there is no sustained semantic shift and the current title still names the
  established workstream, return null. Prefer null — a merely imperfect title is
  not worth churning.
- Rename only when the full message sequence makes the current title materially
  misleading. The new title must summarize the established workstream across the
  conversation; never restate just the latest request.
- A new title is 2-6 words, specific, with no trailing punctuation, quotes,
  "Session" prefix, or filler such as "working on" or "discussion about". Match
  the tone of a git branch name written as prose, e.g. "Autopilot retitle task",
  "iOS push token expiry", "Tailwind migration for settings".
- Ignore one-word replies ("yes", "go on") when judging the subject.
- If the messages are too thin or mixed to identify a stable workstream, return
  null.

Reply with ONLY a JSON array, one entry per session, no prose and no markdown
fence:

[{"id": "<session id>", "title": "<new title>" | null}]

${blocks.join("\n\n")}`;
}

export type RetitleProposal = { id: string; title: string | null };

/**
 * Validate the model's batch reply into proposals.
 *
 * Extraction (bare / fenced / embedded JSON) is the shared service's job;
 * this is the part only the retitle task can do — an entry whose id wasn't
 * asked about, or whose title isn't a usable string, is dropped rather than
 * applied to some other session.
 */
export function validateRetitleBatch(parsed: unknown, askedIds: string[]): RetitleProposal[] {
  const asked = new Set(askedIds);
  if (!Array.isArray(parsed)) return [];

  const out: RetitleProposal[] = [];
  const seen = new Set<string>();
  for (const row of parsed) {
    if (!row || typeof row !== "object") continue;
    const r = row as { id?: unknown; title?: unknown };
    const id = typeof r.id === "string" ? r.id.trim() : "";
    if (!id || !asked.has(id) || seen.has(id)) continue;
    seen.add(id);
    if (r.title === null || r.title === undefined) {
      out.push({ id, title: null });
      continue;
    }
    if (typeof r.title !== "string") continue;
    const title = cleanTitle(r.title);
    out.push({ id, title: title || null });
  }
  return out;
}

/** Text in, proposals out. Kept for tests that exercise the whole reply path. */
export function parseRetitleBatch(text: string, askedIds: string[]): RetitleProposal[] {
  return validateRetitleBatch(extractJson(text), askedIds);
}

/** Strip the wrappers models add back despite being told not to. */
export function cleanTitle(raw: string): string {
  let t = raw.trim().replace(/\s+/g, " ");
  t = t.replace(/^["'`]+|["'`]+$/g, "");
  t = t.replace(/^(?:session|title)\s*:\s*/i, "");
  t = t.replace(/[.,;:]+$/, "");
  return t.trim().slice(0, 80);
}

/** Would applying this proposal actually change anything? */
export function isRealChange(proposal: RetitleProposal, currentTitle: string): boolean {
  if (!proposal.title) return false;
  const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();
  return norm(proposal.title) !== norm(currentTitle);
}

// ---------------------------------------------------------------------------
// The impure half: gather candidates, call the model, apply.
// ---------------------------------------------------------------------------

async function leaseHostFor(sessionId: string, path: string): Promise<string | null> {
  try {
    const p = leasePathForTranscript(sessionId, path);
    const f = Bun.file(p);
    if (!(await f.exists())) return null;
    return parseLease(await f.text())?.hostId ?? null;
  } catch {
    return null;
  }
}

/** Everything on this host worth considering, before selection filters it. */
export async function gatherCandidates(now: number): Promise<RetitleCandidate[]> {
  const [live, resumable] = await Promise.all([
    listSessions().catch(() => []),
    collectResumableCandidates().catch(() => [] as ResumableCandidate[]),
  ]);

  const liveIds = new Set<string>();
  const byId = new Map<string, RetitleCandidate>();

  for (const s of live) {
    if (!s.sessionId || !s.transcriptPath) continue;
    liveIds.add(s.sessionId);
    byId.set(s.sessionId, {
      sessionId: s.sessionId,
      path: s.transcriptPath,
      mtime: s.lastActivityAt ?? now,
      bytes: 0,
      cwd: s.cwd,
      title: s.title,
      live: true,
      // Resolved below by claiming the lease — NOT assumed to be this host.
      leaseHost: null,
    });
  }

  // Only stat/lease-read the transcripts that could still qualify. The corpus is
  // ~9k files; reading a lease for each would be 9k reads to discard almost all
  // of them, so the cheap mtime test comes first.
  for (const c of resumable) {
    if (byId.has(c.id)) continue;
    if (now - c.mtime > RECENT_WINDOW_MS) continue;
    byId.set(c.id, {
      sessionId: c.id,
      path: c.path,
      mtime: c.mtime,
      bytes: 0,
      cwd: c.cwdHint ?? null,
      title: "",
      live: false,
      leaseHost: null,
    });
  }

  const livePid = new Map(live.filter((s) => s.sessionId).map((s) => [s.sessionId!, s.pid]));
  const me = hostInfo().hostId;

  const out = [...byId.values()];
  await Promise.all(
    out.map(async (c) => {
      try {
        c.bytes = Bun.file(c.path).size;
      } catch {}
      if (c.live) {
        // CLAIM it, don't assume it. `ensureLease` returns false when another
        // host already holds a fresh lease — which is exactly the case that made
        // both boxes retitle one session, since a synced `~/.claude` lets one
        // sessionId read as live on both at once.
        const held = await ensureLease(c.sessionId, livePid.get(c.sessionId) ?? 0).catch(
          () => false,
        );
        c.leaseHost = held ? me : await leaseHostFor(c.sessionId, c.path);
      } else {
        c.leaseHost = await leaseHostFor(c.sessionId, c.path);
      }
    }),
  );
  return out;
}

/** The system prompt. Sent via `--system-prompt`, so it REPLACES the default. */
const SYSTEM = `You rename sessions in a coding-agent dashboard. You are given
session digests and you reply with only a JSON array. Never use tools, never ask
questions, never explain yourself.`;

export async function readCheckpoints(): Promise<CheckpointFile> {
  try {
    const f = Bun.file(CHECKPOINTS_PATH);
    if (!(await f.exists())) return {};
    return parseCheckpoints(await f.json());
  } catch {
    return {};
  }
}

async function writeCheckpoints(file: CheckpointFile): Promise<void> {
  await mkdir(PATHS.data, { recursive: true });
  await Bun.write(CHECKPOINTS_PATH, JSON.stringify(file, null, 2));
}

export async function runRetitle(ctx: TaskContext): Promise<TaskResult> {
  const { now, log, dryRun } = ctx;
  const [titles, checkpoints] = await Promise.all([readTitleRecords(), readCheckpoints()]);
  const all = await gatherCandidates(now);
  const picked = selectRetitleCandidates(all, titles, checkpoints, now, {
    hostId: hostInfo().hostId,
  });

  log(`[retitle] ${all.length} in window → ${picked.length} to examine`);
  if (!picked.length) return { examined: 0, changed: 0, note: "no candidates" };

  // Build complete conversation digests; drop anything too thin to judge.
  const digests: RetitleDigest[] = [];
  const byId = new Map<string, RetitleCandidate>();
  const histories = new Map<string, { messages: string[]; nextByte: number }>();
  for (const c of picked) {
    const checkpoint = checkpoints[c.sessionId];
    const canContinue =
      checkpoint?.userMessages !== undefined && checkpoint.bytes <= c.bytes;
    const previous = canContinue ? checkpoint.userMessages! : [];
    const scanned = await allUserTurns(c.path, {
      startByte: canContinue ? checkpoint.bytes : 0,
    }).catch(() => null);
    if (!scanned) continue;
    const turns = [...previous, ...scanned.turns];
    histories.set(c.sessionId, { messages: turns, nextByte: scanned.nextByte });
    if (turns.length < MIN_USER_TURNS) continue;
    const title = c.title || titles[c.sessionId]?.title || "(untitled)";
    digests.push({
      sessionId: c.sessionId,
      title,
      project: c.cwd ? basename(c.cwd) : "—",
      turns,
    });
    byId.set(c.sessionId, { ...c, title });
  }

  // Every session that reached this point HAS been examined, whether or not it
  // made it into the prompt — so all of them get a checkpoint. Without this the
  // thin ones (too few user turns to judge) would be re-picked every run and
  // starve the sessions that could actually be retitled.
  const stamp = async () => {
    if (dryRun) return;
    const next = { ...checkpoints };
    for (const c of picked) {
      const history = histories.get(c.sessionId);
      // A failed read is left unstamped so it can retry. Successful reads cache
      // the complete truncated message sequence and checkpoint only through the
      // last complete JSON row.
      if (history) {
        next[c.sessionId] = {
          bytes: history.nextByte,
          at: now,
          userMessages: history.messages,
        };
      }
    }
    await writeCheckpoints(
      pruneCheckpoints(next, new Set(all.map((c) => c.sessionId))),
    ).catch(() => {});
  };

  if (!digests.length) {
    await stamp();
    return { examined: picked.length, changed: 0, note: "all candidates too thin to judge" };
  }

  const askedIds = digests.map((d) => d.sessionId);
  log(`[retitle] asking about ${digests.length} sessions`);
  const proposals =
    (await askJson<RetitleProposal[]>({
      prompt: buildRetitlePrompt(digests),
      system: SYSTEM,
      label: "retitle",
      log,
      // An empty array is a legitimate answer ("nothing drifted"), so only a
      // non-array is a validation failure.
      validate: (v) => (Array.isArray(v) ? validateRetitleBatch(v, askedIds) : null),
    })) ?? [];
  log(`[retitle] ${proposals.length} parsed proposals`);

  const changes: { id: string; from: string; to: string }[] = [];
  for (const p of proposals) {
    const c = byId.get(p.id);
    if (!c || !isRealChange(p, c.title)) continue;
    changes.push({ id: p.id, from: c.title, to: p.title! });
  }

  if (dryRun) {
    for (const c of changes) log(`[retitle] would rename ${c.id.slice(0, 8)}: "${c.from}" → "${c.to}"`);
    return {
      examined: digests.length,
      changed: 0,
      note: `${changes.length} would change (dry run)`,
      detail: changes,
    };
  }

  for (const c of changes) {
    await setSessionTitle(c.id, c.to, {
      source: "auto",
      basis: `drifted from "${c.from}"`,
    });
    log(`[retitle] renamed ${c.id.slice(0, 8)}: "${c.from}" → "${c.to}"`);
  }
  // Checkpoints cover every session examined, renamed or not — `stamp` reads
  // `picked`, so this single call handles both outcomes.
  await stamp();

  return {
    examined: digests.length,
    changed: changes.length,
    note: changes.length ? changes.map((c) => c.to).join("; ") : "no drift found",
    detail: changes,
  };
}

export const retitleStep: AutopilotStep = {
  name: "retitle-sessions",
  description: "Rename sessions whose title no longer describes the current work",
  run: runRetitle,
};
