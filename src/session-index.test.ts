import { describe, expect, test } from "bun:test";
import {
  SEARCH_INDEX_VERSION,
  applyTitleOverrides,
  matchesTerms,
  matchingEntries,
  parseIndexFile,
  planRefresh,
  queryTerms,
  serializeIndex,
  type IndexCandidate,
  type IndexEntry,
} from "./session-index.ts";

function entry(over: Partial<IndexEntry> & { sessionId: string; mtime: number }): IndexEntry {
  return {
    agent: "claude",
    path: `/p/${over.sessionId}.jsonl`,
    cwd: "/tmp/proj",
    project: "tmp-proj",
    title: "a title",
    lastUserText: null,
    ...over,
  };
}

describe("planRefresh", () => {
  test("reuses entries whose path and mtime are unchanged", () => {
    const prev = [entry({ sessionId: "a", mtime: 100 }), entry({ sessionId: "b", mtime: 200 })];
    const candidates: IndexCandidate[] = [
      { agent: "claude", sessionId: "a", path: "/p/a.jsonl", mtime: 100 },
      { agent: "claude", sessionId: "b", path: "/p/b.jsonl", mtime: 200 },
    ];

    const plan = planRefresh(prev, candidates);

    expect(plan.reuse.map((e) => e.sessionId)).toEqual(["a", "b"]);
    expect(plan.stale).toEqual([]);
    expect(plan.dropped).toBe(0);
  });

  test("re-enriches a modified, moved, or new transcript", () => {
    const prev = [
      entry({ sessionId: "modified", mtime: 100 }),
      entry({ sessionId: "moved", mtime: 100, path: "/old/moved.jsonl" }),
    ];
    const candidates: IndexCandidate[] = [
      { agent: "claude", sessionId: "modified", path: "/p/modified.jsonl", mtime: 101 },
      { agent: "claude", sessionId: "moved", path: "/new/moved.jsonl", mtime: 100 },
      { agent: "claude", sessionId: "fresh", path: "/p/fresh.jsonl", mtime: 300 },
    ];

    const plan = planRefresh(prev, candidates);

    expect(plan.reuse).toEqual([]);
    expect(plan.stale.map((c) => c.sessionId)).toEqual(["modified", "moved", "fresh"]);
  });

  test("an older mtime is stale too — a synced-back file's content is older as well", () => {
    const prev = [entry({ sessionId: "a", mtime: 500 })];
    const plan = planRefresh(prev, [
      { agent: "claude", sessionId: "a", path: "/p/a.jsonl", mtime: 400 },
    ]);

    expect(plan.reuse).toEqual([]);
    expect(plan.stale.map((c) => c.sessionId)).toEqual(["a"]);
  });

  test("drops indexed sessions that are no longer on disk", () => {
    const prev = [entry({ sessionId: "gone", mtime: 100 }), entry({ sessionId: "kept", mtime: 100 })];

    const plan = planRefresh(prev, [
      { agent: "claude", sessionId: "kept", path: "/p/kept.jsonl", mtime: 100 },
    ]);

    expect(plan.reuse.map((e) => e.sessionId)).toEqual(["kept"]);
    expect(plan.dropped).toBe(1);
  });

  test("keeps the first of a duplicated sessionId so paging cannot repeat it", () => {
    const plan = planRefresh([], [
      { agent: "claude", sessionId: "dup", path: "/newest/dup.jsonl", mtime: 900 },
      { agent: "claude", sessionId: "dup", path: "/copy/dup.jsonl", mtime: 100 },
    ]);

    expect(plan.stale).toHaveLength(1);
    expect(plan.stale[0].path).toBe("/newest/dup.jsonl");
  });
});

