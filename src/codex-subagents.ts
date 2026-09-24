import { scanBack } from "./transcript.ts";
import type { SubagentSession, SubagentStatus } from "./subagents.ts";

export type CodexSubagentThread = {
  id: string;
  path: string;
  parentThreadId: string | null;
  agentPath: string | null;
  agentNickname: string | null;
  agentRole: string | null;
  spawnDepth: number | null;
  createdAt: number | null;
  updatedAt: number | null;
};

type Lifecycle = {
  status: SubagentStatus;
  at: number | null;
  lastActivityAt: number | null;
};

const RUNNING_STALE_MS = 30 * 60_000;

function parsedTimestamp(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function taskDescription(thread: CodexSubagentThread): string {
  const task = thread.agentPath?.split("/").filter(Boolean).at(-1);
  if (task) return task.replace(/[_-]+/g, " ");
  return thread.agentNickname?.trim() || "Child agent";
}

async function lifecycle(path: string): Promise<Lifecycle> {
  let newestRecordAt: number | null = null;
  const latest = await scanBack(path, (line): Omit<Lifecycle, "lastActivityAt"> | null => {
    let row: {
      timestamp?: unknown;
      type?: unknown;
      payload?: { type?: unknown; error?: unknown };
    };
    try {
      row = JSON.parse(line);
    } catch {
      return null;
    }
    const at = parsedTimestamp(row.timestamp);
    if (newestRecordAt == null && at != null) newestRecordAt = at;
    if (row.type !== "event_msg") return null;
    switch (row.payload?.type) {
      case "task_started":
        return { status: "running", at };
      case "task_complete":
        return { status: row.payload.error == null ? "completed" : "failed", at };
      case "turn_aborted":
        return { status: "stopped", at };
      default:
        return null;
    }
  });
  return {
    status: latest?.status ?? "unknown",
    at: latest?.at ?? null,
    lastActivityAt: newestRecordAt,
  };
}

function descendantThreads(
  parentId: string,
  threads: readonly CodexSubagentThread[],
): CodexSubagentThread[] {
  const byParent = new Map<string, CodexSubagentThread[]>();
  for (const thread of threads) {
    if (!thread.parentThreadId || thread.parentThreadId === thread.id) continue;
    const siblings = byParent.get(thread.parentThreadId) ?? [];
    siblings.push(thread);
    byParent.set(thread.parentThreadId, siblings);
  }

  const descendants: CodexSubagentThread[] = [];
  const visited = new Set<string>([parentId]);
  const visit = (id: string) => {
    for (const child of byParent.get(id) ?? []) {
      if (visited.has(child.id)) continue;
      visited.add(child.id);
      descendants.push(child);
      visit(child.id);
    }
  };
  visit(parentId);
  return descendants;
}

export async function listCodexSubagentSessions(
  parentId: string,
  threads: readonly CodexSubagentThread[],
  now: number = Date.now(),
): Promise<SubagentSession[]> {
  const descendants = descendantThreads(parentId, threads);
  const agents = await Promise.all(descendants.map(async (thread) => {
    const state = await lifecycle(thread.path);
    const lastActivityAt = state.lastActivityAt ?? thread.updatedAt;
    const status =
      state.status === "running"
      && lastActivityAt != null
      && now - lastActivityAt > RUNNING_STALE_MS
        ? "unknown"
        : state.status;
    return {
      id: thread.id,
      description: taskDescription(thread),
      agentType: thread.agentRole?.trim() || "Codex agent",
      spawnDepth: Math.max(1, thread.spawnDepth ?? 1),
      status,
      startedAt: thread.createdAt,
      lastActivityAt,
      finishedAt: status === "completed" || status === "failed" || status === "stopped"
        ? state.at
        : null,
    } satisfies SubagentSession;
  }));
  return agents.sort((a, b) =>
    (b.lastActivityAt ?? b.startedAt ?? 0) - (a.lastActivityAt ?? a.startedAt ?? 0)
      || a.description.localeCompare(b.description));
}

export function codexSubagentTranscriptFor(
  parentId: string,
  childId: string,
  threads: readonly CodexSubagentThread[],
): string | null {
  const byId = new Map(threads.map((thread) => [thread.id, thread]));
  const child = byId.get(childId);
  if (!child || childId === parentId) return null;

  const visited = new Set<string>([childId]);
  let ancestor = child.parentThreadId;
  while (ancestor) {
    if (ancestor === parentId) return child.path;
    if (visited.has(ancestor)) return null;
    visited.add(ancestor);
    ancestor = byId.get(ancestor)?.parentThreadId ?? null;
  }
  return null;
}
