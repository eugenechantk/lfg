import { describe, expect, test } from "bun:test";
import {
  buildRetitlePrompt,
  cleanTitle,
  isRealChange,
  parseRetitleBatch,
  selectRetitleCandidates,
  type RetitleCandidate,
} from "./retitle.ts";
import { parseCheckpoints, pruneCheckpoints } from "./checkpoints.ts";
import { parseTitleFile, type TitleFile } from "./titles.ts";

const HOST = "host-pro";
const NOW = 1_800_000_000_000;
const DAY = 24 * 60 * 60 * 1000;

function cand(over: Partial<RetitleCandidate> = {}): RetitleCandidate {
  return {
    sessionId: over.sessionId ?? "s1",
    path: `/p/${over.sessionId ?? "s1"}.jsonl`,
    mtime: NOW - 60_000,
    bytes: 100_000,
    cwd: "/Users/e/dev/lfg",
    title: "Fix the preamble",
    live: false,
    leaseHost: HOST,
    ...over,
  };
}

const select = (
  cands: RetitleCandidate[],
  titles: TitleFile = {},
  checkpoints = {},
  opts: { max?: number; windowMs?: number } = {},
) => selectRetitleCandidates(cands, titles, checkpoints, NOW, { hostId: HOST, ...opts });

describe("selectRetitleCandidates", () => {
  test("takes a recent session owned by this host", () => {
    expect(select([cand()]).map((c) => c.sessionId)).toEqual(["s1"]);
  });

  test("never touches a human-set title", () => {
    const titles = parseTitleFile({ s1: "Eugene named this" });
    expect(select([cand()], titles)).toEqual([]);
  });

  test("does touch a title autopilot set earlier", () => {
    const titles = parseTitleFile({
      s1: { title: "Autopilot named this", source: "auto", setAt: 1 },
    });
    expect(select([cand()], titles).map((c) => c.sessionId)).toEqual(["s1"]);
  });

  test("skips sessions outside the recency window", () => {
    expect(select([cand({ mtime: NOW - 8 * DAY })])).toEqual([]);
  });

  test("skips sessions the OTHER host holds the lease for", () => {
    // ~/.claude/projects is synced; without this both boxes retitle the same
    // transcript and disagree.
    expect(select([cand({ leaseHost: "host-air" })])).toEqual([]);
  });

  test("skips sessions with no lease at all", () => {
    // Unclaimed here is equally unclaimed on the peer, so both would take it.
    expect(select([cand({ leaseHost: null })])).toEqual([]);
  });

  test("a live session this host holds the lease for ignores the age window", () => {
    const live = cand({ sessionId: "live", live: true, mtime: NOW - 30 * DAY });
    expect(select([live]).map((c) => c.sessionId)).toEqual(["live"]);
  });

  test("a LIVE session the other host holds the lease for is skipped", () => {
    // The regression this exists for: `~/.claude` is synced, so one sessionId
    // can read as live on BOTH boxes at once. An earlier version exempted live
    // sessions from the lease check on the theory that live implied local, and
    // the Pro and the Air each retitled session 01e32dd7 to a different name.
    const live = cand({ sessionId: "live", live: true, leaseHost: "host-air" });
    expect(select([live])).toEqual([]);
  });

  test("a live session with no lease at all is skipped", () => {
    expect(select([cand({ sessionId: "live", live: true, leaseHost: null })])).toEqual([]);
  });

  test("skips sessions with no new transcript bytes since the last look", () => {
    const checkpoints = { s1: { bytes: 100_000, at: NOW - DAY } };
    expect(select([cand({ bytes: 100_500 })], {}, checkpoints)).toEqual([]);
  });

  test("re-examines once the transcript has grown enough", () => {
    const checkpoints = { s1: { bytes: 100_000, at: NOW - DAY } };
    expect(select([cand({ bytes: 200_000 })], {}, checkpoints).map((c) => c.sessionId)).toEqual([
      "s1",
    ]);
  });

  test("live sessions sort ahead of merely recent ones", () => {
    const rows = [
      cand({ sessionId: "recent" }),
      cand({ sessionId: "live", live: true }),
    ];
    expect(select(rows).map((c) => c.sessionId)).toEqual(["live", "recent"]);
  });

  test("least-recently-examined first, so a big corpus round-robins", () => {
    const rows = [
      cand({ sessionId: "checkedRecently" }),
      cand({ sessionId: "checkedLongAgo" }),
      cand({ sessionId: "neverChecked" }),
    ];
    const checkpoints = {
      checkedRecently: { bytes: 0, at: NOW - 1000 },
      checkedLongAgo: { bytes: 0, at: NOW - 10 * DAY },
    };
    expect(select(rows, {}, checkpoints).map((c) => c.sessionId)).toEqual([
      "neverChecked",
      "checkedLongAgo",
      "checkedRecently",
    ]);
  });

  test("caps the batch so one LLM call stays bounded", () => {
    const rows = Array.from({ length: 50 }, (_, i) => cand({ sessionId: `s${i}` }));
    expect(select(rows, {}, {}, { max: 12 })).toHaveLength(12);
  });
});

