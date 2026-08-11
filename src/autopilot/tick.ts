// The autopilot loop. It wakes every TICK_MS and performs every step, in order.
//
// ONE cadence for the whole system. Steps are pieces of a run, not independently
// scheduled jobs — a step decides for itself whether there is work (see
// `registry.ts`), which is a better rate limit than a timer because it responds
// to the actual state instead of to the clock.
//
// Runs in-process inside `lfg serve`, next to `startAutoScheduler`. It is NOT a
// launchd daemon (which is how gbrain does it) for one concrete reason: the
// state these steps mutate — `~/.lfg/session-titles.json` and friends — is
// already owned by the serve process, and a second writer of those files is a
// lost-update bug waiting to happen. The `lfg autopilot` CLI exists for manual
// and dry runs and shares this exact code path.
//
// Two guards, both earned:
//   - re-entrancy: a run that outlasts TICK_MS must not stack on the next one.
//   - a throwing step does not abort the run — the remaining steps still go, and
//     the failure is recorded and logged. A step that fails persistently retries
//     on every tick, which is what you want from a maintenance loop; the JSONL
//     log is what makes that visible rather than silent.

import { mkdir } from "node:fs/promises";
import { join } from "node:path";
import { PATHS } from "../config.ts";
import {
  parseAutopilotState,
  recordRun,
  type AutopilotState,
  type AutopilotStep,
  type TaskResult,
} from "./registry.ts";
import { retitleStep } from "./retitle.ts";

/** The autopilot's one and only cadence. Every step runs on every tick. */
export const TICK_MS = Number(process.env.LFG_AUTOPILOT_TICK_MS ?? 10 * 60 * 1000);

export const STATE_PATH = join(PATHS.data, "autopilot-state.json");
export const LOG_PATH = join(PATHS.data, "autopilot.log");

/** Every step the autopilot performs, in run order. */
export const STEPS: AutopilotStep[] = [retitleStep];

export function findStep(name: string): AutopilotStep | undefined {
  return STEPS.find((s) => s.name === name);
}

export async function readState(): Promise<AutopilotState> {
  try {
    const f = Bun.file(STATE_PATH);
    if (!(await f.exists())) return {};
    return parseAutopilotState(await f.json());
  } catch {
    return {};
  }
}

async function writeState(state: AutopilotState): Promise<void> {
  await mkdir(PATHS.data, { recursive: true });
  await Bun.write(STATE_PATH, JSON.stringify(state, null, 2));
}

/**
 * One JSON line per event, appended. Same house pattern as `~/.lfg/sendq.log`
 * and `~/.lfg/liveactivity.log`: when a background job silently does nothing,
 * the only thing that distinguishes "nothing to do" from "broken" is a trace
 * that logs the uneventful runs too.
 */
export async function appendLog(row: Record<string, unknown>): Promise<void> {
  try {
    await mkdir(PATHS.data, { recursive: true });
    const line = JSON.stringify({ at: new Date().toISOString(), ...row }) + "\n";
    const f = Bun.file(LOG_PATH);
    const prev = (await f.exists()) ? await f.text() : "";
    await Bun.write(LOG_PATH, prev + line);
  } catch {
    // Logging must never take the tick down with it.
  }
}

export type TickOptions = {
  now?: number;
  dryRun?: boolean;
  log?: (line: string) => void;
  /** Run only these steps instead of all of them. */
  only?: string[];
};

export type TickOutcome = {
  step: string;
  ok: boolean;
  result?: TaskResult;
  error?: string;
};

/** Run every step once, in order. Returns one outcome per step. */
export async function runTick(opts: TickOptions = {}): Promise<TickOutcome[]> {
  const now = opts.now ?? Date.now();
  const dryRun = opts.dryRun ?? false;
  const log = opts.log ?? (() => {});
  const state = await readState();

  const selected = opts.only?.length
    ? STEPS.filter((s) => opts.only!.includes(s.name))
    : STEPS;

  if (!selected.length) return [];

  const outcomes: TickOutcome[] = [];
  let next = state;
  for (const step of selected) {
    log(`[autopilot] running ${step.name}${dryRun ? " (dry)" : ""}`);
    const started = Date.now();
    try {
      const result = await step.run({ now, log, dryRun });
      const ms = Date.now() - started;
      outcomes.push({ step: step.name, ok: true, result });
      log(
        `[autopilot] ${step.name}: examined ${result.examined}, changed ${result.changed}` +
          (result.note ? ` — ${result.note}` : ""),
      );
      await appendLog({
        step: step.name,
        ok: true,
        dryRun,
        ms,
        examined: result.examined,
        changed: result.changed,
        note: result.note,
      });
      // A dry run must not move the schedule — otherwise inspecting what the
      // autopilot *would* do silently cancels the run that would have done it.
      if (!dryRun) {
        next = recordRun(next, step.name, now, {
          ok: true,
          note: result.note,
          changed: result.changed,
        });
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      outcomes.push({ step: step.name, ok: false, error: msg });
      log(`[autopilot] ${step.name} FAILED: ${msg}`);
      await appendLog({ step: step.name, ok: false, dryRun, ms: Date.now() - started, error: msg });
      if (!dryRun) next = recordRun(next, step.name, now, { ok: false, note: msg });
    }
  }
  if (!dryRun) await writeState(next).catch(() => {});
  return outcomes;
}

let timer: ReturnType<typeof setInterval> | null = null;
let ticking = false;

export function startAutopilot(onLog: (line: string) => void = () => {}): void {
  if (timer) return;
  if (process.env.LFG_AUTOPILOT === "0") {
    onLog("[autopilot] disabled (LFG_AUTOPILOT=0)");
    return;
  }

  const tick = async () => {
    if (ticking) return; // a slow LLM batch can outlast the interval
    ticking = true;
    try {
      await runTick({ log: onLog });
    } catch (e) {
      onLog(`[autopilot] tick failed: ${e instanceof Error ? e.message : e}`);
    } finally {
      ticking = false;
    }
  };

  timer = setInterval(() => void tick(), TICK_MS);
  // One minute in rather than at boot: `lfg serve` restarts are frequent (no hot
  // reload), and firing instantly on every restart would stack runs during a
  // restart storm. A boot-time run is otherwise harmless — steps self-gate, so
  // one that just ran finds nothing to do and returns without calling a model.
  setTimeout(() => void tick(), 60_000);
  onLog(
    `[autopilot] started (every ${Math.round(TICK_MS / 60_000)} min, steps: ${STEPS.map((s) => s.name).join(", ")})`,
  );
}
