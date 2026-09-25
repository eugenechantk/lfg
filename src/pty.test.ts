import { test, expect } from "bun:test";
import { PtyBridge, restoreTermWindowAutoSize, termSessionName } from "./pty.ts";

const dec = new TextDecoder();

function collect(bridge: PtyBridge) {
  let out = "";
  bridge.onData((c) => { out += dec.decode(c); });
  return { get text() { return out; } };
}

async function waitFor(pred: () => boolean, ms = 5000) {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    if (pred()) return true;
    await Bun.sleep(20);
  }
  return pred();
}

test("keystrokes reach the child and its output comes back", async () => {
  const bridge = new PtyBridge(["/bin/sh"], { cols: 80, rows: 24 });
  const out = collect(bridge);
  try {
    bridge.write("echo PTY_$((40+2))\r");
    expect(await waitFor(() => out.text.includes("PTY_42"))).toBe(true);
  } finally {
    bridge.close();
  }
});

// Regression: the FFI bridge set O_NONBLOCK through variadic fcntl, which is a
// silent no-op on arm64 macOS — the drain loop's read() then blocked the one
// event loop the whole server runs on, so timers (and HTTP) stopped.
test("an idle pty never blocks the event loop", async () => {
  const bridge = new PtyBridge(["/bin/sh"], { cols: 80, rows: 24 });
  collect(bridge);
  let ticks = 0;
  const iv = setInterval(() => ticks++, 20);
  try {
    await Bun.sleep(1000);
    expect(ticks).toBeGreaterThan(30);
  } finally {
    clearInterval(iv);
    bridge.close();
  }
});

test("resize reaches the child's window size", async () => {
  const bridge = new PtyBridge(["/bin/sh"], { cols: 80, rows: 24 });
  const out = collect(bridge);
  try {
    bridge.resize(132, 41);
    await Bun.sleep(100);
    bridge.write("stty size\r");
    expect(await waitFor(() => out.text.includes("41 132"))).toBe(true);
  } finally {
    bridge.close();
  }
});

test("child exit fires onExit", async () => {
  const bridge = new PtyBridge(["/bin/sh", "-c", "exit 0"], { cols: 80, rows: 24 });
  let exited = false;
  bridge.onExit(() => { exited = true; });
  collect(bridge);
  try {
    expect(await waitFor(() => exited)).toBe(true);
  } finally {
    bridge.close();
  }
});

test("termSessionName sanitizes ids", () => {
  expect(termSessionName("phone")).toBe("lfg-term-phone");
  expect(termSessionName("a.b:c/d")).toBe("lfg-term-abcd");
  expect(termSessionName("")).toBe("lfg-term-main");
});

test("a terminal attach restores a manually sized tmux window and follows PTY resizes", async () => {
  const socket = `lfg-pty-test-${process.pid}-${Math.random().toString(36).slice(2)}`;
  const tmux = (...args: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...args]);
  const windowWidth = () => Number(new TextDecoder().decode(
    tmux("display-message", "-p", "-t", "phone", "#{window_width}").stdout,
  ).trim());
  let bridge: PtyBridge | null = null;
  try {
    expect(tmux("new-session", "-d", "-s", "phone", "-x", "120", "-y", "40").exitCode).toBe(0);
    expect(tmux("resize-window", "-t", "phone", "-x", "120", "-y", "200").exitCode).toBe(0);
    expect(new TextDecoder().decode(tmux("show-options", "-w", "-t", "phone", "window-size").stdout).trim())
      .toBe("window-size manual");

    expect(restoreTermWindowAutoSize("phone", socket)).toBe(true);
    expect(new TextDecoder().decode(tmux("show-options", "-w", "-t", "phone", "window-size").stdout).trim())
      .toBe("window-size latest");

    bridge = new PtyBridge(["tmux", "-L", socket, "attach-session", "-t", "phone"],
      { cols: 48, rows: 20 });
    expect(await waitFor(() => windowWidth() === 48)).toBe(true);
    bridge.resize(120, 20);
    expect(await waitFor(() => windowWidth() === 120)).toBe(true);
  } finally {
    bridge?.close();
    tmux("kill-server");
  }
});
