import { test, expect, afterAll } from "bun:test";
import { TermScroll, type TmuxRunner } from "./term-scroll.ts";

// --- unit: the tmux commands issued, via a recording runner ---

function recorder() {
  const calls: string[] = [];
  const run: TmuxRunner = async (args) => { calls.push(args.join(" ")); return 0; };
  return { calls, run };
}

test("scrolling up enters copy-mode once, then scrolls by lines", async () => {
  const { calls, run } = recorder();
  const s = new TermScroll("lfg-term-x", run);
  await s.scroll(3);
  await s.scroll(2);
  expect(calls).toEqual([
    "copy-mode -e -t lfg-term-x",
    "send-keys -t lfg-term-x -X -N 3 scroll-up",
    "send-keys -t lfg-term-x -X -N 2 scroll-up",
  ]);
});

test("scrolling down at the live screen does nothing", async () => {
  const { calls, run } = recorder();
  const s = new TermScroll("lfg-term-x", run);
  await s.scroll(-5);
  await s.scroll(0);
  expect(calls).toEqual([]);
});

test("input after scrolling cancels copy-mode first, and keeps keystroke order", async () => {
  const { calls, run } = recorder();
  const s = new TermScroll("lfg-term-x", run);
  const written: string[] = [];
  await s.scroll(4);
  s.input(() => written.push("a"));
  s.input(() => written.push("b"));
  await s.idle();
  expect(calls.at(-1)).toBe("send-keys -t lfg-term-x -X cancel");
  expect(written).toEqual(["a", "b"]);
  // Back at the live screen: input goes straight through, no tmux call.
  const before = calls.length;
  s.input(() => written.push("c"));
  expect(written).toEqual(["a", "b", "c"]);
  expect(calls.length).toBe(before);
});

test("line counts are clamped and truncated", async () => {
  const { calls, run } = recorder();
  const s = new TermScroll("t", run);
  await s.scroll(99999.7);
  expect(calls.at(-1)).toBe("send-keys -t t -X -N 1000 scroll-up");
});

// --- integration: a real tmux session ---

const session = `lfg-term-scrolltest-${process.pid}`;
const tmux = (...args: string[]) => Bun.spawnSync(["tmux", ...args]).stdout.toString().trim();
afterAll(() => { Bun.spawnSync(["tmux", "kill-session", "-t", session]); });

test("real tmux: scroll back through history, input returns to the live screen", async () => {
  Bun.spawnSync(["tmux", "new-session", "-d", "-s", session, "-x", "80", "-y", "24", "sh"]);
  Bun.spawnSync(["tmux", "send-keys", "-t", session, "seq 1 500", "Enter"]);
  await Bun.sleep(500);
  const s = new TermScroll(session);
  await s.scroll(40);
  expect(tmux("display", "-p", "-t", session, "#{pane_in_mode} #{scroll_position}")).toBe("1 40");
  await s.scroll(-15);
  expect(tmux("display", "-p", "-t", session, "#{scroll_position}")).toBe("25");
  s.input(() => {});
  await s.idle();
  expect(tmux("display", "-p", "-t", session, "#{pane_in_mode}")).toBe("0");
});
