// TRANSPORT ONLY: how one prompt reaches the installed `claude` CLI and how its
// answer comes back. Autopilot tasks do not import this — they call `ask` /
// `askJson` in `claude.ts`, which adds retries, serialization, JSON salvage and
// task-labelled logging on top. This file's job is the subprocess and nothing
// else.
//
// Every call runs on the CLI's own OAuth session — the Claude Code subscription
// — never an API key.
//
// Modelled on gbrain's `claude-cli` provider
// (`~/.bun/install/global/node_modules/gbrain/src/core/ai/providers/claude-cli-language-model.ts`),
// which exists for exactly this reason: a background job that runs on a timer
// should bill the flat-rate subscription, not per-token API usage.
//
// Why not `pipeToClaudeAiSdk` (what autopilot used first): it drives the
// same binary, but through the `ai-sdk-provider-claude-code` package and with
// `settingSources: ["user", "project"]`. That loads the project's settings and
// CLAUDE.md and boots every configured MCP server on each call — measured at
// 25-56s per retitle batch, with `MCP servers not connected` warnings, for a task
// whose entire job is to summarise a few lines of text. The same call through
// this module takes ~6s.
//
// Four isolation measures, each load-bearing (flag set verified against claude
// CLI 2.1.220):
//
//   --tools ""              no built-in tools at all. The prompt already carries
//                           everything; a headless run that decides to go read
//                           files is a run that takes minutes.
//   --strict-mcp-config     ignore user-level MCP servers. Without it every call
//                           boots them — slow, noisy, and pointless here.
//   --disable-slash-commands  skip skill resolution.
//   clean cwd               spawn from an empty tmpdir so CLAUDE.md
//                           auto-discovery finds no project files.
//
// The user-level `~/.claude/CLAUDE.md` still loads (~8.5k cached tokens on this
// box). The only flag that skips it is `--bare`, which forces ANTHROPIC_API_KEY
// auth and so defeats the entire point of this module — same trade-off gbrain
// documents, and on a subscription the cached tokens are free.

import { mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** The binary to drive. Mirrors gbrain's `GBRAIN_CLAUDE_CLI_BIN` escape hatch. */
export function claudeBin(): string {
  return process.env.LFG_CLAUDE_PATH ?? Bun.which("claude") ?? "claude";
}

/** An empty directory, so the CLI's CLAUDE.md auto-discovery finds nothing. */
const CLEAN_CWD = join(tmpdir(), `lfg-autopilot-claude-cwd-${process.pid}`);
let cwdReady = false;
async function ensureCleanCwd(): Promise<string> {
  if (!cwdReady) {
    await mkdir(CLEAN_CWD, { recursive: true });
    cwdReady = true;
  }
  return CLEAN_CWD;
}

export function buildArgs(model: string, system?: string): string[] {
  const args = [
    "--print",
    "--output-format",
    "json",
    "--model",
    model,
    "--disable-slash-commands",
    "--tools",
    "",
    "--strict-mcp-config",
  ];
  if (system) args.push("--system-prompt", system);
  return args;
}

/**
 * Strip every API-key route out of the child's environment.
 *
 * This is the whole point of the module, and it must be unconditional: if any of
 * these is set — by `.env`, a shell profile, or a parent agent — the CLI
 * silently switches to per-token API billing and nothing in the output says so.
 */
export function scrubbedEnv(base: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv {
  const env = { ...base };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;
  delete env.ANTHROPIC_BASE_URL;
  return env;
}

/** The `--output-format json` envelope. */
type ClaudeJsonResult = {
  type?: string;
  subtype?: string;
  is_error?: boolean;
  result?: string;
  total_cost_usd?: number;
  duration_ms?: number;
  modelUsage?: Record<string, { provider?: string }>;
};

/** Pull the assistant text out of the envelope, or throw with a usable message. */
export function parseEnvelope(stdout: string): {
  text: string;
  costUsd?: number;
  provider?: string;
} {
  const trimmed = stdout.trim();
  if (!trimmed) throw new Error("claude --print produced no output");
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    throw new Error(`claude --print output was not JSON: ${trimmed.slice(0, 300)}`);
  }
  // `--output-format json` normally emits one object, but can emit an array of
  // events; the result envelope is the last one either way.
  const envelope = (
    Array.isArray(parsed) ? parsed[parsed.length - 1] : parsed
  ) as ClaudeJsonResult;
  if (!envelope || typeof envelope !== "object") {
    throw new Error("claude --print returned an unrecognised envelope");
  }
  if (envelope.is_error || (envelope.subtype && envelope.subtype !== "success")) {
    throw new Error(
      `claude --print reported an error (${envelope.subtype ?? "unknown"}): ` +
        String(envelope.result ?? "").slice(0, 400),
    );
  }
  return {
    text: typeof envelope.result === "string" ? envelope.result : "",
    costUsd: envelope.total_cost_usd,
    provider: Object.values(envelope.modelUsage ?? {})[0]?.provider,
  };
}

export type ClaudeCliOptions = {
  prompt: string;
  system?: string;
  model: string;
  timeoutMs?: number;
  log?: (line: string) => void;
};

/** Run one prompt and return the assistant's text. */
export async function runClaudeCli(opts: ClaudeCliOptions): Promise<string> {
  const log = opts.log ?? (() => {});
  const timeoutMs = opts.timeoutMs ?? 120_000;
  const bin = claudeBin();
  const cwd = await ensureCleanCwd();

  log(`[claude-cli] ${opts.model} via subscription OAuth (${opts.prompt.length} chars)`);

  const proc = Bun.spawn({
    cmd: [bin, ...buildArgs(opts.model, opts.system)],
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    cwd,
    env: scrubbedEnv(),
  });

  proc.stdin.write(opts.prompt);
  await proc.stdin.end();

  const timer = setTimeout(() => {
    log(`[claude-cli] timed out after ${timeoutMs}ms — killing`);
    proc.kill();
  }, timeoutMs);

  let stdout: string;
  let stderr: string;
  let exitCode: number;
  try {
    [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);
  } finally {
    clearTimeout(timer);
  }

  if (exitCode !== 0) {
    throw new Error(
      `claude --print exited ${exitCode}: ${(stderr || stdout).trim().slice(0, 400)}`,
    );
  }

  const { text, costUsd, provider } = parseEnvelope(stdout);
  log(
    `[claude-cli] done (${text.length} chars` +
      (provider ? `, provider=${provider}` : "") +
      (costUsd !== undefined ? `, nominal $${costUsd.toFixed(4)}` : "") +
      ")",
  );
  return text;
}
