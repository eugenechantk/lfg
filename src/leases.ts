import { mkdir, readFile, rename, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { basename, dirname, join } from "node:path";
import { hostInfo } from "./hostinfo.ts";

export const LEASE_FRESH_MS = 90_000;

/**
 * One session's record, written by TWO independent parties. Fields are owned:
 *
 *   lfg  (this module) — hostId, pid, acquiredAt, heartbeatAt   → liveness
 *   hook (lfg-agent-hook.py) — state, stateAt, stateEvent, endReason → turn state
 *
 * Each writer read-modify-writes only its own fields and must preserve the
 * other's. That is why `parseLease` carries the hook fields through instead of
 * rebuilding a bare record: `renewLease` heartbeats on every tick, so a parser
 * that dropped them would erase the hook's work within a second of it landing.
 *
 * The hook can reach this file with no server and no lookup — its payload
 * carries `session_id` and `transcript_path`, which is exactly
 * `leasePathForTranscript`'s input. That independence is the point: hooks fire
 * while `lfg serve` is restarting, and this file is in the SYNCED tree, so a
 * hook-written turn state reaches the other host too.
 */
export type LeaseRecord = {
  hostId: string;
  pid: number;
  acquiredAt: number;
  heartbeatAt: number;
  /** Hook-owned. Never written by this module. */
  state?: "running" | "idle" | "ended";
  stateAt?: number;
  stateEvent?: string;
  /** SessionEnd only: `clear`/`resume` mean the id rolled over, not a real close. */
  endReason?: string;
};

export type LeaseManagerDeps = {
  hostId: () => string;
  now: () => number;
  resolveTranscript: (sessionId: string) => Promise<string | null>;
};

/**
 * The id a transcript file is named for, or null if it isn't shaped like one.
 *
 *   claude:  <uuid>.jsonl
 *   codex:   rollout-2026-08-05T00-15-19-<uuid>.jsonl
 *
 * Anchored to the END so a codex rollout's timestamp segment can't be mistaken
 * for the id.
 */
export function sessionIdForTranscript(transcriptPath: string): string | null {
  const base = basename(transcriptPath).replace(/\.jsonl$/i, "");
  const m = base.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i);
  return m ? m[1] : null;
}

/**
 * Where a session's shared record lives: next to its transcript, named for the
 * id the TRANSCRIPT carries — not for lfg's session key.
 *
 * That distinction is load-bearing for codex. lfg keys a codex session by its own
 * `sessionId` (e.g. `3f8dfe1e-…`) while the agent knows itself by its thread id
 * (`019f03aa-…`), which is what the codex hook puts in its payload and what the
 * rollout file is named for. Keying this path on lfg's id produced TWO records
 * per codex session — the hook writing one name, lfg reading another — so the
 * hook's turn state was never found. Deriving the name from the file both parties
 * already agree on makes them converge by construction. Identical for claude,
 * where the two ids are the same.
 *
 * `sessionId` remains the fallback for a transcript whose name we can't parse.
 */
export function leasePathForTranscript(sessionId: string, transcriptPath: string): string {
  const id = sessionIdForTranscript(transcriptPath) ?? sessionId;
  return join(dirname(transcriptPath), `${id}.lease.json`);
}

export function parseLease(raw: string): LeaseRecord | null {
  try {
    const x = JSON.parse(raw) as Partial<LeaseRecord>;
    if (
      typeof x.hostId !== "string" ||
      !x.hostId ||
      typeof x.pid !== "number" ||
      !Number.isFinite(x.pid) ||
      typeof x.acquiredAt !== "number" ||
      !Number.isFinite(x.acquiredAt) ||
      typeof x.heartbeatAt !== "number" ||
      !Number.isFinite(x.heartbeatAt)
    ) {
      return null;
    }
    // Hook-owned fields are carried through untouched. Validate loosely: a
    // malformed value from the other writer must not invalidate the whole lease
    // (liveness would break, and liveness is what gates resume).
    const state =
      x.state === "running" || x.state === "idle" || x.state === "ended" ? x.state : undefined;
    return {
      hostId: x.hostId,
      pid: x.pid,
      acquiredAt: x.acquiredAt,
      heartbeatAt: x.heartbeatAt,
      ...(state ? { state } : {}),
      ...(typeof x.stateAt === "number" && Number.isFinite(x.stateAt) ? { stateAt: x.stateAt } : {}),
      ...(typeof x.stateEvent === "string" ? { stateEvent: x.stateEvent } : {}),
      ...(typeof x.endReason === "string" ? { endReason: x.endReason } : {}),
    };
  } catch {
    return null;
  }
}

export function leaseIsFresh(lease: LeaseRecord, now: number): boolean {
  return now - lease.heartbeatAt < LEASE_FRESH_MS;
}

async function defaultResolveTranscript(sessionId: string): Promise<string | null> {
  const sessions = await import("./sessions.ts");
  return sessions.resolveTranscript(sessionId);
}

async function atomicWriteJson(path: string, value: unknown): Promise<void> {
  const dir = dirname(path);
  await mkdir(dir, { recursive: true });
  const tmp = join(
    dir,
    `.${basename(path)}.${process.pid}.${Date.now()}.${randomBytes(4).toString("hex")}.tmp`,
  );
  try {
    await Bun.write(tmp, JSON.stringify(value, null, 2));
    await rename(tmp, path);
  } catch (e) {
    try {
      await unlink(tmp);
    } catch {}
    throw e;
  }
}

