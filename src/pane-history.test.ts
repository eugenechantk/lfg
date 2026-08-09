// Rebuilding the scrollback the alternate screen refuses to keep.
//
// The failure this exists to remove: a question's preamble is taller than the
// pane, so by the time the selector renders the top of the turn is gone and the
// client shows a mid-sentence fragment (or nothing). Measured on a real 78x59
// iTerm-hosted session — the size Eugene's `cy` sessions actually get.
import { test, expect, describe } from "bun:test";
import { PaneStitcher, MAX_LINES, contentAboveSelector } from "./pane-history.ts";
import { noteTurnEdge, withStitchedPreamble } from "./journal-pump.ts";

/** A pane frame: the last `rows` content lines plus the chrome a real pane draws. */
function frame(content: string[], rows = 12): string {
  const visible = content.slice(-rows);
  return [
    ...visible,
    "✽ Fermenting… (27s · ↓ 1.2k tokens)",
    "─".repeat(78),
    "❯ ",
    "─".repeat(78),
    "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt",
  ].join("\n");
}

/** Stream an answer one line at a time, capturing every `every` lines — i.e.
 *  what the pump's ~1Hz poll sees while the model types. */
function streamed(lines: string[], rows = 12, every = 3): string[] {
  const frames: string[] = [];
  for (let n = 1; n <= lines.length; n += every) frames.push(frame(lines.slice(0, n), rows));
  frames.push(frame(lines, rows));
  return frames;
}

const answer = [
  "⏺ HEADZZZ the opening sentence that must survive.",
  "  second line of the first paragraph.",
  "",
  "  a middle paragraph nobody should lose.",
  "  more of the middle paragraph.",
  "",
  "  the closing paragraph, which is all a single capture can still show.",
];

describe("PaneStitcher", () => {
  test("recovers a head that no single frame still contains", () => {
    const frames = streamed(answer, 4);
    // Precondition: the bug. The last frame really has lost the opening.
    expect(frames[frames.length - 1]).not.toContain("HEADZZZ");

    const s = new PaneStitcher();
    for (const f of frames) s.consume(f);
    const out = s.preamble();
    expect(out).toContain("HEADZZZ");
    expect(out).toContain("a middle paragraph nobody should lose");
    expect(out).toContain("the closing paragraph");
  });

  test("strips the bullet and rejoins the pane's hard wrap into paragraphs", () => {
    const s = new PaneStitcher();
    for (const f of streamed(answer, 4)) s.consume(f);
    const out = s.preamble()!;
    expect(out.startsWith("HEADZZZ")).toBe(true);
    expect(out).not.toContain("⏺");
    // First paragraph's two wrapped lines become one line; paragraphs separated.
    expect(out.split("\n\n").length).toBe(3);
  });

  test("chrome never enters the reconstruction", () => {
    const s = new PaneStitcher();
    for (const f of streamed(answer, 4)) s.consume(f);
    const out = s.preamble()!;
    for (const junk of ["Fermenting", "bypass permissions", "❯", "─────"]) {
      expect(out).not.toContain(junk);
    }
  });

  test("a spinner that ticks every frame cannot flood the buffer", () => {
    const s = new PaneStitcher();
    for (let i = 0; i < 300; i++) {
      s.consume(`⏺ one line of prose\n✽ Thinking… (${i}s · ↓ ${i}k tokens)\n${"─".repeat(78)}`);
    }
    expect(s.size()).toBe(1);
  });

  test("reset drops the previous turn, so its prose can't become the next preamble", () => {
    const s = new PaneStitcher();
    for (const f of streamed(answer, 4)) s.consume(f);
    expect(s.preamble()).toContain("HEADZZZ");
    s.reset();
    expect(s.preamble()).toBeNull();
    s.consume(frame(["⏺ a brand new turn."]));
    expect(s.preamble()).toBe("a brand new turn.");
    expect(s.preamble()).not.toContain("HEADZZZ");
  });

  test("no bullet ever seen yields null rather than guessing", () => {
    // Pump started mid-answer: we never saw where the turn began, so attributing
    // the visible block to the model would risk surfacing the user's own text.
    const s = new PaneStitcher();
    s.consume(frame(["  orphan prose with no bullet above it."]));
    expect(s.preamble()).toBeNull();
  });

  test("only the LAST bullet's prose is returned within one turn", () => {
    const s = new PaneStitcher();
    s.consume(frame(["⏺ earlier assistant note.", "", "⏺ the prose right before the question."], 12));
    expect(s.preamble()).toBe("the prose right before the question.");
  });

  test("memory is bounded", () => {
    const s = new PaneStitcher();
    for (let i = 0; i < MAX_LINES * 3; i++) s.consume(`unique prose line ${i}`);
    expect(s.size()).toBeLessThanOrEqual(MAX_LINES);
  });
});

