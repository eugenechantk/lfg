// Is the double-count race reachable through the public entry point every consumer
// uses (sessionTurnState), and how wide is the window? Two consumers consult the
// same mark; the second starts `delay` ms after the first. After they finish, one
// more quiet tick. Correct: idle (only metadata was written after the stop).
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync } from "node:fs";
import { join } from "node:path";

const root = mkdtempSync(join(import.meta.dir, "audit-race-"));
process.env.LFG_AGENT_STATE_DIR = join(root, "agent-state");
mkdirSync(process.env.LFG_AGENT_STATE_DIR, { recursive: true });
const { sessionTurnState } = await import("/Users/eugenechan/dev/personal/lfg/src/session-state.ts");
const { noteConfirmedInterrupt, __resetInterruptMarks } = await import("/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts");
const { __resetTurnStateCache } = await import("/Users/eugenechan/dev/personal/lfg/src/turn-state.ts");

const J = (x: unknown) => JSON.stringify(x);
const prompt = { type: "user", message: { role: "user", content: "cut a new build" } };
const meta = [{ type: "ai-title", aiTitle: "Cut a build" }, { type: "last-prompt", lastPrompt: "cut a new build" }];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let n = 0;

async function trial(delayMs: number | "sequential"): Promise<string> {
  __resetInterruptMarks();
  __resetTurnStateCache();
  const sid = `${String(n++).padStart(8, "0")}-0000-4000-8000-000000000000`;
  const tp = join(root, `${sid}.jsonl`);
  writeFileSync(tp, J(prompt) + "\n");
  noteConfirmedInterrupt(sid, tp);
  appendFileSync(tp, meta.map(J).join("\n") + "\n");
  const call = () => sessionTurnState({ sessionId: sid, transcriptPath: tp });
  if (delayMs === "sequential") {
    await call();
    await call();
  } else {
    await Promise.all([call(), (async () => { if (delayMs > 0) await sleep(delayMs); else if (delayMs === 0) await null; return call(); })()]);
  }
  return (await call())?.state ?? "null";
}

for (const d of ["sequential", -1, 0, 1, 2, 5] as const) {
  const res: Record<string, number> = {};
  for (let i = 0; i < 20; i++) {
    const s = await trial(d);
    res[s] = (res[s] ?? 0) + 1;
  }
  console.log(`second consumer start offset=${d === -1 ? "same tick" : d === 0 ? "next microtask" : d === "sequential" ? "after first finished" : d + "ms"}  → quiet-tick verdicts over 20 trials: ${J(res)}`);
}
process.exit(0);
