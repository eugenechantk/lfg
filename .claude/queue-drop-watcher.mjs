// Queue-drop watcher — standalone, no server restart needed.
// Polls every session's outbound queue and logs every per-message status
// transition. Flags the smoking gun: a message that leaves a live state
// (pending/sending/queued) and vanishes WITHOUT ever reaching "delivered"
// (i.e. a genuine drop), or lands on "failed". On a suspicious transition it
// snapshots the tmux pane so we can see what the TUI was doing.
//
// Run:  bun .claude/queue-drop-watcher.mjs   (or: node ...)
// Log:  .claude/queue-drop-watch.log
import { appendFileSync, writeFileSync } from "fs";
import { execSync } from "child_process";

const BASE = "http://localhost:8766";
const OUT = "/Users/eugenechan/dev/personal/lfg/.claude/queue-drop-watch.log";
const POLL_MS = 1200;

// key = `${sid}:${msgId}` -> { status, text, tmux, lastDelivered:boolean }
const seen = new Map();
writeFileSync(OUT, `# queue-drop-watch started ${new Date().toISOString()}\n`);
const log = (s) => { appendFileSync(OUT, s + "\n"); console.log(s); };

const pane = (tmux) => {
  try { return execSync(`tmux capture-pane -p -t ${tmux} 2>/dev/null | tail -12`, { encoding: "utf8" }); }
  catch { return "(pane unavailable)"; }
};

async function tick() {
  let sessions;
  try {
    sessions = (await (await fetch(`${BASE}/api/sessions`)).json()).sessions || [];
  } catch { return; }
  const live = new Map(); // sid -> tmuxTarget
  for (const s of sessions) if (s.sessionId) live.set(s.sessionId, s.tmuxTarget);

  const present = new Set();
  for (const [sid, tmux] of live) {
    let q;
    try { q = (await (await fetch(`${BASE}/api/sessions/${sid}/queue`)).json()).queue || []; }
    catch { continue; }
    for (const m of q) {
      const key = `${sid}:${m.id}`;
      present.add(key);
      const prev = seen.get(key);
      if (!prev) {
        seen.set(key, { status: m.status, text: m.text, tmux, delivered: m.status === "delivered" });
        log(`t=${new Date().toISOString()} NEW ${sid.slice(0,8)} ${m.status} | ${JSON.stringify(m.text.slice(0,60))}`);
      } else if (prev.status !== m.status) {
        prev.delivered = prev.delivered || m.status === "delivered";
        log(`t=${new Date().toISOString()} MOVE ${sid.slice(0,8)} ${prev.status}→${m.status} attempts=${m.attempts} redel=${m.redeliveries ?? 0}${m.error ? " err=" + JSON.stringify(m.error) : ""} | ${JSON.stringify(m.text.slice(0,50))}`);
        if (m.status === "failed") log(`  !! FAILED pane:\n${pane(tmux)}`);
        prev.status = m.status;
      }
    }
  }
  // Detect disappearances: a key we were tracking is gone from the queue.
  for (const [key, info] of seen) {
    if (present.has(key)) continue;
    const sid = key.split(":")[0];
    if (!info.delivered && (info.status === "pending" || info.status === "sending" || info.status === "queued")) {
      log(`t=${new Date().toISOString()} *** DROP *** ${sid.slice(0,8)} vanished from queue while status=${info.status}, NEVER delivered | ${JSON.stringify(info.text.slice(0,60))}`);
      log(`  pane:\n${pane(info.tmux)}`);
    }
    seen.delete(key);
  }
}

log(`polling ${BASE} every ${POLL_MS}ms — watching for queued messages that drop before delivery`);
setInterval(tick, POLL_MS);
tick();
