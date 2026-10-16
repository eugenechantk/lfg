import { describe, expect, test } from "bun:test";
import type { TaskRun } from "./scheduled-tasks.ts";
import { cachedTaskOrigins, taskOriginsBySession, withTaskOrigin } from "./task-origin.ts";

const run = (over: Partial<TaskRun>): TaskRun => ({
  id: "r1", taskId: "t1", taskName: "Daily repo review", agent: "claude", trigger: "scheduled",
  scheduledFor: 1_000, startedAt: 1_000, status: "succeeded", ...over,
});

describe("taskOriginsBySession", () => {
  test("maps each run's session to its task", () => {
    const map = taskOriginsBySession([
      run({ id: "r1", sessionId: "s1", taskId: "t1", taskName: "Daily repo review" }),
      run({ id: "r2", sessionId: "s2", taskId: "t2", taskName: "Readwise sync check" }),
    ]);
    expect(map.get("s1")).toEqual({ id: "t1", name: "Daily repo review" });
    expect(map.get("s2")).toEqual({ id: "t2", name: "Readwise sync check" });
  });

  test("skips runs that never got a session", () => {
    const map = taskOriginsBySession([run({ id: "r1", sessionId: undefined })]);
    expect(map.size).toBe(0);
  });

  test("the newest run wins when two runs name the same session", () => {
    const map = taskOriginsBySession([
      run({ id: "old", sessionId: "s1", taskId: "t-old", taskName: "Old name", startedAt: 1_000 }),
      run({ id: "new", sessionId: "s1", taskId: "t-new", taskName: "New name", startedAt: 2_000 }),
    ]);
    expect(map.get("s1")).toEqual({ id: "t-new", name: "New name" });
  });
});

describe("withTaskOrigin", () => {
  test("adds task only to sessions a task started", () => {
    const map = taskOriginsBySession([run({ sessionId: "s1" })]);
    expect(withTaskOrigin({ sessionId: "s1", title: "x" }, map)).toEqual({
      sessionId: "s1", title: "x", task: { id: "t1", name: "Daily repo review" },
    });
    const plain = { sessionId: "s9", title: "y" };
    expect(withTaskOrigin(plain, map)).toBe(plain);
    const noId: { sessionId?: string; title: string } = { title: "z" };
    expect(withTaskOrigin(noId, map)).toBe(noId);
  });
});

describe("cachedTaskOrigins", () => {
  test("reads the task store at most once per TTL", async () => {
    let reads = 0;
    let now = 0;
    const origins = cachedTaskOrigins(async () => {
      reads++;
      return { runs: [run({ sessionId: `s${reads}` })] };
    }, 5_000, () => now);

    expect((await origins()).has("s1")).toBe(true);
    now = 4_999;
    expect((await origins()).has("s1")).toBe(true);
    expect(reads).toBe(1);
    now = 5_000;
    expect((await origins()).has("s2")).toBe(true);
    expect(reads).toBe(2);
  });

  test("a failed read returns the last good map instead of throwing", async () => {
    let fail = false;
    let now = 0;
    const origins = cachedTaskOrigins(async () => {
      if (fail) throw new Error("disk");
      return { runs: [run({ sessionId: "s1" })] };
    }, 1_000, () => now);
    expect((await origins()).has("s1")).toBe(true);
    fail = true;
    now = 2_000;
    expect((await origins()).has("s1")).toBe(true);
  });

  test("a failed first read returns an empty map", async () => {
    const origins = cachedTaskOrigins(async () => { throw new Error("disk"); }, 1_000, () => 0);
    expect((await origins()).size).toBe(0);
  });
});
