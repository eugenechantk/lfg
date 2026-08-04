// One pane, one sendable session.
//
// Claude Code's branch view runs the fronted conversation in a DETACHED child
// (transient daemon → bg-pty-host → the branch agent), all descendants of the
// pane's TUI. So six pids can resolve to one pane. The old guard dropped the
// target from all of them, which made the pane unsendable and 409'd every
// follow-up ("session is not in a tmux pane — cannot send").
//
// The candidate set below is the real one observed on pane cy-224353-78784:0.0,
// where the branch (pid 90707) — not the parent TUI (79040) — was what the
// pane's keystrokes actually reached.
import { test, expect } from "bun:test";
import { resolvePaneOwners } from "./sessions";

const PANE = "cy-224353-78784:0.0";

function row(pid: number, sessionId: string | null, lastActivityAt: number | null) {
  return { pid, sessionId, lastActivityAt, tmuxTarget: PANE } as never;
}

// Verbatim from the failing host.
function realCandidates() {
  return [
    row(79040, "a135bff5-b8b9-4d2a-9215-54682a4d72d1", 1785815163640), // parent TUI
    row(90638, "2d160746-0000-0000-0000-000000000000", 1784989538286), // daemon, 9d stale
    row(90674, null, null), // bg-pty-host
    row(90675, null, null), // bg-pty-host
    row(90693, null, null), // bg-spare
    row(90707, "0b41d17c-7cf6-4c89-88fd-4cda00de470e", 1785815236463), // the branch
  ];
}

test("the fronted branch keeps the pane, not the parent TUI", () => {
  const rows = realCandidates();
  resolvePaneOwners(rows);
  const kept = rows.filter((r: never) => (r as { tmuxTarget: string | null }).tmuxTarget);
  expect(kept).toHaveLength(1);
  expect((kept[0] as { pid: number }).pid).toBe(90707);
});

test("exactly one row stays sendable — the pane is never left unsendable", () => {
  // The regression: every row losing its target is what produced the blue-bubble
  // "cannot send" error with a Try Again button.
  const rows = realCandidates();
  resolvePaneOwners(rows);
  expect(
    rows.filter((r: never) => (r as { tmuxTarget: string | null }).tmuxTarget),
  ).not.toHaveLength(0);
});

test("daemon workers with no session or transcript can never win", () => {
  const rows = realCandidates();
  resolvePaneOwners(rows);
  for (const pid of [90674, 90675, 90693, 90638]) {
    const r = rows.find((x: never) => (x as { pid: number }).pid === pid)!;
    expect((r as { tmuxTarget: string | null }).tmuxTarget).toBeNull();
  }
});

test("the parent TUI wins back the pane once it is the active conversation", () => {
  // Switching out of branch view: the parent starts taking turns again.
  const rows = [
    row(79040, "a135bff5-b8b9-4d2a-9215-54682a4d72d1", 1785815999999),
    row(90707, "0b41d17c-7cf6-4c89-88fd-4cda00de470e", 1785815236463),
  ];
  resolvePaneOwners(rows);
  expect((rows[0] as { tmuxTarget: string | null }).tmuxTarget).toBe(PANE);
  expect((rows[1] as { tmuxTarget: string | null }).tmuxTarget).toBeNull();
});

test("an ordinary single-session pane is untouched", () => {
  const rows = [row(60523, "a9388586-bec9-40c8-8481-bd44d736f8ea", 1785815464961)];
  resolvePaneOwners(rows);
  expect((rows[0] as { tmuxTarget: string | null }).tmuxTarget).toBe(PANE);
});

test("sessions on different panes never compete", () => {
  const a = { pid: 1, sessionId: "a", lastActivityAt: 10, tmuxTarget: "s1:0.0" } as never;
  const b = { pid: 2, sessionId: "b", lastActivityAt: 99, tmuxTarget: "s2:0.0" } as never;
  resolvePaneOwners([a, b]);
  expect((a as { tmuxTarget: string | null }).tmuxTarget).toBe("s1:0.0");
  expect((b as { tmuxTarget: string | null }).tmuxTarget).toBe("s2:0.0");
});
