import {
  LOG_PATH,
  STATE_PATH,
  STEPS,
  TICK_MS,
  findStep,
  readState,
  runTick,
} from "../autopilot/tick.ts";

const HELP = `lfg autopilot — periodic maintenance over lfg's own state

The autopilot runs every ${Math.round(TICK_MS / 60_000)} min inside 'lfg serve' and
performs every step below, in order, on each run. Steps are pieces of a run, not
separately scheduled jobs — each one decides for itself whether it has work.

Usage:
  lfg autopilot list               Show the steps and how each one last went
  lfg autopilot run                Run every step now
  lfg autopilot run --dry          Show what a run would do, change nothing
  lfg autopilot run <step>         Run one step now
  lfg autopilot run <step> --dry   Dry-run one step

State: ${STATE_PATH}
Log:   ${LOG_PATH}

Env:
  LFG_AUTOPILOT=0              Disable the in-serve loop entirely
  LFG_AUTOPILOT_TICK_MS        How often the autopilot runs (default 600000)
  LFG_AUTOPILOT_MODEL          Model for LLM-backed steps (default haiku)
  LFG_AUTOPILOT_LLM_TIMEOUT_MS Per-call timeout (default 120000)
  LFG_RETITLE_MAX              Sessions examined per retitle run (default 12)
  LFG_RETITLE_WINDOW_MS        How far back counts as recent (default 7d)
`;

export async function cmdAutopilot(args: string[]) {
  const [sub, ...rest] = args;
  const dryRun = rest.includes("--dry") || rest.includes("--dry-run");
  const log = (line: string) => console.error(line);

  switch (sub) {
    case "list": {
      const state = await readState();
      const now = Date.now();
      console.log(`autopilot runs every ${Math.round(TICK_MS / 60_000)} min; ${STEPS.length} step(s):\n`);
      for (const step of STEPS) {
        const s = state[step.name];
        const last = s ? `${Math.round((now - s.lastRunAt) / 60000)}m ago` : "never";
        const outcome = s?.lastOk === false ? " FAILED" : s?.lastNote ? ` — ${s.lastNote}` : "";
        console.log(`  ${step.name.padEnd(20)} last run: ${last}${outcome}`);
        console.log(`  ${" ".repeat(20)} ${step.description}`);
      }
      return;
    }
    // `tick` kept as an alias for `run`: they were separate when steps had their
    // own schedules and "tick" meant "run whatever is due".
    case "tick":
    case "run": {
      const name = rest.find((a) => !a.startsWith("--"));
      if (name && !findStep(name)) {
        console.error(`unknown step '${name}'. Known: ${STEPS.map((s) => s.name).join(", ")}`);
        process.exit(1);
      }
      const outcomes = await runTick({ dryRun, log, only: name ? [name] : undefined });
      report(outcomes, dryRun);
      return;
    }
    case undefined:
    case "help":
    case "-h":
    case "--help":
      console.log(HELP);
      return;
    default:
      console.error(`Unknown autopilot subcommand: ${sub}\n`);
      console.log(HELP);
      process.exit(1);
  }
}

function report(outcomes: Awaited<ReturnType<typeof runTick>>, dryRun: boolean): void {
  for (const o of outcomes) {
    if (!o.ok) {
      console.log(`${o.step}: FAILED — ${o.error}`);
      continue;
    }
    const r = o.result!;
    console.log(
      `${o.step}: examined ${r.examined}, ${dryRun ? "would change" : "changed"} ${
        dryRun ? (Array.isArray(r.detail) ? r.detail.length : 0) : r.changed
      }${r.note ? ` — ${r.note}` : ""}`,
    );
    if (Array.isArray(r.detail)) {
      for (const d of r.detail as { id: string; from: string; to: string }[]) {
        console.log(`  ${d.id.slice(0, 8)}  "${d.from}"\n            → "${d.to}"`);
      }
    }
  }
}
