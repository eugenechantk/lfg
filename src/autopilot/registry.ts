// What an autopilot STEP is, and the record of how each one last went.
//
// The autopilot is the thing that runs on a schedule. A step is one piece of
// work inside a run — not an independently scheduled job. So there is exactly
// one cadence in this system (`TICK_MS` in `tick.ts`), and every step runs on
// every tick, in order.
//
// An earlier version gave each step its own `intervalMs` and ran only the "due"
// ones. That was two schedules for one loop: the tick's, and each step's, with
// the real cadence being whatever the two quantised to. It also put the rate
// limit in the wrong place. A step already knows better than any timer whether
// there is work — `retitle-sessions` keeps a per-session checkpoint and skips
// anything whose transcript hasn't grown — and a step with nothing to do returns
// in milliseconds without calling a model. That self-gating IS the rate limit;
// an interval on top of it only delays useful work.
//
// The contract a step must honour, because the tick runs it unconditionally:
//   - cheap when there is nothing to do (no model call on an empty run)
//   - idempotent (running twice in a row changes nothing the second time)
//   - honest in its TaskResult, since that is what the log and CLI report
//
// Everything here is pure; the loop that drives it lives in `tick.ts`.

export type TaskContext = {
  /** ms epoch, passed in rather than read, so runs are reproducible in tests. */
  now: number;
  log: (line: string) => void;
  /** Compute and report, change nothing. */
  dryRun: boolean;
};

export type TaskResult = {
  /** How many items the step looked at. */
  examined: number;
  /** How many it actually changed (always 0 on a dry run). */
  changed: number;
  /** One line for the log; keep it short. */
  note?: string;
  /** Free-form detail for `--dry` output. Never persisted. */
  detail?: unknown;
};

export type AutopilotStep = {
  /** Stable id — it keys the persisted state and names the step in the CLI. */
  name: string;
  description: string;
  run: (ctx: TaskContext) => Promise<TaskResult>;
};

export type StepState = {
  lastRunAt: number;
  lastOk?: boolean;
  lastNote?: string;
  lastChanged?: number;
};

export type AutopilotState = Record<string, StepState>;

/** Lenient read: a corrupt state file costs a bit of history, never a run. */
export function parseAutopilotState(raw: unknown): AutopilotState {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: AutopilotState = {};
  for (const [name, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!name || !value || typeof value !== "object") continue;
    const v = value as Partial<StepState>;
    if (typeof v.lastRunAt !== "number" || !Number.isFinite(v.lastRunAt)) continue;
    out[name] = {
      lastRunAt: v.lastRunAt,
      ...(typeof v.lastOk === "boolean" ? { lastOk: v.lastOk } : {}),
      ...(typeof v.lastNote === "string" ? { lastNote: v.lastNote } : {}),
      ...(typeof v.lastChanged === "number" && Number.isFinite(v.lastChanged)
        ? { lastChanged: v.lastChanged }
        : {}),
    };
  }
  return out;
}

/** Merge one step's outcome into the state map (pure; the tick persists it). */
export function recordRun(
  state: AutopilotState,
  name: string,
  now: number,
  outcome: { ok: boolean; note?: string; changed?: number },
): AutopilotState {
  return {
    ...state,
    [name]: {
      lastRunAt: now,
      lastOk: outcome.ok,
      ...(outcome.note ? { lastNote: outcome.note.slice(0, 200) } : {}),
      ...(outcome.changed !== undefined ? { lastChanged: outcome.changed } : {}),
    },
  };
}
