// A durable record of every close/interrupt, and what actually happened.
//
// WHY THIS EXISTS. `serve.ts` logged nothing for either endpoint — no request, no
// target, no outcome. So "Stop doesn't work" and "close doesn't work" arrived with
// no evidence attached and each investigation restarted from zero, exactly as the
// send failures did before `data/sendq.log`. Both endpoints could also answer
// `200 {"ok":true}` while doing nothing at all, which made the absence of a log
// the difference between a five-minute diagnosis and a five-hour one.
//
// Append-only, one JSON object per line, best-effort: a logging failure must never
// fail the operation it is describing.

import { appendFile, mkdir, stat, rename } from "node:fs/promises";
import { dirname, join } from "node:path";

/** Rotate at 5 MB, keeping one previous file. Bounded without a cron. */
const MAX_BYTES = 5 * 1024 * 1024;

function logPath(): string {
  return process.env.LFG_OPS_LOG ?? join(process.cwd(), "data", "ops.log");
}

async function rotateIfBig(path: string): Promise<void> {
  try {
    const s = await stat(path);
    if (s.size < MAX_BYTES) return;
    await rename(path, `${path}.1`);
  } catch {
    // Missing file (nothing to rotate) or an un-renameable one — either way the
    // append below is still worth attempting.
  }
}

export type OpsEntry = {
  op: "close" | "interrupt";
  sessionId: string;
  /** `ok` here is the OUTCOME, not the HTTP status — the whole point of the log. */
  ok: boolean;
  ms: number;
  [k: string]: unknown;
};

export async function logOp(entry: OpsEntry): Promise<void> {
  const line = JSON.stringify({ at: new Date().toISOString(), ...entry }) + "\n";
  const path = logPath();
  try {
    await mkdir(dirname(path), { recursive: true });
    await rotateIfBig(path);
    await appendFile(path, line);
  } catch {
    // Best effort by design: never let the log break the op it describes.
  }
}