describe("contentAboveSelector", () => {
  const withBox = [
    "⏺ the prose that is the preamble.",
    "─".repeat(78),
    " ☐ Choice",
    "",
    "Which one should we use?",
    "",
    "❯ 1. OPTION A",
    "     a long description that is indented prose and would otherwise be",
    "     recorded as part of the preamble.",
    "  2. OPTION B",
    "     another description.",
    "─".repeat(78),
    "  3. Chat about this",
    "",
    "Enter to select · ↑/↓ to navigate · Esc to cancel",
  ].join("\n");

  test("cuts the question box off, descriptions included", () => {
    const out = contentAboveSelector(withBox);
    expect(out).toContain("the prose that is the preamble");
    expect(out).not.toContain("Which one should we use?");
    expect(out).not.toContain("a long description");
    expect(out).not.toContain("OPTION A");
  });

  test("a pane with no selector is untouched", () => {
    const plain = "⏺ just prose\n  more prose";
    expect(contentAboveSelector(plain)).toBe(plain);
  });

  test("option descriptions never reach the preamble", () => {
    const s = new PaneStitcher();
    s.consume(frame(["⏺ the prose that is the preamble."]));
    s.consume(withBox);
    const out = s.preamble()!;
    expect(out).toBe("the prose that is the preamble.");
  });
});

// The agents write lists constantly, and the first cut of the chrome filter
// deleted every numbered one — "1. Cost at read time" is indistinguishable from
// a selector option by shape alone.
describe("the model's own list structure survives", () => {
  const prose = [
    "⏺ Here is the **recommendation**, with the `flags` that matter.",
    "",
    "  Three things drive the decision:",
    "",
    "  1. Cost at read time, which dominates and keeps dominating as the",
    "     library grows past the first few thousand assets.",
    "  2. Storage growth, which compounds.",
    "  3. Invalidation, which is the hard one.",
    "",
    "  - a bulleted point",
    "  - another bulleted point",
    "",
    "  ────────────────────────",
    "",
    "  Final note about the tradeoff.",
  ].join("\n");

  const out = (() => {
    const s = new PaneStitcher();
    s.consume(prose);
    return s.preamble()!;
  })();

  test("numbered list items are not eaten as selector options", () => {
    expect(out).toContain("1. Cost at read time");
    expect(out).toContain("2. Storage growth, which compounds.");
    expect(out).toContain("3. Invalidation, which is the hard one.");
  });

  test("each list item keeps its own line instead of collapsing into prose", () => {
    expect(out).toContain("\n2. Storage growth");
    expect(out).toContain("\n- another bulleted point");
  });

  test("a wrapped list item folds back into that item, not into a new one", () => {
    expect(out).toContain("dominates and keeps dominating as the library grows");
  });

  test("inline markdown is passed through verbatim for the client to render", () => {
    expect(out).toContain("**recommendation**");
    expect(out).toContain("`flags`");
  });

  test("a horizontal rule is dropped but its paragraph break is not", () => {
    expect(out).toContain("point\n\nFinal note");
  });

  test("a numbered list is still not mistaken for a live selector", () => {
    // No cursor → not a selector → nothing is cut.
    expect(contentAboveSelector("⏺ prose\n  1. one\n  2. two")).toContain("2. two");
    // Cursor → a real selector → cut.
    expect(contentAboveSelector("⏺ prose\n" + "─".repeat(78) + "\n❯ 1. Yes\n  2. No"))
      .not.toContain("Yes");
  });
});

describe("pump integration", () => {
  test("the idle→busy edge resets, but staying busy at a question does not", () => {
    const w = { stitcher: new PaneStitcher(), wasBusy: false };
    noteTurnEdge(w, true); // turn starts
    for (const f of streamed(answer, 4)) w.stitcher.consume(f);
    // Parked at the question: busy stays true across many polls. The preamble
    // must survive every one of them — this is the whole window that matters.
    for (let i = 0; i < 20; i++) noteTurnEdge(w, true);
    expect(w.stitcher.preamble()).toContain("HEADZZZ");
    // Answered, then a new turn begins.
    noteTurnEdge(w, false);
    noteTurnEdge(w, true);
    expect(w.stitcher.preamble()).toBeNull();
  });

  test("a truncated scrape is upgraded to the full preamble", () => {
    const w = { stitcher: new PaneStitcher(), wasBusy: true };
    for (const f of streamed(answer, 4)) w.stitcher.consume(f);
    const scraped = { question: "Which one?", options: [], context: "the closing paragraph, which is all a single capture can still show." };
    const out = withStitchedPreamble(scraped, w) as typeof scraped;
    expect(out.context).toContain("HEADZZZ");
    expect(out.question).toBe("Which one?");
  });

  test("an empty scrape is filled in", () => {
    const w = { stitcher: new PaneStitcher(), wasBusy: true };
    for (const f of streamed(answer, 4)) w.stitcher.consume(f);
    const out = withStitchedPreamble({ question: "Q", options: [] }, w) as { context?: string };
    expect(out.context).toContain("HEADZZZ");
  });

  test("never regresses a scrape that is already longer", () => {
    const w = { stitcher: new PaneStitcher(), wasBusy: true };
    w.stitcher.consume(frame(["⏺ short."]));
    const rich = { question: "Q", options: [], context: "a much longer context than the reconstruction currently holds" };
    expect((withStitchedPreamble(rich, w) as typeof rich).context).toBe(rich.context);
  });

  test("a structured transcript prompt is left alone", () => {
    const w = { stitcher: new PaneStitcher(), wasBusy: true };
    for (const f of streamed(answer, 4)) w.stitcher.consume(f);
    // No `question` key → not a pane prompt; must pass through untouched.
    const pending = { kind: "pending", tool: "AskUserQuestion" };
    expect(withStitchedPreamble(pending, w)).toBe(pending);
    expect(withStitchedPreamble(null, w)).toBeNull();
  });
});
