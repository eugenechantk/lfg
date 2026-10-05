// R1 window, lower bound: how long a confirming capture takes from spawn to resolved
// promise in an otherwise idle Bun process. The pane snapshot is taken inside this
// interval, so snapshot→note is at most this plus event-loop delay in the real server.
import { capturePaneAsync, isBusy } from "/Users/eugenechan/dev/personal/lfg/src/tmux.ts";
const name = `audit-cap-${process.pid}`;
Bun.spawnSync(["tmux", "new-session", "-d", "-s", name, "-x", "120", "-y", "50", "sleep", "60"]);
const ms: number[] = [];
try {
  for (let i = 0; i < 60; i++) {
    const t0 = performance.now();
    const p = await capturePaneAsync(`${name}:0.0`);
    isBusy(p ?? "");
    ms.push(performance.now() - t0);
  }
} finally { Bun.spawnSync(["tmux", "kill-session", "-t", name]); }
ms.sort((a, b) => a - b);
const q = (f: number) => ms[Math.min(ms.length - 1, Math.floor(f * ms.length))].toFixed(1);
console.log(`capturePaneAsync+isBusy over ${ms.length} runs: p50 ${q(0.5)}ms p95 ${q(0.95)}ms max ${q(1)}ms`);
process.exit(0);