describe("parseRetitleBatch", () => {
  const asked = ["a", "b"];

  test("parses a bare JSON array", () => {
    const out = parseRetitleBatch('[{"id":"a","title":"New name"},{"id":"b","title":null}]', asked);
    expect(out).toEqual([
      { id: "a", title: "New name" },
      { id: "b", title: null },
    ]);
  });

  test("parses a fenced array", () => {
    const text = 'Sure:\n```json\n[{"id":"a","title":"New name"}]\n```';
    expect(parseRetitleBatch(text, asked)).toEqual([{ id: "a", title: "New name" }]);
  });

  test("parses an array embedded in prose", () => {
    const text = 'Here you go: [{"id":"a","title":"New name"}] — hope that helps!';
    expect(parseRetitleBatch(text, asked)).toEqual([{ id: "a", title: "New name" }]);
  });

  test("drops ids that were never asked about", () => {
    // A hallucinated id must never be applied to some other session.
    const out = parseRetitleBatch('[{"id":"zzz","title":"Nope"},{"id":"a","title":"Yes"}]', asked);
    expect(out).toEqual([{ id: "a", title: "Yes" }]);
  });

  test("keeps only the first entry for a duplicated id", () => {
    const out = parseRetitleBatch('[{"id":"a","title":"First"},{"id":"a","title":"Second"}]', asked);
    expect(out).toEqual([{ id: "a", title: "First" }]);
  });

  test("a missing or non-string title is treated as leave-alone or dropped", () => {
    expect(parseRetitleBatch('[{"id":"a"}]', asked)).toEqual([{ id: "a", title: null }]);
    expect(parseRetitleBatch('[{"id":"a","title":42}]', asked)).toEqual([]);
  });

  test("an empty title means leave it alone, not blank it", () => {
    expect(parseRetitleBatch('[{"id":"a","title":"  "}]', asked)).toEqual([{ id: "a", title: null }]);
  });

  test("unparseable output yields no proposals rather than throwing", () => {
    for (const t of ["", "I could not do that", "{{{", "null"]) {
      expect(parseRetitleBatch(t, asked)).toEqual([]);
    }
  });
});

describe("cleanTitle", () => {
  test("strips quotes, labels, trailing punctuation and collapses space", () => {
    expect(cleanTitle('  "Autopilot   retitle task."  ')).toBe("Autopilot retitle task");
    expect(cleanTitle("Title: iOS push expiry")).toBe("iOS push expiry");
    expect(cleanTitle("`backtick wrapped`")).toBe("backtick wrapped");
  });

  test("caps length", () => {
    expect(cleanTitle("x".repeat(200)).length).toBe(80);
  });
});

describe("isRealChange", () => {
  test("null is never a change", () => {
    expect(isRealChange({ id: "a", title: null }, "Old")).toBe(false);
  });

  test("a case- or whitespace-only difference is not a change", () => {
    expect(isRealChange({ id: "a", title: "fix  the Preamble" }, "Fix the preamble")).toBe(false);
  });

  test("a genuinely different title is a change", () => {
    expect(isRealChange({ id: "a", title: "Autopilot retitle" }, "Fix the preamble")).toBe(true);
  });
});

describe("buildRetitlePrompt", () => {
  const digests = [
    { sessionId: "a", title: "Fix the preamble", project: "lfg", turns: ["one", "two"] },
  ];

  test("carries id, current title, project and turns", () => {
    const p = buildRetitlePrompt(digests);
    expect(p).toContain("id: a");
    expect(p).toContain("current_title: Fix the preamble");
    expect(p).toContain("project: lfg");
    expect(p).toContain("- one");
    expect(p).toContain("- two");
  });

  test("asks for a JSON array and biases toward null", () => {
    const p = buildRetitlePrompt(digests);
    expect(p).toContain('[{"id": "<session id>", "title": "<new title>" | null}]');
    expect(p.toLowerCase()).toContain("prefer null");
  });

  test("a session with no usable turns still renders", () => {
    const p = buildRetitlePrompt([{ sessionId: "b", title: "t", project: "p", turns: [] }]);
    expect(p).toContain("(none)");
  });
});

describe("checkpoints", () => {
  test("round-trips and drops malformed rows", () => {
    const parsed = parseCheckpoints({
      good: { bytes: 10, at: 20 },
      noBytes: { at: 20 },
      nan: { bytes: NaN, at: 1 },
      notObj: 3,
    });
    expect(parsed).toEqual({ good: { bytes: 10, at: 20 } });
  });

  test("a non-object file yields empty checkpoints", () => {
    for (const v of [null, undefined, "x", []]) expect(parseCheckpoints(v)).toEqual({});
  });

  test("pruning keeps only sessions still in the candidate set", () => {
    const file = { a: { bytes: 1, at: 1 }, b: { bytes: 2, at: 2 } };
    expect(pruneCheckpoints(file, new Set(["a"]))).toEqual({ a: { bytes: 1, at: 1 } });
  });
});
