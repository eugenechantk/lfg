import { describe, expect, test } from "bun:test";
import { createRolloutMemo } from "./codex-rollout-memo.ts";

const WINDOW = 1000;

function rig(heads: Record<string, { head: string | null; final: boolean }>, firstUser: Record<string, string | null>) {
  const calls = { head: 0, firstUser: 0 };
  const memo = createRolloutMemo<string>({
    readHead: async (path) => {
      calls.head++;
      return heads[path] ?? { head: null, final: true };
    },
    readFirstUserText: async (path) => {
      calls.firstUser++;
      return firstUser[path] ?? null;
    },
    windowBytes: WINDOW,
  });
  return { memo, calls, heads, firstUser };
}

describe("createRolloutMemo", () => {
  test("a full-window rollout is read once, however often it is asked", async () => {
    const { memo, calls } = rig({ a: { head: "A", final: true } }, { a: "hello" });
    for (let i = 0; i < 5; i++) {
      expect(await memo.get("a", { birthtimeMs: 1, size: WINDOW + i * 10 })).toEqual({ head: "A", firstUserText: "hello" });
    }
    expect(calls).toEqual({ head: 1, firstUser: 1 });
  });

  test("below the window, the first user message is re-read only when the size changes", async () => {
    const { memo, calls, firstUser } = rig({ a: { head: "A", final: true } }, { a: null });
    expect((await memo.get("a", { birthtimeMs: 1, size: 100 })).firstUserText).toBeNull();
    expect((await memo.get("a", { birthtimeMs: 1, size: 100 })).firstUserText).toBeNull();
    expect(calls.firstUser).toBe(1);
    firstUser.a = "now there";
    expect((await memo.get("a", { birthtimeMs: 1, size: 300 })).firstUserText).toBe("now there");
    expect(calls.firstUser).toBe(2);
    // Filled the window: final from here on.
    expect((await memo.get("a", { birthtimeMs: 1, size: WINDOW })).firstUserText).toBe("now there");
    await memo.get("a", { birthtimeMs: 1, size: WINDOW * 3 });
    expect(calls).toEqual({ head: 1, firstUser: 3 });
  });

  test("a header still being written is read again until it is complete", async () => {
    const { memo, calls, heads } = rig({ a: { head: null, final: false } }, { a: "hi" });
    expect((await memo.get("a", { birthtimeMs: 1, size: 10 })).head).toBeNull();
    expect((await memo.get("a", { birthtimeMs: 1, size: 10 })).head).toBeNull();
    expect(calls.head).toBe(2);
    heads.a = { head: "A", final: true };
    expect(await memo.get("a", { birthtimeMs: 1, size: 50 })).toEqual({ head: "A", firstUserText: "hi" });
    await memo.get("a", { birthtimeMs: 1, size: 50 });
    expect(calls.head).toBe(3);
  });

  test("a file that is not a thread is decided once", async () => {
    const { memo, calls } = rig({ a: { head: null, final: true } }, {});
    for (let i = 0; i < 3; i++) expect(await memo.get("a", { birthtimeMs: 1, size: 10 })).toEqual({ head: null, firstUserText: null });
    expect(calls).toEqual({ head: 1, firstUser: 0 });
  });

  test("a replaced file (new birth time) or a shrunk file is read afresh", async () => {
    const { memo, calls, heads, firstUser } = rig({ a: { head: "A", final: true } }, { a: "one" });
    await memo.get("a", { birthtimeMs: 1, size: WINDOW });
    heads.a = { head: "B", final: true };
    firstUser.a = "two";
    expect(await memo.get("a", { birthtimeMs: 2, size: WINDOW })).toEqual({ head: "B", firstUserText: "two" });
    heads.a = { head: "C", final: true };
    firstUser.a = "three";
    expect(await memo.get("a", { birthtimeMs: 2, size: 10 })).toEqual({ head: "C", firstUserText: "three" });
    expect(calls).toEqual({ head: 3, firstUser: 3 });
  });

  test("prune forgets files that are gone", async () => {
    const { memo } = rig({ a: { head: "A", final: true }, b: { head: "B", final: true } }, {});
    await memo.get("a", { birthtimeMs: 1, size: 10 });
    await memo.get("b", { birthtimeMs: 1, size: 10 });
    expect(memo.size).toBe(2);
    memo.prune(new Set(["b"]));
    expect(memo.size).toBe(1);
  });
});