describe("query matching", () => {
  test("matches case-insensitively across title, project, cwd and last user text", () => {
    const e = entry({
      sessionId: "a",
      mtime: 1,
      title: "Fix the Preamble",
      project: "users-eugene-dev-lfg",
      cwd: "/Users/eugene/dev/lfg",
      lastUserText: "restart the server please",
    });

    expect(matchesTerms(e, queryTerms("preamble"))).toBe(true);
    expect(matchesTerms(e, queryTerms("PREAMBLE"))).toBe(true);
    expect(matchesTerms(e, queryTerms("lfg"))).toBe(true);
    expect(matchesTerms(e, queryTerms("/Users/eugene"))).toBe(true);
    expect(matchesTerms(e, queryTerms("restart"))).toBe(true);
    expect(matchesTerms(e, queryTerms("nonexistent"))).toBe(false);
  });

  test("multiple terms AND across fields", () => {
    const e = entry({
      sessionId: "a",
      mtime: 1,
      title: "fix the preamble",
      project: "lfg",
      lastUserText: null,
    });

    expect(matchesTerms(e, queryTerms("preamble lfg"))).toBe(true);
    expect(matchesTerms(e, queryTerms("preamble missing"))).toBe(false);
  });

  test("an empty query matches everything", () => {
    expect(matchesTerms(entry({ sessionId: "a", mtime: 1 }), queryTerms("   "))).toBe(true);
  });

  test("matches a session id, so a pasted id finds its conversation", () => {
    const e = entry({ sessionId: "00000000-0000-4000-8000-00000000beef", mtime: 1 });
    expect(matchesTerms(e, queryTerms("00000000-0000-4000-8000-00000000beef"))).toBe(true);
  });
});

describe("matchingEntries", () => {
  const corpus = [
    entry({ sessionId: "c", mtime: 300, title: "preamble three" }),
    entry({ sessionId: "a", mtime: 100, title: "preamble one" }),
    entry({ sessionId: "b", mtime: 200, title: "preamble two" }),
    entry({ sessionId: "z", mtime: 400, title: "unrelated" }),
  ];

  test("returns matches newest-first regardless of input order", () => {
    expect(matchingEntries(corpus, queryTerms("preamble"), null).map((e) => e.sessionId)).toEqual([
      "c",
      "b",
      "a",
    ]);
  });

  test("the before cursor is exclusive and walks strictly older", () => {
    const page1 = matchingEntries(corpus, queryTerms("preamble"), null).slice(0, 2);
    expect(page1.map((e) => e.sessionId)).toEqual(["c", "b"]);

    const page2 = matchingEntries(corpus, queryTerms("preamble"), page1[1].mtime);
    expect(page2.map((e) => e.sessionId)).toEqual(["a"]);
  });

  test("a match far outside the newest page is still found", () => {
    // The point of the whole feature: 20 newer sessions, none matching, and the
    // only hit is the oldest conversation in the corpus.
    const many = Array.from({ length: 20 }, (_, i) =>
      entry({ sessionId: `noise-${i}`, mtime: 1_000 + i, title: "noise" }),
    );
    const needle = entry({ sessionId: "needle", mtime: 1, title: "the buried one" });

    const hits = matchingEntries([...many, needle], queryTerms("buried"), null);

    expect(hits.map((e) => e.sessionId)).toEqual(["needle"]);
  });

  test("ties break on session id so paging is deterministic", () => {
    const tied = [
      entry({ sessionId: "bbb", mtime: 500, title: "tie" }),
      entry({ sessionId: "aaa", mtime: 500, title: "tie" }),
    ];
    expect(matchingEntries(tied, queryTerms("tie"), null).map((e) => e.sessionId)).toEqual([
      "aaa",
      "bbb",
    ]);
  });
});

describe("index file round-trip", () => {
  test("serializes and parses back", () => {
    const entries = [entry({ sessionId: "a", mtime: 1, lastUserText: "hi" })];
    expect(parseIndexFile(serializeIndex(entries))).toEqual(entries);
  });

  test("discards a file from a different index version", () => {
    expect(parseIndexFile({ version: SEARCH_INDEX_VERSION + 1, entries: [entry({ sessionId: "a", mtime: 1 })] })).toEqual([]);
  });

  test("survives garbage without throwing", () => {
    expect(parseIndexFile(null)).toEqual([]);
    expect(parseIndexFile("nope")).toEqual([]);
    expect(parseIndexFile({ version: SEARCH_INDEX_VERSION })).toEqual([]);
    expect(
      parseIndexFile({ version: SEARCH_INDEX_VERSION, entries: [null, { sessionId: "" }, { sessionId: "a" }] }),
    ).toEqual([]);
  });
});

describe("applyTitleOverrides", () => {
  test("a renamed session is searchable by its new title", () => {
    const entries = [entry({ sessionId: "a", mtime: 1, title: "original prompt" })];

    const overlaid = applyTitleOverrides(entries, { a: "Preamble investigation" });

    expect(matchesTerms(overlaid[0], queryTerms("preamble"))).toBe(true);
    expect(entries[0].title).toBe("original prompt"); // no mutation of the cache
  });

  test("is a no-op when there are no overrides", () => {
    const entries = [entry({ sessionId: "a", mtime: 1 })];
    expect(applyTitleOverrides(entries, {})).toBe(entries);
  });
});
