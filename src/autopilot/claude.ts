// The autopilot's Claude service — how EVERY maintenance task asks a question.
//
// Tasks should never spawn the CLI themselves. They call `ask` (text back) or
// `askJson` (parsed structure back) and get four things they'd otherwise each
// have to reinvent, wrongly:
//
//   1. Subscription auth. Every call runs on the installed `claude` CLI's OAuth
//      session with the API-key env vars stripped (see `claude-cli.ts`). A task
//      cannot accidentally opt into per-token API billing.
//   2. Tolerant JSON extraction. "Reply with only JSON" holds most of the time,
//      not all of it. The salvage ladder (bare → fenced → embedded) lived inside
//      the retitle task first; it is generic, and the second task to need it
//      would have copy-pasted it.
//   3. Serialization. Each call is a subprocess. lfg runs on ONE Bun event loop
//      and this repo bans fan-out over a growing collection — a task looping
//      `ask` over N sessions would be exactly that. Calls queue instead.
//   4. One log vocabulary, labelled by task, so `~/.lfg/autopilot.log` and the
//      serve log stay readable once several tasks are asking.
//
// Model policy lives here too: autopilot work is short summarisation and
// classification, so the default is deliberately the cheapest model. A task that
// genuinely needs more reasoning passes `model` explicitly rather than changing
// the default for everyone.

import { runClaudeCli } from "./claude-cli.ts";

/** Cheap by default — these are one-line summarisation and classification jobs. */
export const DEFAULT_MODEL = process.env.LFG_AUTOPILOT_MODEL ?? "haiku";
const DEFAULT_TIMEOUT_MS = Number(process.env.LFG_AUTOPILOT_LLM_TIMEOUT_MS ?? 120_000);

export type AskOptions = {
  prompt: string;
  /** Replaces the CLI's default system prompt. Keep it short and behavioural. */
  system?: string;
  /** Defaults to `DEFAULT_MODEL`. */
  model?: string;
  timeoutMs?: number;
  /**
   * Extra attempts after a failure. Defaults to 1: a background job that does
   * nothing for a full interval because of one transient blip is a real cost,
   * and these calls are idempotent reads.
   */
  retries?: number;
  /** Task name, for the log line. */
  label?: string;
  log?: (line: string) => void;
};

// One at a time. See (3) above — the guard is against a task fanning out, not
// against the tick, which already runs tasks sequentially.
let chain: Promise<unknown> = Promise.resolve();
function serialize<T>(fn: () => Promise<T>): Promise<T> {
  const run = chain.catch(() => {}).then(fn);
  chain = run.catch(() => {});
  return run;
}

/**
 * The transport. Swappable only so the retry and serialization guarantees above
 * can be tested without spawning a real subprocess — production always uses
 * `runClaudeCli`. Follows this repo's existing `*ForTests` seam convention.
 */
export type Transport = typeof runClaudeCli;
let transport: Transport = runClaudeCli;

export function setTransportForTests(next: Transport | null): void {
  transport = next ?? runClaudeCli;
}

/** Ask a question, get the assistant's text. */
export function ask(opts: AskOptions): Promise<string> {
  const log = opts.log ?? (() => {});
  const label = opts.label ? `${opts.label}: ` : "";
  const model = opts.model ?? DEFAULT_MODEL;
  const attempts = Math.max(1, (opts.retries ?? 1) + 1);

  return serialize(async () => {
    let lastErr: unknown;
    for (let i = 1; i <= attempts; i++) {
      try {
        return await transport({
          prompt: opts.prompt,
          system: opts.system,
          model,
          timeoutMs: opts.timeoutMs ?? DEFAULT_TIMEOUT_MS,
          log: (l) => log(`${label}${l}`),
        });
      } catch (e) {
        lastErr = e;
        if (i < attempts) {
          log(
            `${label}[claude] attempt ${i}/${attempts} failed (${
              e instanceof Error ? e.message : e
            }) — retrying`,
          );
        }
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
  });
}

/**
 * Pull a JSON value out of model output.
 *
 * Three rungs, cheapest first: the whole string, a fenced block, then the widest
 * brace/bracket span. Returns null rather than throwing — for these tasks
 * unparseable output means "no answer this round", which is a normal outcome, not
 * an error worth aborting a tick over.
 */
export function extractJson(text: string): unknown {
  const tryParse = (s: string): { ok: true; value: unknown } | { ok: false } => {
    try {
      return { ok: true, value: JSON.parse(s) };
    } catch {
      return { ok: false };
    }
  };

  const whole = tryParse(text.trim());
  if (whole.ok) return whole.value;

  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) {
    const fenced = tryParse(fence[1].trim());
    if (fenced.ok) return fenced.value;
  }

  // Widest span for each opener; whichever starts earlier in the text wins, so a
  // reply that leads with prose containing braces can't shadow the real payload.
  const spans: Array<[number, string]> = [];
  for (const [open, close] of [
    ["[", "]"],
    ["{", "}"],
  ] as const) {
    const start = text.indexOf(open);
    const end = text.lastIndexOf(close);
    if (start !== -1 && end > start) spans.push([start, text.slice(start, end + 1)]);
  }
  spans.sort((a, b) => a[0] - b[0]);
  for (const [, span] of spans) {
    const parsed = tryParse(span);
    if (parsed.ok) return parsed.value;
  }
  return null;
}

export type AskJsonOptions<T> = AskOptions & {
  /**
   * Turn the parsed JSON into the shape the caller wants, or null to reject it.
   * Validation is the CALLER's job — this service cannot know that a returned id
   * was never asked about, and applying an unvalidated model answer to real
   * state is how a hallucinated key ends up renaming the wrong thing.
   */
  validate: (value: unknown) => T | null;
};

/**
 * Ask for JSON and get it validated. Returns null when the model produced
 * nothing usable — callers treat that as "no answer", never as an error.
 */
export async function askJson<T>(opts: AskJsonOptions<T>): Promise<T | null> {
  const log = opts.log ?? (() => {});
  const label = opts.label ? `${opts.label}: ` : "";
  const text = await ask(opts);
  const value = extractJson(text);
  if (value === null) {
    log(`${label}[claude] no JSON in reply (${text.length} chars) — treating as no answer`);
    return null;
  }
  const validated = opts.validate(value);
  if (validated === null) {
    log(`${label}[claude] reply failed validation — treating as no answer`);
    return null;
  }
  return validated;
}
