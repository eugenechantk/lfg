// SC5 probe: old (HEAD) vs new sessionTurnState on the REAL lfg-e4d53c transcript.
// Prints verdicts, sizes and record TYPES only — never record content.
import { sessionTurnState as oldSTS } from "./audit-old-session-state.ts";
import { sessionTurnState as newSTS } from "/Users/eugenechan/dev/personal/lfg/src/session-state.ts";
import { hookState } from "/Users/eugenechan/dev/personal/lfg/src/hook-state.ts";
import { noteConfirmedInterrupt, __resetInterruptMarks } from "/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts";
import { classifyTurnLine, __resetTurnStateCache } from "/Users/eugenechan/dev/personal/lfg/src/turn-state.ts";
import { statSync, readFileSync } from "node:fs";

const sid = "b08adb88-1926-4a22-8ffd-874b7a687884";
const tp = `${process.env.HOME}/.claude/projects/-Users-eugenechan-dev-personal-lfg/${sid}.jsonl`;
const st = statSync(tp);
console.log("transcript size", st.size, "mtime", new Date(st.mtimeMs).toISOString());

// Types of the last 8 records + which one is the newest decisive (type/classification only).
const lines = readFileSync(tp, "utf8").split("\n").filter(Boolean);
const tail = lines.slice(-8).map((l) => {
  try {
    const x = JSON.parse(l);
    return `${x.type}${x.subtype ? "/" + x.subtype : ""}${x.isMeta ? "(meta)" : ""} -> ${classifyTurnLine(l)}`;
  } catch {
    return "unparseable";
  }
});
console.log("last 8 record types (oldest→newest):", JSON.stringify(tail));
console.log("any assistant record after last user row?", (() => {
  let lastUser = -1, lastAsst = -1;
  lines.forEach((l, i) => { try { const x = JSON.parse(l); if (x.type === "user" && !x.isMeta) lastUser = i; if (x.type === "assistant") lastAsst = i; } catch {} });
  return lastAsst > lastUser;
})());
console.log("any [Request interrupted marker in file?", lines.some((l) => l.includes("[Request interrupted")));

const h = await hookState(sid, tp);
console.log("hookState:", JSON.stringify(h ? { state: h.state, at: h.at } : null));

// The moment of the first Stop (ops.log): 14:21:31Z. Evaluate 4s later, inside STALL_MS.
const stopAt = Date.parse("2026-10-04T14:21:31.300Z");
const now = Date.parse("2026-10-04T14:21:35.000Z");
__resetInterruptMarks();
__resetTurnStateCache();
console.log("OLD (HEAD) code @14:21:35Z:          ", JSON.stringify(await oldSTS({ sessionId: sid, transcriptPath: tp, now })));
console.log("NEW code, no mark @14:21:35Z:        ", JSON.stringify(await newSTS({ sessionId: sid, transcriptPath: tp, now })));
noteConfirmedInterrupt(sid, tp, stopAt);
console.log("NEW code, mark @14:21:31Z, eval :35Z:", JSON.stringify(await newSTS({ sessionId: sid, transcriptPath: tp, now })));
console.log("NEW code, mark, second tick:         ", JSON.stringify(await newSTS({ sessionId: sid, transcriptPath: tp, now: now + 1000 })));
__resetInterruptMarks();
console.log("OLD (HEAD) code @real now (", new Date().toISOString(), "):", JSON.stringify(await oldSTS({ sessionId: sid, transcriptPath: tp })));
