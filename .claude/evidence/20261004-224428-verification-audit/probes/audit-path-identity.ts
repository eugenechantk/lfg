// Path identity: the interrupt endpoint marks `sess.transcriptPath` (from listSessions,
// as served by GET /api/sessions); the journal pump and push watcher consult with
// `resolveTranscript(sid)`. A mismatch makes `noDecisiveSince` drop the mark.
// Prints ids, agent and booleans only.
import { resolveTranscript } from "/Users/eugenechan/dev/personal/lfg/src/sessions.ts";

const res = await fetch("http://127.0.0.1:8766/api/sessions");
const body = await res.json();
const rows = (Array.isArray(body) ? body : body.sessions ?? body) as {
  sessionId: string | null; agent: string; transcriptPath: string | null; tmuxTarget: string | null;
}[];
let same = 0, diff = 0;
for (const r of rows) {
  if (!r.sessionId || !r.tmuxTarget) continue; // the endpoint 404s/409s these before marking
  const pumpTp = await resolveTranscript(r.sessionId);
  const ok = pumpTp === r.transcriptPath;
  ok ? same++ : diff++;
  console.log(ok ? "SAME" : "DIFF", r.agent, r.sessionId.slice(0, 8), ok ? "" : JSON.stringify({ endpoint: r.transcriptPath, pump: pumpTp }));
}
console.log(`pane-backed rows: ${same + diff} | same path: ${same} | different: ${diff}`);
process.exit(0);
