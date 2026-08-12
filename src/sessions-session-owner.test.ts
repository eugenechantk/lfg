// One sessionId, one row.
//
// This is the OTHER collision — not several pids resolving to one pane
// (sessions-pane-owner.test.ts), but two live processes in *different* panes
// each holding an authoritative `~/.claude/sessions/<pid>.json` naming the SAME
// sessionId. An in-TUI `/resume` of a session another live claude is already on
// produces it.
//
// The rows below are verbatim from the host that shipped the bug: two `claude
// --dangerously-skip-permissions` in ~/dev/personal/reelly, pids 36372 and
// 18071, both claiming d1a3496d. One pane sat on an AskUserQuestion, the other
// idle at the composer, so the push watcher — whose `prior` map is keyed by
// sessionId — saw the prompt "appear" every single tick and sent a "🙋 reelly"
// needs-input push every ~12s for a session nobody had asked anything of.
import { test, expect } from "bun:test";
import { resolveSessionOwners } from "./sessions";

const REELLY = "d1a3496d-cd67-483b-b973-a2d8cb57ab21";

function row(pid: number, sessionId: string | null, startedAt: number | null) {
  return { pid, sessionId, startedAt } as never;
}

// pidfile `startedAt` — when each process bound the id, not when it launched.
// Present only for pids whose `~/.claude/sessions/<pid>.json` was readable; a pid
// missing here is a GUESS (id scraped off the `--resume` arg).
const BOUND = new Map<number, number>([
  [36372, 1786114225725], // Aug 7 14:50, the older claimant
  [18071, 1786182842584], // Aug 8 09:54, resumed onto the same session
]);
const claim = (pid: number) => {
  const boundAt = BOUND.get(pid);
  return boundAt == null
    ? { authoritative: false, boundAt: null }
    : { authoritative: true, boundAt };
};

function realCollision() {
  return [
    row(36372, REELLY, 1786114224000),
    row(18071, REELLY, 1786182841000),
  ];
}

test("two live processes claiming one session collapse to the newest claimant", () => {
  const kept = resolveSessionOwners(realCollision(), claim);
  expect(kept).toHaveLength(1);
  expect((kept[0] as { pid: number }).pid).toBe(18071);
});

test("an authoritative claimant beats a guessed one regardless of process age", () => {
  // The guess (no pidfile → no claim) is the NEWER process, so a naive
  // newest-wins would pick it and bind the pane of a session we only inferred.
  const kept = resolveSessionOwners(
    [row(36372, REELLY, 1786114224000), row(99999, REELLY, 1786200000000)],
    claim,
  );
  expect(kept).toHaveLength(1);
  expect((kept[0] as { pid: number }).pid).toBe(36372);
});

test("the winner is stable across ticks — a flapping winner would restore the storm", () => {
  const first = resolveSessionOwners(realCollision(), claim);
  // Same processes, opposite enumeration order (ps ordering is not guaranteed).
  const second = resolveSessionOwners(realCollision().reverse(), claim);
  expect((first[0] as { pid: number }).pid).toBe((second[0] as { pid: number }).pid);
});

test("distinct sessions and id-less worker rows are left alone", () => {
  const rows = [
    row(1, REELLY, 100),
    row(2, "0c9fa133-0000-0000-0000-000000000000", 200),
    row(3, null, null),
    row(4, null, null),
  ];
  expect(resolveSessionOwners(rows, claim)).toHaveLength(4);
});

test("the array identity is preserved when there is nothing to drop", () => {
  const rows = [row(1, REELLY, 100)];
  expect(resolveSessionOwners(rows, claim)).toBe(rows as never);
});

test("three-way collision still yields exactly one row", () => {
  const kept = resolveSessionOwners(
    [row(36372, REELLY, 1), row(18071, REELLY, 2), row(40000, REELLY, 3)],
    claim,
  );
  expect(kept).toHaveLength(1);
  // 40000 has no pidfile binding at all, so it loses to both real claimants;
  // 18071 bound the id most recently of the two that did.
  expect((kept[0] as { pid: number }).pid).toBe(18071);
});

// The OTHER collision shape, and it wants the OPPOSITE tiebreak. Verbatim from
// the same host: pid 4559 is `claude --resume 03533b45`, pids 96879 and 97772 are
// `claude --resume 03533b45 --fork-session`. The forks genuinely own b9b47c23 and
// 408c20d9 — but until their pidfiles are readable every id is guessed off the
// identical `--resume` arg, so for the first moments of a fork's life all three
// look like the parent. Newest-wins would hand the parent's session to a fork.
const FORKED = "03533b45-6a9b-42c1-981b-8fd7212b7e37";
const noPidfiles = () => ({ authoritative: false, boundAt: null });

test("un-materialised forks lose to the session they forked from, not the reverse", () => {
  const kept = resolveSessionOwners(
    [
      row(4559, FORKED, 1786065644000), // the real owner, oldest
      row(96879, FORKED, 1786074698000), // fork, 2.5h later
      row(97772, FORKED, 1786074737000), // fork, 39s after that
    ],
    noPidfiles,
  );
  expect(kept).toHaveLength(1);
  expect((kept[0] as { pid: number }).pid).toBe(4559);
});

test("once each fork's pidfile lands they own distinct ids and nothing is dropped", () => {
  const kept = resolveSessionOwners(
    [
      row(4559, FORKED, 1786065644000),
      row(96879, "b9b47c23-0000-0000-0000-000000000000", 1786074698000),
      row(97772, "408c20d9-0000-0000-0000-000000000000", 1786074737000),
    ],
    noPidfiles,
  );
  expect(kept).toHaveLength(3);
});