export function createLeaseManager(
  deps: Partial<LeaseManagerDeps> = {},
): {
  leasePath: (sessionId: string) => Promise<string | null>;
  readLease: (sessionId: string) => Promise<LeaseRecord | null>;
  acquireLease: (sessionId: string, pid: number) => Promise<boolean>;
  renewLease: (sessionId: string) => Promise<boolean>;
  releaseLease: (sessionId: string) => Promise<boolean>;
  ensureLease: (sessionId: string, pid: number) => Promise<boolean>;
  foreignFresh: (sessionId: string) => Promise<string | null>;
  foreignFreshAt: (sessionId: string, transcriptPath: string) => Promise<string | null>;
  anyFreshAt: (sessionId: string, transcriptPath: string) => Promise<string | null>;
} {
  const hostId = deps.hostId ?? (() => hostInfo().hostId);
  const now = deps.now ?? (() => Date.now());
  const resolveTranscript = deps.resolveTranscript ?? defaultResolveTranscript;

  const leasePath = async (sessionId: string): Promise<string | null> => {
    try {
      const transcript = await resolveTranscript(sessionId);
      return transcript ? leasePathForTranscript(sessionId, transcript) : null;
    } catch {
      return null;
    }
  };

  const readLeaseAt = async (path: string): Promise<LeaseRecord | null> => {
    try {
      return parseLease(await readFile(path, "utf8"));
    } catch {
      return null;
    }
  };

  const readLease = async (sessionId: string): Promise<LeaseRecord | null> => {
    const path = await leasePath(sessionId);
    return path ? readLeaseAt(path) : null;
  };

  const acquireLease = async (sessionId: string, pid: number): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const t = now();
    // Carry hook-owned fields across a takeover. They are the other writer's, and
    // a stale `state` cannot mislead: `sessionTurnState` arbitrates it by recency
    // against the transcript, so an outdated one simply loses.
    const prior = await readLeaseAt(path);
    try {
      await atomicWriteJson(path, {
        ...(prior ?? {}),
        hostId: hostId(),
        pid,
        acquiredAt: t,
        heartbeatAt: t,
      } satisfies LeaseRecord);
      return true;
    } catch {
      return false;
    }
  };

  /**
   * Make this host's claim on a live session current, without ever stealing one.
   *
   * `renewLease` alone could not do this: it no-ops unless the lease is ALREADY
   * ours, so it only maintained sessions lfg had explicitly spawned. Sessions lfg
   * merely adopted never got a lease at all — 7 of 16 on this machine — which is
   * fatal once `closed` is defined as "no fresh lease", because a leaseless
   * running session would read as ended.
   *
   * Driving this from enumeration (every session we can see, every tick) is what
   * makes that gap unrepresentable: there is no "remember to acquire" step to
   * forget.
   */
  const ensureLease = async (sessionId: string, pid: number): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const lease = await readLeaseAt(path);
    // Someone else holds it and is still alive: leave it alone. This is the
    // mutual-exclusion guarantee the lease exists for.
    if (lease && lease.hostId !== hostId() && leaseIsFresh(lease, now())) return false;
    if (lease && lease.hostId === hostId()) return renewLease(sessionId);
    return acquireLease(sessionId, pid);
  };

  const renewLease = async (sessionId: string): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const lease = await readLeaseAt(path);
    if (!lease || lease.hostId !== hostId()) return false;
    try {
      await atomicWriteJson(path, { ...lease, heartbeatAt: now() } satisfies LeaseRecord);
      return true;
    } catch {
      return false;
    }
  };

  const releaseLease = async (sessionId: string): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const lease = await readLeaseAt(path);
    if (!lease || lease.hostId !== hostId()) return false;
    try {
      await unlink(path);
      return true;
    } catch {
      return false;
    }
  };

  const foreignHostIfFresh = (lease: LeaseRecord | null): string | null => {
    if (!lease || !leaseIsFresh(lease, now())) return null;
    const ours = hostId();
    return lease.hostId !== ours ? lease.hostId : null;
  };

  const foreignFresh = async (sessionId: string): Promise<string | null> => {
    return foreignHostIfFresh(await readLease(sessionId));
  };

  const foreignFreshAt = async (sessionId: string, transcriptPath: string): Promise<string | null> => {
    return foreignHostIfFresh(await readLeaseAt(leasePathForTranscript(sessionId, transcriptPath)));
  };

  /**
   * Is ANY host — including this one — currently claiming this session?
   *
   * This is the single reader behind `closed`: a session is closed exactly when
   * nothing holds a fresh lease on it. `foreignFreshAt` answers a narrower
   * question (is a PEER on it), which was the right question while local liveness
   * came from a separate enumeration; now that `ensureLease` writes a lease for
   * every session we enumerate, local and remote are the same fact and deserve
   * the same question.
   */
  const anyFreshAt = async (sessionId: string, transcriptPath: string): Promise<string | null> => {
    const lease = await readLeaseAt(leasePathForTranscript(sessionId, transcriptPath));
    return lease && leaseIsFresh(lease, now()) ? lease.hostId : null;
  };

  return {
    leasePath, readLease, acquireLease, renewLease, releaseLease, ensureLease,
    foreignFresh, foreignFreshAt, anyFreshAt,
  };
}

const defaultManager = createLeaseManager();

export const leasePath = defaultManager.leasePath;
export const readLease = defaultManager.readLease;
export const acquireLease = defaultManager.acquireLease;
export const renewLease = defaultManager.renewLease;
export const ensureLease = defaultManager.ensureLease;
export const anyFreshAt = defaultManager.anyFreshAt;
export const releaseLease = defaultManager.releaseLease;
export const foreignFresh = defaultManager.foreignFresh;
export const foreignFreshAt = defaultManager.foreignFreshAt;
