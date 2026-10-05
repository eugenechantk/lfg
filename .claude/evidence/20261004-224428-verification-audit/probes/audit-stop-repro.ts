// Auditor's endpoint-faithful real-seam repro. Differences from the implementer's:
//  - proves the pane was BUSY before the stop (discriminating case)
//  - records the mark IMMEDIATELY after interruptAndConfirm, exactly like serve.ts,
//    so post-stop metadata lands AFTER the size snapshot
//  - compares against the OLD (HEAD) sessionTurnState at every tick
//  - logs the record types appended after the snapshot (types only)
//  - after resubmitting, checks the new turn reads running and STAYS running
import { interruptAndConfirm } from "/Users/eugenechan/dev/personal/lfg/src/closing.ts";
import { tmuxInterrupt, capturePaneAsync, isBusy } from "/Users/eugenechan/dev/personal/lfg/src/tmux.ts";
import { sessionTurnState } from "/Users/eugenechan/dev/personal/lfg/src/session-state.ts";
import { sessionTurnState as oldSTS } from "./audit-old-session-state.ts";
import { noteConfirmedInterrupt } from "/Users/eugenechan/dev/personal/lfg/src/interrupt-marks.ts";
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const cwd = process.argv[2];
const paneOut = process.argv[3];
const name = `stoprepro-audit-${process.pid}`;
const projDir = join(process.env.HOME!, ".claude/projects", cwd.replace(/[^A-Za-z0-9]/g, "-"));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const log = (...a: unknown[]) => console.log(new Date().toISOString().slice(11, 23), ...a);
const J = JSON.stringify;
const before = new Set((() => { try { return readdirSync(projDir); } catch { return []; } })());
Bun.spawnSync(["tmux", "new-session", "-d", "-s", name, "-x", "120", "-y", "50", "-c", cwd,
  "/opt/homebrew/bin/claude", "--dangerously-skip-permissions", "--",
  "Think very carefully, step by step, about the history of the number zero, then write a long essay about it."]);
const target = `${name}:0.0`;
const typesAfter = (tp: string, from: number) =>
  readFileSync(tp).subarray(from).toString("utf8").split("\n").filter(Boolean).map((l) => {
    try { const x = JSON.parse(l); return x.type + (x.subtype ? "/" + x.subtype : ""); } catch { return "fragment"; }
  });
let tp: string | null = null;
try {
  for (let i = 0; i < 300 && !tp; i++) {
    await sleep(100);
    try {
      const f = readdirSync(projDir).find((x) => x.endsWith(".jsonl") && !before.has(x));
      if (f) {
        const p = join(projDir, f);
        if (readFileSync(p, "utf8").split("\n").some((l) => l.includes('"type":"user"'))) tp = p;
      }
    } catch {}
  }
  if (!tp) throw new Error("no transcript with a user row after 30s");
  const sid = tp.split("/").pop()!.replace(".jsonl", "");
  log("prompt submitted; sid", sid);
  await sleep(800);
  const paneBefore = (await capturePaneAsync(target)) ?? "";
  log("BEFORE stop: pane busy?", isBusy(paneBefore), "| assistant row?", readFileSync(tp, "utf8").includes('"type":"assistant"'),
    "| old verdict", J(await oldSTS({ sessionId: sid, transcriptPath: tp })));
  const r = await interruptAndConfirm(target, {
    escape: tmuxInterrupt, capture: capturePaneAsync, busy: isBusy,
    wait: (ms) => new Promise((res) => setTimeout(res, ms)),
  });
  if (r.stopped === true) noteConfirmedInterrupt(sid, tp); // same position as serve.ts
  const snap = statSync(tp).size;
  log("interruptAndConfirm:", J(r), "| mark recorded at size", snap);
  for (let t = 1; t <= 8; t++) {
    await sleep(1000);
    const size = statSync(tp).size;
    log(`tick ${t}s: NEW ${J(await sessionTurnState({ sessionId: sid, transcriptPath: tp }))} | OLD ${J(await oldSTS({ sessionId: sid, transcriptPath: tp }))} | +${size - snap}B appended: ${J(typesAfter(tp, snap))}`);
  }
  const paneAfter = (await capturePaneAsync(target)) ?? "";
  writeFileSync(paneOut, paneAfter);
  log("AFTER stop: pane busy?", isBusy(paneAfter), "| assistant row?", readFileSync(tp, "utf8").includes('"type":"assistant"'),
    "| interrupt marker?", readFileSync(tp, "utf8").includes("[Request interrupted"), "| pane saved to", paneOut);
  // New turn: resubmit the rewound prompt from the composer.
  const preResubmit = statSync(tp).size;
  Bun.spawnSync(["tmux", "send-keys", "-t", target, "Enter"]);
  let first: string | null = null;
  for (let i = 0; i < 50; i++) {
    await sleep(200);
    const v = await sessionTurnState({ sessionId: sid, transcriptPath: tp });
    if (v?.state === "running") { first = `${J(v)} after ${(i + 1) * 200}ms`; break; }
  }
  log("after resubmitting:", first ?? "never running within 10s", "| appended types:", J(typesAfter(tp, preResubmit).slice(0, 6)));
  for (let t = 1; t <= 4; t++) {
    await sleep(1000);
    const pane = (await capturePaneAsync(target)) ?? "";
    log(`  new-turn tick ${t}s: NEW ${J(await sessionTurnState({ sessionId: sid, transcriptPath: tp }))} | pane busy? ${isBusy(pane)}`);
  }
  tmuxInterrupt(target); await sleep(500);
} finally {
  Bun.spawnSync(["tmux", "kill-session", "-t", name]);
  log("killed", name);
}
process.exit(0);
