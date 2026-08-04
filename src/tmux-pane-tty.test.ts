// Regression cover for the "two sessions claim one pane" bug: a detached Claude
// fork (spawned by the transient daemon, no controlling terminal) resolved to
// its ancestor's tmux pane, tripped the pane-collision guard in listSessions(),
// and nulled tmuxTarget for the REAL foreground session too — so every follow-up
// message to that session 409'd.
//
// The fixtures below are verbatim output captured from the machine where this
// reproduced (pane cy-224353-78784:0.0, foreground pid 79040 on ttys011, fork
// pid 90707 detached).
import { test, expect } from "bun:test";
import { parsePsRows, normalizeTty, ttyNameFromTtyNr } from "./procinfo";
import { parsePaneList } from "./tmux";

const PS_FIXTURE = [
  "    1     0 ??       Sun Aug  2 10:58:16 2026     /sbin/launchd",
  "  836     1 ??       Mon Aug  3 19:26:10 2026     /usr/libexec/logd",
  "90707 90675 ??       Mon Aug  3 22:55:31 2026     /opt/homebrew/bin/claude --session-id fb7d7f9e --fork-session --reply-on-resume",
  "79040  2810 ttys011  Mon Aug  3 22:43:53 2026     claude --dangerously-skip-permissions",
].join("\n");

const PANE_FIXTURE = [
  "54932 cy-000654-54570:0.0 /dev/ttys012",
  "79040 cy-224353-78784:0.0 /dev/ttys011",
  "76972 lfg-12ce15:0.0 /dev/ttys015",
].join("\n");

test("ps snapshot keeps ppid/start/cmd intact after the tty column was added", () => {
  const rows = parsePsRows(PS_FIXTURE);
  const fg = rows.get(79040)!;
  expect(fg.ppid).toBe(2810);
  expect(fg.cmd).toBe("claude --dangerously-skip-permissions");
  expect(fg.startMs).toBe(Date.parse("Mon Aug  3 22:43:53 2026"));
  // The command column must stay free-form — spaces and flags survive the split.
  expect(rows.get(90707)!.cmd).toContain("--fork-session --reply-on-resume");
});

test("ps snapshot distinguishes a pane's foreground proc from a detached fork", () => {
  const rows = parsePsRows(PS_FIXTURE);
  expect(rows.get(79040)!.tty).toBe("ttys011");
  expect(rows.get(90707)!.tty).toBeNull(); // "??" — no controlling terminal
  expect(rows.get(1)!.tty).toBeNull();
});

test("pane list parses pane_pid, target and tty", () => {
  const panes = parsePaneList(PANE_FIXTURE);
  expect(panes.get(79040)).toEqual({
    target: "cy-224353-78784:0.0",
    tty: "ttys011",
  });
  expect(panes.size).toBe(3);
});

test("a pane tty and a ps tty for the same terminal compare equal", () => {
  const panes = parsePaneList(PANE_FIXTURE);
  const rows = parsePsRows(PS_FIXTURE);
  // This equality is what tmuxTargetForPid gates on. Without the /dev/ strip
  // the two forms never match and every session would lose its target.
  expect(panes.get(79040)!.tty).toBe(rows.get(79040)!.tty);
  // The detached fork has nothing to match — it never claims the pane.
  expect(rows.get(90707)!.tty).not.toBe(panes.get(79040)!.tty);
});

test("normalizeTty folds every 'no terminal' spelling to null", () => {
  expect(normalizeTty("/dev/ttys011")).toBe("ttys011");
  expect(normalizeTty("/dev/pts/3")).toBe("pts/3");
  expect(normalizeTty("ttys011")).toBe("ttys011");
  for (const none of ["??", "?", "-", "", "   ", null, undefined]) {
    expect(normalizeTty(none)).toBeNull();
  }
});

test("Linux tty_nr decodes to the pts name tmux reports", () => {
  // major 136 (pts), minor 3 → tty_nr = (136 << 8) | 3 = 34819
  expect(ttyNameFromTtyNr((136 << 8) | 3)).toBe("pts/3");
  expect(ttyNameFromTtyNr(0)).toBeNull(); // no controlling terminal
  expect(ttyNameFromTtyNr(Number.NaN)).toBeNull();
  // Minor numbers above 255 spill into the high bits of tty_nr.
  expect(ttyNameFromTtyNr((136 << 8) | (300 & 0xff) | ((300 & 0xfff00) << 12))).toBe(
    "pts/300",
  );
});
