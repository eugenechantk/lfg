import { describe, expect, test } from "bun:test";
import { rankSessions, RankedSearchPager } from "./ranked-session-search";
import type { IndexEntry } from "./session-index";

const entry = (sessionId: string, title: string, mtime: number): IndexEntry => ({
  agent: "claude", sessionId, path: `/tmp/${sessionId}.jsonl`, mtime,
  cwd: "/tmp/work", project: "work", title, lastUserText: null, userText: "",
});

describe("ranked session search", () => {
  test("exact title leads, assistant prose is searchable, and user hit wins close prose ties", () => {
    const rows = rankSessions([
      entry("assistant", "unrelated", 300),
      entry("title", "Amber notebook", 100),
      entry("user", "unrelated", 200),
    ], [
      { sessionId: "assistant", role: "assistant", text: "The amber notebook is here", rank: -1, ts: null },
      { sessionId: "user", role: "user", text: "Find my amber notebook", rank: -1, ts: null },
    ], "amber notebook");
    expect(rows.map((row) => row.sessionId)).toEqual(["title", "user", "assistant"]);
    expect(rows[1].lastUserText).toContain("You: Find my amber notebook");
    expect(rows[2].lastUserText).toContain("Assistant: The amber notebook");
  });

  test("terms can be spread across messages and metadata", () => {
    const rows = rankSessions([entry("a", "amber project", 100)], [
      { sessionId: "a", role: "assistant", text: "The cobalt answer", rank: -1, ts: null },
    ], "amber cobalt");
    expect(rows.map((row) => row.sessionId)).toEqual(["a"]);
  });

  test("frozen cursor walks all ranked sessions without overlap despite a new first page", () => {
    const pager = new RankedSearchPager();
    const rows = rankSessions([entry("a", "amber", 300), entry("b", "amber", 200), entry("c", "amber", 100)], [], "amber");
    const first = pager.first("amber", "[]", rows, 1);
    pager.first("amber", "[]", [entry("new", "amber", 400) as never], 1);
    const second = pager.next(first.nextCursor!, "amber", "[]", 1)!;
    const third = pager.next(second.nextCursor!, "amber", "[]", 1)!;
    expect([...first.sessions, ...second.sessions, ...third.sessions].map((row) => row.sessionId)).toEqual(["a", "b", "c"]);
    expect(third.nextCursor).toBeNull();
    expect(pager.next(first.nextCursor!, "different", "[]", 1)).toBeNull();
  });
});
