import { readdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { claudeBin, codexBin } from "./tmux.ts";

export type AgentModelCatalog = {
  version: string | null;
  defaultModel: string;
  models: string[];
};

export type ModelCatalogResponse = {
  agents: {
    claude: AgentModelCatalog;
    codex: AgentModelCatalog;
  };
};

export const BUNDLED_MODEL_CATALOG: ModelCatalogResponse = {
  agents: {
    claude: {
      version: null,
      defaultModel: "claude-opus-5-5",
      models: [
        "claude-opus-5-5",
        "claude-fable-5-1",
        "claude-sonnet-5",
        "claude-haiku-4-5-20251001",
      ],
    },
    codex: {
      version: null,
      defaultModel: "gpt-6-astra",
      models: [
        "gpt-6-astra",
        "gpt-6-sol",
        "gpt-6-luna",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.5",
      ],
    },
  },
};

const MODEL_ID_RE = /^[A-Za-z0-9_.:-]{1,80}$/;

export function isSafeModelId(value: unknown): value is string {
  return typeof value === "string" && MODEL_ID_RE.test(value);
}

function uniqueSafeModels(values: unknown[]): string[] {
  return [...new Set(values.filter(isSafeModelId))];
}

export function parseClaudeCatalog(raw: string, version: string | null): AgentModelCatalog | null {
  try {
    const parsed = JSON.parse(raw) as {
      catalog?: {
        config?: { models?: Array<{ id?: unknown; section?: unknown }> };
        state?: { model?: unknown };
      };
    };
    const entries = parsed.catalog?.config?.models;
    if (!Array.isArray(entries)) return null;
    const models = uniqueSafeModels(
      entries.filter(entry => entry?.section === "main").map(entry => entry?.id),
    );
    if (models.length === 0) return null;
    const stateModel = parsed.catalog?.state?.model;
    const defaultModel = isSafeModelId(stateModel) && models.includes(stateModel)
      ? stateModel
      : models[0]!;
    return { version, defaultModel, models };
  } catch {
    return null;
  }
}

export function parseCodexModelListOutput(raw: string, version: string | null): AgentModelCatalog | null {
  let response: {
    id?: unknown;
    result?: { data?: Array<{ model?: unknown; hidden?: unknown; isDefault?: unknown }> };
  } | null = null;
  for (const line of raw.split("\n")) {
    try {
      const candidate = JSON.parse(line);
      if (candidate?.id === 2 && Array.isArray(candidate?.result?.data)) response = candidate;
    } catch {
      // App-server stderr/config warnings are not protocol responses.
    }
  }
  const entries = response?.result?.data;
  if (!entries) return null;
  const visible = entries.filter(entry => entry?.hidden !== true && isSafeModelId(entry?.model));
  const models = uniqueSafeModels(visible.map(entry => entry.model));
  if (models.length === 0) return null;
  const providerDefault = visible.find(entry => entry.isDefault === true)?.model;
  const defaultModel = isSafeModelId(providerDefault) && models.includes(providerDefault)
    ? providerDefault
    : models[0]!;
  return { version, defaultModel, models };
}

export function mergeWithBundledFallbacks(discovered: {
  claude: AgentModelCatalog | null;
  codex: AgentModelCatalog | null;
}): ModelCatalogResponse {
  return {
    agents: {
      claude: discovered.claude ?? BUNDLED_MODEL_CATALOG.agents.claude,
      codex: discovered.codex ?? BUNDLED_MODEL_CATALOG.agents.codex,
    },
  };
}

async function executableVersion(bin: string, pattern: RegExp): Promise<string | null> {
  try {
    const proc = Bun.spawn([bin, "--version"], { stdout: "pipe", stderr: "ignore" });
    const output = await new Response(proc.stdout).text();
    if (await proc.exited !== 0) return null;
    return output.match(pattern)?.[1] ?? null;
  } catch {
    return null;
  }
}

async function discoverClaudeModels(): Promise<AgentModelCatalog | null> {
  const version = await executableVersion(claudeBin(), /\b(\d+\.\d+\.\d+)\b/);
  const cacheDir = join(process.env.HOME ?? homedir(), ".claude", "cache", "model-catalog");
  try {
    const candidates: Array<{ fetchedAt: number; raw: string }> = [];
    for (const entry of await readdir(cacheDir, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
      const raw = await readFile(join(cacheDir, entry.name), "utf8");
      try {
        const fetchedAt = Number((JSON.parse(raw) as { fetchedAt?: unknown }).fetchedAt ?? 0);
        candidates.push({ fetchedAt: Number.isFinite(fetchedAt) ? fetchedAt : 0, raw });
      } catch {
        // Ignore corrupt/partially replaced cache files.
      }
    }
    candidates.sort((a, b) => b.fetchedAt - a.fetchedAt);
    for (const candidate of candidates) {
      const parsed = parseClaudeCatalog(candidate.raw, version);
      if (parsed) return parsed;
    }
  } catch {
    // Missing cache is expected on a fresh or signed-out Claude Code install.
  }
  return null;
}

async function readProtocolLine(
  reader: { read: () => Promise<{ done: boolean; value?: Uint8Array }> },
  state: { buffer: string },
  predicate: (value: unknown) => boolean,
  deadline: number,
): Promise<unknown> {
  const decoder = new TextDecoder();
  while (Date.now() < deadline) {
    let newline = state.buffer.indexOf("\n");
    while (newline >= 0) {
      const line = state.buffer.slice(0, newline);
      state.buffer = state.buffer.slice(newline + 1);
      try {
        const parsed = JSON.parse(line);
        if (predicate(parsed)) return parsed;
      } catch {}
      newline = state.buffer.indexOf("\n");
    }
    const remaining = Math.max(1, deadline - Date.now());
    const chunk = await Promise.race([
      reader.read(),
      Bun.sleep(remaining).then(() => null),
    ]);
    if (chunk == null) throw new Error("Codex model discovery timed out");
    if (chunk.done || !chunk.value) throw new Error("Codex app-server exited before model/list");
    state.buffer += decoder.decode(chunk.value, { stream: true });
  }
  throw new Error("Codex model discovery timed out");
}

async function discoverCodexModels(): Promise<AgentModelCatalog | null> {
  const bin = codexBin();
  const version = await executableVersion(bin, /\b(\d+\.\d+\.\d+)\b/);
  let proc: ReturnType<typeof Bun.spawn> | null = null;
  try {
    proc = Bun.spawn([bin, "app-server", "--stdio"], {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "ignore",
    });
    if (!proc.stdout || typeof proc.stdout === "number"
        || !proc.stdin || typeof proc.stdin === "number") return null;
    const input = proc.stdin;
    const reader = proc.stdout.getReader();
    const state = { buffer: "" };
    const deadline = Date.now() + 5_000;
    input.write(JSON.stringify({
      id: 1,
      method: "initialize",
      params: { clientInfo: { name: "lfg-model-catalog", version: "1" }, capabilities: {} },
    }) + "\n");
    await readProtocolLine(reader, state, value => (value as { id?: unknown })?.id === 1, deadline);
    input.write(JSON.stringify({ method: "initialized" }) + "\n");
    input.write(JSON.stringify({
      id: 2,
      method: "model/list",
      params: { includeHidden: false, limit: 100 },
    }) + "\n");
    const response = await readProtocolLine(
      reader,
      state,
      value => (value as { id?: unknown })?.id === 2,
      deadline,
    );
    return parseCodexModelListOutput(JSON.stringify(response), version);
  } catch {
    return null;
  } finally {
    try {
      const input = proc?.stdin;
      if (input && typeof input !== "number") input.end();
    } catch {}
    try { proc?.kill(); } catch {}
  }
}

let cached: { expiresAt: number; value: ModelCatalogResponse } | null = null;
let inFlight: Promise<ModelCatalogResponse> | null = null;

export async function currentModelCatalog(force = false): Promise<ModelCatalogResponse> {
  if (!force && cached && cached.expiresAt > Date.now()) return cached.value;
  if (inFlight) return inFlight;
  inFlight = (async () => {
    const [claude, codex] = await Promise.all([discoverClaudeModels(), discoverCodexModels()]);
    const value = mergeWithBundledFallbacks({ claude, codex });
    cached = { expiresAt: Date.now() + 15_000, value };
    return value;
  })();
  try {
    return await inFlight;
  } finally {
    inFlight = null;
  }
}
