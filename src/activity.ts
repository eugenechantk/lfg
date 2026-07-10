import { readdirSync, readFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const CODEX_SCAN_TTL_MS = 2000;
const PANE_BUSY_TTL_MS = 10_000;

let delegationCache: { at: number; ids: Set<string> } | null = null;
const paneBusyCache = new Map<string, { busy: boolean; at: number }>();

export function defaultCodexStateRoots(): string[] {
  return [
    join(homedir(), ".claude", "plugins", "data", "codex-openai-codex", "state"),
    join(tmpdir(), "codex-companion"),
  ];
}

function pidAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export function scanStateRoots(roots: string[]): Set<string> {
  const active = new Set<string>();
  for (const root of roots) {
    let entries;
    try {
      entries = readdirSync(root, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      let parsed: unknown;
      try {
        parsed = JSON.parse(readFileSync(join(root, entry.name, "state.json"), "utf8"));
      } catch {
        continue;
      }
      const jobs = (parsed as { jobs?: unknown }).jobs;
      if (!Array.isArray(jobs)) continue;
      for (const job of jobs) {
        if (!job || typeof job !== "object") continue;
        const record = job as Record<string, unknown>;
        const sessionId = typeof record.sessionId === "string" ? record.sessionId : "";
        const pid = typeof record.pid === "number" ? record.pid : null;
        if (record.status === "running" && sessionId && pid != null && pidAlive(pid)) {
          active.add(sessionId);
        }
      }
    }
  }
  return active;
}

export function codexDelegationSessionIds(now: () => number = Date.now): Set<string> {
  const at = now();
  if (delegationCache && at - delegationCache.at < CODEX_SCAN_TTL_MS) {
    return new Set(delegationCache.ids);
  }
  const ids = scanStateRoots(defaultCodexStateRoots());
  delegationCache = { at, ids };
  return new Set(ids);
}

export function notePaneBusy(sid: string, busy: boolean, at: number = Date.now()): void {
  paneBusyCache.set(sid, { busy, at });
}

export function lastPaneBusy(sid: string, at: number = Date.now()): boolean | null {
  const hit = paneBusyCache.get(sid);
  if (!hit) return null;
  if (at - hit.at > PANE_BUSY_TTL_MS) {
    paneBusyCache.delete(sid);
    return null;
  }
  return hit.busy;
}
