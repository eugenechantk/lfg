import fs from "fs";
const F = "/Users/eugenechan/.claude/projects/-Users-eugenechan-dev-personal-lfg/3f1ec26c-c3db-4a9e-b244-23186f306d2e.jsonl";
const OUT = "/Users/eugenechan/dev/personal/lfg/.claude/brainstorm/watch-log.txt";
const MARKER = "ZZMARKER_PREQ_TEXT";
fs.writeFileSync(OUT, "");
let lastSize = -1;
setInterval(() => {
  let size;
  try { size = fs.statSync(F).size; } catch { return; }
  if (size === lastSize) return;
  lastSize = size;
  const lines = fs.readFileSync(F, "utf8").split("\n").filter(Boolean);
  const tail = lines.slice(-8);
  const summ = tail.map((l) => {
    let x; try { x = JSON.parse(l); } catch { return "?"; }
    const c = x.message?.content;
    let d;
    if (typeof c === "string") d = "STR";
    else if (Array.isArray(c)) d = c.map(b => b.type === "tool_use" ? `tu(${b.name})` : b.type === "text" ? (String(b.text||"").includes(MARKER) ? "TEXT*MARKER*" : "text") : b.type).join("+");
    else d = "-";
    return `${x.type}:${d}`;
  }).join(" || ");
  const hasMarker = lines.some(l => l.includes(MARKER));
  const hasAUQ = lines.some(l => { try { const x=JSON.parse(l); return Array.isArray(x.message?.content)&&x.message.content.some(b=>b.type==="tool_use"&&b.name==="AskUserQuestion"); } catch { return false; } });
  fs.appendFileSync(OUT, `t=${Date.now()} size=${size} marker=${hasMarker?1:0} auq=${hasAUQ?1:0} tail=[${summ}]\n`);
}, 250);
