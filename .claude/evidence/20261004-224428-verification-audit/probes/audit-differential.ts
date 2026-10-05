// "No mark → no change": old (HEAD) vs new sessionTurnState over the REAL transcript
// corpus, no marks recorded. Prints counts and mismatching ids/verdicts only.
import { sessionTurnState as oldSTS } from "./audit-old-session-state.ts";
import { sessionTurnState as newSTS } from "/Users/eugenechan/dev/personal/lfg/src/session-state.ts";
import { __resetInterruptMarks } from "/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts";
import { Glob } from "bun";
import { statSync } from "node:fs";

const home = process.env.HOME!;
const files: { tp: string; sid: string; mtime: number }[] = [];
for (const p of new Glob(".claude/projects/*/*.jsonl").scanSync({ cwd: home, absolute: true, dot: true })) {
  try { files.push({ tp: p, sid: p.split("/").pop()!.replace(/\.jsonl$/, ""), mtime: statSync(p).mtimeMs }); } catch {}
}
for (const p of new Glob(".codex/sessions/**/rollout-*.jsonl").scanSync({ cwd: home, absolute: true, dot: true })) {
  const m = p.match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/);
  try { files.push({ tp: p, sid: m ? m[1] : p, mtime: statSync(p).mtimeMs }); } catch {}
}
files.sort((a, b) => b.mtime - a.mtime);
const sample = files.slice(0, Number(process.argv[2] ?? 600));
__resetInterruptMarks();
const tally: Record<string, number> = {};
let compared = 0, mismatches = 0;
const wall = Date.now();
for (const f of sample) {
  // Three clocks per file: real now, just after its last write (no stall), and
  // with sessionId omitted (transcript-only path).
  const cases: [string, { sessionId?: string | null; transcriptPath: string; now: number }][] = [
    ["now", { sessionId: f.sid, transcriptPath: f.tp, now: wall }],
    ["fresh", { sessionId: f.sid, transcriptPath: f.tp, now: f.mtime + 5_000 }],
    ["nosid", { sessionId: null, transcriptPath: f.tp, now: f.mtime + 5_000 }],
  ];
  for (const [label, args] of cases) {
    const a = JSON.stringify(await oldSTS(args));
    const b = JSON.stringify(await newSTS(args));
    compared++;
    tally[`${label} ${b}`] = (tally[`${label} ${b}`] ?? 0) + 1;
    if (a !== b) {
      mismatches++;
      console.log("MISMATCH", label, f.sid, "old", a, "new", b);
    }
  }
}
console.log("transcripts:", sample.length, "of", files.length, "| comparisons:", compared, "| mismatches:", mismatches);
console.log("verdict distribution (new):");
for (const [k, v] of Object.entries(tally).sort()) console.log("  ", v, k);
