import { readFileSync } from "node:fs";
import { rename, unlink } from "node:fs/promises";
import { join } from "node:path";
import { PATHS } from "./config.ts";

/**
 * When each session was last seen running on THIS host.
 *
 * A closed row belongs to the machine that ran the session most recently, so a
 * fork or tool switch from it runs there. Only that machine can say so: the
 * transcript is synced and names no host, lease files are not synced
 * (`~/.claude/.stignore`), and the agent hook deletes a lease the moment its
 * session genuinely ends — that is how `closed` resolves at once. So each host
 * keeps this ledger in `PATHS.data` (host-local), fed by the lease heartbeat,
 * and reports it as `lastRunHereAt`; clients compare the hosts' answers.
 */
export type RanHereLedger = {
  note: (sessionIds: Iterable<string>, now?: number) => Promise<void>;
  at: (sessionId: string) => number | null;
};

export function createRanHereLedger(
  path: string,
  opts: { minAdvanceMs?: number; maxEntries?: number } = {},
): RanHereLedger {
  // The heartbeat ticks every 30s; rewriting the file for a timestamp that
  // moved less than this buys nothing a host comparison can use.
  const minAdvance = opts.minAdvanceMs ?? 60_000;
  const maxEntries = opts.maxEntries ?? 20_000;
  let seen: Record<string, number> | null = null;

  const load = (): Record<string, number> => {
    if (seen) return seen;
    try {
      const raw = JSON.parse(readFileSync(path, "utf8")) as unknown;
      seen = raw && typeof raw === "object" && !Array.isArray(raw)
        ? Object.fromEntries(
            Object.entries(raw).filter(([, v]) => typeof v === "number" && Number.isFinite(v)),
          ) as Record<string, number>
        : {};
    } catch {
      seen = {};
    }
    return seen;
  };

  const note = async (sessionIds: Iterable<string>, now = Date.now()): Promise<void> => {
    const map = load();
    let changed = false;
    for (const id of sessionIds) {
      if (!id) continue;
      const prev = map[id];
      if (prev == null || now - prev >= minAdvance) {
        map[id] = now;
        changed = true;
      }
    }
    if (!changed) return;
    let out = map;
    const entries = Object.entries(map);
    if (entries.length > maxEntries) {
      entries.sort((a, b) => b[1] - a[1]);
      out = seen = Object.fromEntries(entries.slice(0, maxEntries));
    }
    const tmp = `${path}.${process.pid}.tmp`;
    try {
      await Bun.write(tmp, JSON.stringify(out));
      await rename(tmp, path);
    } catch {
      await unlink(tmp).catch(() => {});
    }
  };

  return { note, at: (sessionId) => load()[sessionId] ?? null };
}

const ledger = createRanHereLedger(join(PATHS.data, "ran-here.json"));

export const noteRunningHere = ledger.note;
export const ranHereAt = ledger.at;
