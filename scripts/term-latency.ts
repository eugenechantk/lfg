#!/usr/bin/env bun
// Keystroke → echo latency for /api/term, measured on the same websocket path
// the iOS terminal uses.
//
//   bun scripts/term-latency.ts                              # http://127.0.0.1:8766
//   bun scripts/term-latency.ts https://lfg-pro.eugenechantk.me
//
// Remote hosts get the Access service token from
// ~/.cloudflared/lfg-access-service-token.private.json. Each sample types one
// marker character into `cat` (so the pty echoes it straight back) and times
// until that character shows up in the output stream. Prints p50/p90/p99/max.

const base = (process.argv[2] ?? "http://127.0.0.1:8766").replace(/\/+$/, "");
const samples = Number(process.argv[3] ?? 60);
const wsURL = `${base.replace(/^http/, "ws")}/api/term?session=latency-probe&cols=80&rows=24`;

const headers: Record<string, string> = {};
if (!/^https?:\/\/(127\.0\.0\.1|localhost)/.test(base)) {
  const t = JSON.parse(await Bun.file(`${process.env.HOME}/.cloudflared/lfg-access-service-token.private.json`).text());
  headers["CF-Access-Client-Id"] = t.clientID;
  headers["CF-Access-Client-Secret"] = t.clientSecret;
}

const ws = new WebSocket(wsURL, { headers } as unknown as string[]);
ws.binaryType = "arraybuffer";
const dec = new TextDecoder();
let buffer = "";
let waiter: { ch: string; resolve: () => void } | null = null;

ws.onmessage = (e) => {
  buffer += typeof e.data === "string" ? e.data : dec.decode(e.data as ArrayBuffer);
  if (waiter && buffer.includes(waiter.ch)) {
    const w = waiter;
    waiter = null;
    buffer = "";
    w.resolve();
  }
  if (buffer.length > 65536) buffer = buffer.slice(-4096);
};

const send = (s: string) => ws.send(new TextEncoder().encode(s));
const opened = new Promise<void>((resolve, reject) => {
  ws.onopen = () => resolve();
  ws.onerror = () => reject(new Error(`websocket failed: ${wsURL}`));
});
const connectStart = performance.now();
await opened;
const connectMs = performance.now() - connectStart;

// A quiet foreground reader: `cat` echoes each keystroke via the tty line
// discipline without any shell prompt redraw noise.
await Bun.sleep(1500);
send("clear; stty -icanon; cat\r");
await Bun.sleep(1500);
buffer = "";

const marks = "abcdefghijklmnopqrstuvwxyz";
const rtts: number[] = [];
for (let i = 0; i < samples; i++) {
  const ch = marks[i % marks.length]!;
  const t0 = performance.now();
  const got = await Promise.race([
    new Promise<boolean>((resolve) => { waiter = { ch, resolve: () => resolve(true) }; send(ch); }),
    Bun.sleep(3000).then(() => false),
  ]);
  if (!got) { waiter = null; console.error(`sample ${i}: timed out`); continue; }
  rtts.push(performance.now() - t0);
  await Bun.sleep(60);
}

send("\x03"); // ^C out of cat
await Bun.sleep(200);
ws.close();
Bun.spawnSync(["tmux", "kill-session", "-t", "lfg-term-latency-probe"]);

rtts.sort((a, b) => a - b);
const pct = (p: number) => rtts[Math.min(rtts.length - 1, Math.floor((p / 100) * rtts.length))]!;
const fmt = (n: number) => `${n.toFixed(1)}ms`;
console.log(JSON.stringify({
  target: base,
  connect: fmt(connectMs),
  samples: rtts.length,
  p50: fmt(pct(50)),
  p90: fmt(pct(90)),
  p99: fmt(pct(99)),
  max: fmt(rtts.at(-1) ?? 0),
}));
process.exit(rtts.length === samples ? 0 : 1);
