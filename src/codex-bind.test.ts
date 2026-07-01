import { describe, expect, it } from "bun:test";
import { pickCodexThread } from "./sessions.ts";

type Thread = {
  id: string;
  path: string;
  cwd: string | null;
  createdAt: number | null;
  updatedAt: number | null;
  firstUserText: string | null;
};

const T0 = 1_782_885_876_000; // process startedAt used across cases

function thread(over: Partial<Thread> & { id: string }): Thread {
  return {
    path: `/rollout-${over.id}.jsonl`,
    cwd: "/Users/eugenechan/dev/inbox",
    createdAt: T0 + 8_000,
    updatedAt: T0 + 8_000,
    firstUserText: null,
    ...over,
  };
}

describe("pickCodexThread — promptless (interactive codex)", () => {
  it("binds an interactive codex to its same-cwd rollout written just after launch", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got?.id).toBe("a");
  });

  it("does not bind a rollout from a different cwd", () => {
    const t = thread({ id: "a", cwd: "/other/dir" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("does not bind a stale rollout created well before launch", () => {
    const t = thread({ id: "a", createdAt: T0 - 5 * 60_000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("does not bind a rollout created long after launch (a newer session)", () => {
    const t = thread({ id: "a", createdAt: T0 + 10 * 60_000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("skips already-claimed rollouts", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(["a"]),
    );
    expect(got).toBeNull();
  });

  it("binds two interactive codex in the same cwd each to its nearest-launch rollout", () => {
    const startA = T0;
    const startB = T0 + 60_000;
    const rollA = thread({ id: "a", createdAt: startA + 5_000 });
    const rollB = thread({ id: "b", createdAt: startB + 5_000 });
    const threads = [rollA, rollB];
    const claimed = new Set<string>();

    const gotA = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: startA, prompt: null },
      threads,
      claimed,
    );
    expect(gotA?.id).toBe("a");
    claimed.add(gotA!.id);

    const gotB = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: startB, prompt: null },
      threads,
      claimed,
    );
    expect(gotB?.id).toBe("b");
  });

  it("returns null when startedAt is unknown (can't disambiguate promptless)", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: null, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });
});

describe("pickCodexThread — prompt match (regression)", () => {
  it("binds by matching first user text, freshest wins", () => {
    const older = thread({ id: "old", firstUserText: "fix the bug", updatedAt: T0 });
    const newer = thread({ id: "new", firstUserText: "fix the bug", updatedAt: T0 + 1000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: "fix the bug" },
      [older, newer],
      new Set(),
    );
    expect(got?.id).toBe("new");
  });

  it("does not bind when no thread's prompt matches", () => {
    const t = thread({ id: "a", firstUserText: "something else" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: "fix the bug" },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });
});
