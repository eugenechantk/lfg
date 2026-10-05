import { mkdtempSync, mkdirSync, writeFileSync, truncateSync, statSync } from "node:fs";
import { join } from "node:path";
const root = mkdtempSync(join(import.meta.dir, "audit-shrink-"));
process.env.LFG_AGENT_STATE_DIR = join(root, "agent-state");
mkdirSync(process.env.LFG_AGENT_STATE_DIR, { recursive: true });
const { sessionTurnState } = await import("/Users/eugenechan/dev/personal/lfg/src/session-state.ts");
const { noteConfirmedInterrupt } = await import("/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts");
const sid = "00000099-0000-4000-8000-000000000000", tp = join(root, sid + ".jsonl");
const p = (t: string) => JSON.stringify({ type: "user", message: { role: "user", content: t } });
writeFileSync(tp, p("a") + "\n" + p("b".repeat(200)) + "\n");
noteConfirmedInterrupt(sid, tp);
console.log("E0 before shrink:", JSON.stringify(await sessionTurnState({ sessionId: sid, transcriptPath: tp })));
truncateSync(tp, p("a").length + 1); // drop the last line only: transcript shrinks, nothing re-grows
console.log("E0 after shrink only (expect running, fail-safe):", JSON.stringify(await sessionTurnState({ sessionId: sid, transcriptPath: tp })));
process.exit(0);
