// Fixed-code interleavings where concurrent readers see DIFFERENT sizes: reader A
// snapshots size S1, more bytes land, reader B snapshots S2, both resolve in either order.
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync } from "node:fs";
import { join } from "node:path";
const root = mkdtempSync(join(import.meta.dir, "audit-mixed-"));
process.env.LFG_AGENT_STATE_DIR = join(root, "agent-state");
mkdirSync(process.env.LFG_AGENT_STATE_DIR, { recursive: true });
const { sessionTurnState } = await import("/Users/eugenechan/dev/personal/lfg/src/session-state.ts");
const { noteConfirmedInterrupt, interruptStands, __resetInterruptMarks } = await import("/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts");
const { __resetTurnStateCache } = await import("/Users/eugenechan/dev/personal/lfg/src/turn-state.ts");
const J = JSON.stringify;
const prompt = (t = "cut a new build") => ({ type: "user", message: { role: "user", content: t } });
const meta = (p = 0) => ({ type: "ai-title", aiTitle: "Cut" + "x".repeat(p) });
let n = 0;
const fresh = () => {
  __resetInterruptMarks(); __resetTurnStateCache();
  const sid = `${String(n++).padStart(8, "0")}-0000-4000-8000-000000000000`;
  const tp = join(root, `${sid}.jsonl`);
  writeFileSync(tp, J(prompt()) + "\n");
  noteConfirmedInterrupt(sid, tp);
  return { sid, tp };
};
const app = (tp: string, ...l: unknown[]) => appendFileSync(tp, l.map(J).join("\n") + "\n");
const v = async (sid: string, tp: string) => (await sessionTurnState({ sessionId: sid, transcriptPath: tp }))?.state;
const tally = (o: Record<string, number>, k: string) => (o[k] = (o[k] ?? 0) + 1);

// M1: A sees metadata only; B also sees MORE metadata. Then quiet tick (expect idle),
//     then a new prompt (expect running).
// M2: A sees metadata only; B sees metadata + a NEW PROMPT. B must win: running now
//     and on the next tick, regardless of completion order.
// M3: M1 but B started first (larger range resolves first, smaller second) — max() must not regress.
const res: Record<string, Record<string, number>> = { M1: {}, M2: {}, M3: {} };
for (let i = 0; i < 20; i++) {
  { const { sid, tp } = fresh(); app(tp, meta(300)); const a = interruptStands(sid, tp, null); app(tp, meta(900)); const b = interruptStands(sid, tp, null);
    const r = await Promise.all([a, b]); tally(res.M1, `stands=${r} quiet=${await v(sid, tp)} afterPrompt=${(app(tp, prompt("next")), await v(sid, tp))}`); }
  { const { sid, tp } = fresh(); app(tp, meta(300)); const a = interruptStands(sid, tp, null); app(tp, prompt("next")); const b = interruptStands(sid, tp, null);
    const r = await Promise.all([a, b]); tally(res.M2, `stands=${r} nextTick=${await v(sid, tp)} tick+2=${await v(sid, tp)}`); }
  { const { sid, tp } = fresh(); app(tp, meta(300), meta(900)); const b = interruptStands(sid, tp, null); const a = interruptStands(sid, tp, null);
    const r = await Promise.all([b, a]); tally(res.M3, `stands=${r} quiet=${await v(sid, tp)} afterMeta=${(app(tp, meta(50)), await v(sid, tp))} afterPrompt=${(app(tp, prompt("next")), await v(sid, tp))}`); }
}
console.log("M1 (A:S1 meta, B:S2 more meta)        expect quiet=idle afterPrompt=running:", J(res.M1));
console.log("M2 (A:S1 meta, B:S2 meta+new prompt)  expect B stands=false, nextTick=running:", J(res.M2));
console.log("M3 (both see same larger range)       expect quiet=idle afterMeta=idle afterPrompt=running:", J(res.M3));
process.exit(0);
