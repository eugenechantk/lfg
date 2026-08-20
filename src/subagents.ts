import { createReadStream, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { createInterface } from "node:readline";
import { basename, dirname, join } from "node:path";

export type SubagentStatus = "running" | "completed" | "failed" | "stopped" | "unknown";

export type SubagentSession = {
  id: string;
  description: string;
  agentType: string;
  spawnDepth: number;
  status: SubagentStatus;
  startedAt: number | null;
  lastActivityAt: number | null;
  finishedAt: number | null;
};

type ParentWithBusy = { busy: boolean };

export function busyWithRunningWork(
  parentBusy: boolean,
  runningChildAgentCount: number,
  runningBackgroundProcessCount: number,
): boolean {
  return parentBusy || runningChildAgentCount > 0 || runningBackgroundProcessCount > 0;
}

/**
 * Fold delegated work into the parent snapshot without erasing the parent's
 * own turn state. This stays generic so the transcript readers remain
 * independent of the much larger sessions module.
 */
export function withSessionWorkActivity<T extends ParentWithBusy>(
  parent: T,
  agents: ReadonlyArray<Pick<SubagentSession, "status">>,
  runningBackgroundProcessCount: number,
): Omit<T, "busy"> & {
  busy: boolean;
  runningChildAgentCount: number;
  runningBackgroundProcessCount: number;
} {
  const runningChildAgentCount = agents.filter((agent) => agent.status === "running").length;
  return {
    ...parent,
    busy: busyWithRunningWork(
      parent.busy,
      runningChildAgentCount,
      runningBackgroundProcessCount,
    ),
    runningChildAgentCount,
    runningBackgroundProcessCount,
  };
}

type Launch = {
  description: string | null;
  agentType: string | null;
  timestamp: number | null;
};

type Lifecycle = {
  status: SubagentStatus;
  timestamp: number | null;
};

type ParentEvents = {
  launchesByToolUseId: Map<string, Launch>;
  lifecycleByAgentId: Map<string, Lifecycle>;
  lifecycleByToolUseId: Map<string, Lifecycle>;
  backgroundProcesses: Map<string, string>;
};

type CacheEntry = {
  signature: string;
  sessions: SubagentSession[];
};

type ParentEventsCacheEntry = {
  signature: string;
  events: ParentEvents;
};

const cache = new Map<string, CacheEntry>();
const parentEventsCache = new Map<string, ParentEventsCacheEntry>();
const SAFE_AGENT_ID = /^[A-Za-z0-9_-]{1,128}$/;

function timestamp(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function nonempty(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function sidecarDirectory(parentTranscript: string): string {
  return join(
    dirname(parentTranscript),
    basename(parentTranscript).replace(/\.jsonl$/i, ""),
    "subagents",
  );
}

function xmlValue(body: string, tag: string): string | null {
  const match = new RegExp(`<${tag}>([^<]*)<\\/${tag}>`).exec(body);
  return match?.[1]?.trim() || null;
}

function xmlValues(body: string, tag: string): string[] {
  return Array.from(body.matchAll(new RegExp(`<${tag}>([^<]*)<\\/${tag}>`, "g")))
    .map((match) => match[1]?.trim() ?? "")
    .filter(Boolean);
}

function mapStatus(raw: string | null): SubagentStatus {
  switch (raw?.toLowerCase()) {
    case "running": return "running";
    case "completed": return "completed";
    case "failed": return "failed";
    case "killed":
    case "stopped": return "stopped";
    default: return "unknown";
  }
}

function isTerminal(status: SubagentStatus): boolean {
  return status === "completed" || status === "failed" || status === "stopped";
}

async function readParentEvents(path: string): Promise<ParentEvents> {
  const launchesByToolUseId = new Map<string, Launch>();
  const lifecycleByAgentId = new Map<string, Lifecycle>();
  const lifecycleByToolUseId = new Map<string, Lifecycle>();
  const backgroundProcesses = new Map<string, string>();
  if (!existsSync(path)) {
    return {
      launchesByToolUseId,
      lifecycleByAgentId,
      lifecycleByToolUseId,
      backgroundProcesses,
    };
  }

  const lines = createInterface({ input: createReadStream(path), crlfDelay: Infinity });
  for await (const line of lines) {
    if (
      !line.includes('"Agent"')
      && !line.includes("<task-notification>")
      && !line.includes('"backgroundTaskId"')
    ) continue;
    let row: Record<string, unknown>;
    try {
      row = JSON.parse(line) as Record<string, unknown>;
    } catch {
      continue;
    }
    const at = timestamp(row.timestamp);
    const toolUseResult = row.toolUseResult as Record<string, unknown> | undefined;
    const backgroundProcessId = nonempty(toolUseResult?.backgroundTaskId);
    if (backgroundProcessId && SAFE_AGENT_ID.test(backgroundProcessId)) {
      const resultContent = JSON.stringify((row.message as { content?: unknown } | undefined)?.content);
      const outputFile = /Output is being written to:\s*([^"\n]+?\.output)\b/.exec(resultContent)?.[1];
      if (outputFile?.startsWith("/")) backgroundProcesses.set(backgroundProcessId, outputFile);
    }
    const message = row.message as { content?: unknown } | undefined;
    if (Array.isArray(message?.content)) {
      for (const block of message.content as Array<Record<string, unknown>>) {
        if (block.type !== "tool_use" || block.name !== "Agent" || typeof block.id !== "string") {
          continue;
        }
        const input = block.input as Record<string, unknown> | undefined;
        launchesByToolUseId.set(block.id, {
          description: nonempty(input?.description),
          agentType: nonempty(input?.subagent_type),
          timestamp: at,
        });
      }
    }
    const content = typeof row.content === "string" ? row.content : null;
    if (!content?.includes("<task-notification>")) continue;
    const event: Lifecycle = { status: mapStatus(xmlValue(content, "status")), timestamp: at };
    const agentIds = xmlValues(content, "task-id").map((id) => id.replace(/^agent-/, ""));
    const toolUseId = xmlValue(content, "tool-use-id");
    for (const agentId of agentIds) {
      if (SAFE_AGENT_ID.test(agentId)) lifecycleByAgentId.set(agentId, event);
    }
    if (toolUseId) lifecycleByToolUseId.set(toolUseId, event);
  }
  return {
    launchesByToolUseId,
    lifecycleByAgentId,
    lifecycleByToolUseId,
    backgroundProcesses,
  };
}

function fileSignature(path: string): string {
  try {
    const stat = statSync(path);
    return `${stat.size}:${stat.mtimeMs}`;
  } catch {
    return "missing";
  }
}

async function parentEvents(path: string): Promise<ParentEvents> {
  const signature = fileSignature(path);
  const cached = parentEventsCache.get(path);
  if (cached?.signature === signature) return cached.events;
  const events = await readParentEvents(path);
  parentEventsCache.set(path, { signature, events });
  return events;
}

async function transcriptTimes(path: string): Promise<{ first: number | null; last: number | null }> {
  let first: number | null = null;
  let last: number | null = null;
  if (!existsSync(path)) return { first, last };
  const lines = createInterface({ input: createReadStream(path), crlfDelay: Infinity });
  for await (const line of lines) {
    if (!line.includes('"timestamp"')) continue;
    try {
      const at = timestamp((JSON.parse(line) as Record<string, unknown>).timestamp);
      if (at == null) continue;
      first = first == null ? at : Math.min(first, at);
      last = last == null ? at : Math.max(last, at);
    } catch {}
  }
  return { first, last };
}

function directorySignature(parentTranscript: string, sidecars: string): string {
  const parts: string[] = [];
  try {
    const stat = statSync(parentTranscript);
    parts.push(`${stat.size}:${stat.mtimeMs}`);
  } catch {
    parts.push("missing-parent");
  }
  try {
    for (const name of readdirSync(sidecars).sort()) {
      if (!name.endsWith(".jsonl") && !name.endsWith(".meta.json")) continue;
      const stat = statSync(join(sidecars, name));
      parts.push(`${name}:${stat.size}:${stat.mtimeMs}`);
    }
  } catch {
    parts.push("missing-sidecars");
  }
  return parts.join("|");
}

export async function listSubagentSessions(parentTranscript: string): Promise<SubagentSession[]> {
  const sidecars = sidecarDirectory(parentTranscript);
  if (!existsSync(sidecars)) return [];
  let names: string[];
  try {
    names = readdirSync(sidecars);
  } catch {
    return [];
  }
  const signature = directorySignature(parentTranscript, sidecars);
  const cached = cache.get(parentTranscript);
  if (cached?.signature === signature) return cached.sessions;

  const events = await parentEvents(parentTranscript);
  const sessions: SubagentSession[] = [];
  for (const name of names.sort()) {
    const match = /^agent-([A-Za-z0-9_-]{1,128})\.meta\.json$/.exec(name);
    if (!match) continue;
    const id = match[1];
    let meta: Record<string, unknown>;
    try {
      meta = JSON.parse(readFileSync(join(sidecars, name), "utf8")) as Record<string, unknown>;
    } catch {
      continue;
    }
    const toolUseId = nonempty(meta.toolUseId);
    const launch = toolUseId ? events.launchesByToolUseId.get(toolUseId) : undefined;
    const lifecycle = events.lifecycleByAgentId.get(id)
      ?? (toolUseId ? events.lifecycleByToolUseId.get(toolUseId) : undefined);
    const childPath = join(sidecars, `agent-${id}.jsonl`);
    if (!existsSync(childPath)) continue;
    const times = await transcriptTimes(childPath);
    const status = lifecycle?.status ?? "running";
    const startedAt = launch?.timestamp ?? times.first;
    const lastActivityAt = [times.last, lifecycle?.timestamp ?? null]
      .filter((value): value is number => value != null)
      .reduce<number | null>((latest, value) => latest == null ? value : Math.max(latest, value), null);
    sessions.push({
      id,
      description: nonempty(meta.description) ?? launch?.description ?? "Child agent",
      agentType: nonempty(meta.agentType) ?? launch?.agentType ?? "Agent",
      spawnDepth:
        typeof meta.spawnDepth === "number" && Number.isFinite(meta.spawnDepth) && meta.spawnDepth >= 1
          ? Math.floor(meta.spawnDepth)
          : 1,
      status,
      startedAt,
      lastActivityAt,
      finishedAt: lifecycle && isTerminal(status) ? lifecycle.timestamp : null,
    });
  }
  sessions.sort((a, b) =>
    (b.lastActivityAt ?? b.startedAt ?? 0) - (a.lastActivityAt ?? a.startedAt ?? 0)
      || a.description.localeCompare(b.description));
  cache.set(parentTranscript, { signature, sessions });
  return sessions;
}

export type BackgroundProcessProbe = (outputFiles: string[]) => ReadonlySet<string>;

function openBackgroundOutputFiles(outputFiles: string[]): ReadonlySet<string> {
  const files = Array.from(new Set(outputFiles)).slice(-64);
  if (files.length === 0) return new Set();
  try {
    const result = Bun.spawnSync(["lsof", "-nP", "-Fn", "--", ...files]);
    const open = new Set<string>();
    for (const line of new TextDecoder().decode(result.stdout).split("\n")) {
      if (line.startsWith("n/")) open.add(line.slice(1));
    }
    return open;
  } catch {
    return new Set();
  }
}

/**
 * Active Claude Bash tasks. Transcript lifecycle identifies candidates; an
 * open output file proves the command still has a live process and prevents a
 * missed notification from pinning the parent Working forever.
 */
export async function runningBackgroundProcessCount(
  parentTranscript: string,
  probe: BackgroundProcessProbe = openBackgroundOutputFiles,
): Promise<number> {
  return (await runningBackgroundProcessCounts([parentTranscript], probe))
    .get(parentTranscript) ?? 0;
}

/**
 * Batch the liveness proof for a session-list snapshot into one `lsof` call.
 * The list can contain dozens of parents, so probing once per transcript would
 * recreate the process-spawn fan-out that listSessions deliberately coalesces.
 */
export async function runningBackgroundProcessCounts(
  parentTranscripts: readonly string[],
  probe: BackgroundProcessProbe = openBackgroundOutputFiles,
): Promise<Map<string, number>> {
  const unique = Array.from(new Set(parentTranscripts));
  const candidatesByTranscript = new Map<string, string[]>();
  await Promise.all(unique.map(async (parentTranscript) => {
    const events = await parentEvents(parentTranscript);
    const candidates: string[] = [];
    for (const [id, outputFile] of events.backgroundProcesses) {
      const lifecycle = events.lifecycleByAgentId.get(id);
      if (!lifecycle || !isTerminal(lifecycle.status)) candidates.push(outputFile);
    }
    candidatesByTranscript.set(parentTranscript, candidates);
  }));
  const open = probe(Array.from(candidatesByTranscript.values()).flat());
  return new Map(unique.map((parentTranscript) => [
    parentTranscript,
    (candidatesByTranscript.get(parentTranscript) ?? [])
      .filter((outputFile) => open.has(outputFile)).length,
  ]));
}

export function resolveSubagentTranscript(
  parentTranscript: string,
  agentId: string,
): string | null {
  if (!SAFE_AGENT_ID.test(agentId)) return null;
  const path = join(sidecarDirectory(parentTranscript), `agent-${agentId}.jsonl`);
  return existsSync(path) ? path : null;
}

export function resetSubagentCacheForTests(): void {
  cache.clear();
  parentEventsCache.clear();
}
