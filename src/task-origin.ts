// Which scheduled task started a session — the Sessions list shows a repeat icon
// on those rows. Only the reverse link is stored (`TaskRun.sessionId`), so this
// inverts it.
//
// The list is polled, so the task store is read at most once per TTL rather than
// once per request; a failed read keeps the last good map instead of breaking the
// session list over an optional decoration.
import type { TaskRun } from "./scheduled-tasks.ts";

export type TaskOrigin = { id: string; name: string };

export function taskOriginsBySession(runs: readonly TaskRun[]): Map<string, TaskOrigin> {
  const map = new Map<string, TaskOrigin & { startedAt: number }>();
  for (const r of runs) {
    if (!r.sessionId) continue;
    const prev = map.get(r.sessionId);
    if (prev && prev.startedAt > r.startedAt) continue;
    map.set(r.sessionId, { id: r.taskId, name: r.taskName, startedAt: r.startedAt });
  }
  return new Map([...map].map(([sid, { id, name }]) => [sid, { id, name }]));
}

/** Returns the row unchanged unless a task started it. */
export function withTaskOrigin<T extends { sessionId?: string | null }>(
  row: T,
  origins: ReadonlyMap<string, TaskOrigin>,
): T | (T & { task: TaskOrigin }) {
  const task = row.sessionId ? origins.get(row.sessionId) : undefined;
  return task ? { ...row, task } : row;
}

export function cachedTaskOrigins(
  read: () => Promise<{ runs: readonly TaskRun[] }>,
  ttlMs = 5_000,
  now: () => number = Date.now,
): () => Promise<Map<string, TaskOrigin>> {
  let value = new Map<string, TaskOrigin>();
  let readAt = -Infinity;
  return async () => {
    if (now() - readAt < ttlMs) return value;
    try {
      value = taskOriginsBySession((await read()).runs);
    } catch {
      // Keep the last good map; the list must not fail over a decoration.
    }
    readAt = now();
    return value;
  };
}
