// Regression cover for "message never left the input box after retries".
//
// The composer region is found by pairing the two `─` border lines around it.
// Two real pane shapes defeated the original bottom-up pairing, and in BOTH
// the region parsed as the empty string — which deliver() reads as "our text
// never landed in the composer", so it retyped three times and failed the send
// while the keystrokes were in fact arriving perfectly:
//
//   1. A border drawn wider than the pane WRAPS into two consecutive rule
//      lines. The scan paired the wrap continuation with its own first half.
//   2. Claude's branch view labels the top border `(Branch) ──` — a label
//      PREFIX with only two trailing dashes, which `^─{3,}` never matched.
//
// The fixtures are verbatim `tmux capture-pane` tails from panes where this
// reproduced (cy-224353-78784, cy-222138-60277) and one healthy pane
// (cy-000654-54570) that must keep working.
import { test, expect } from "bun:test";
import { inputBoxFromPane, isRuleLine } from "./tmux";

const RULE_77 = "─".repeat(77);

// Healthy pane: plain borders, both exactly pane width.
const HEALTHY = [
  "                      Update available! Run: brew upgrade claude-code@latest",
  RULE_77,
  "❯ ",
  RULE_77,
  "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents           /rc",
  "",
].join("\n");

// Branch view + a bottom border that wrapped into an 8-dash continuation.
const BRANCH_WRAPPED = [
  "✻ Baked for 28s",
  "                      Update available! Run: brew upgrade claude-code@latest",
  " Check my ad performance so far and see if we need to adjust our strategy",
  "(Branch) ──",
  "❯ set up a loop to check every few hours",
  RULE_77,
  "─".repeat(8),
  "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents           /rc",
  "",
].join("\n");

// Same defect where the branch label trails a wrapped transcript line.
const BRANCH_INLINE = [
  "  of letting it parallax with the bag. (disable recaps in /config)",
  "                                      new task? /clear to save 413.4k tokens",
  " /Users/eugenechan/dev/personal/reelly/ads/assets/muse_parallax_ad.mov can",
  "you take a screenshot of e (Branch) ──",
  "❯ ",
  RULE_77,
  "─".repeat(36),
  "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents           /rc",
  "",
].join("\n");

test("healthy pane still yields its composer", () => {
  expect(inputBoxFromPane(HEALTHY)).toBe("❯ ");
});

test("branch view with a wrapped bottom border yields the draft, not empty", () => {
  // The whole bug in one assertion: this used to be "".
  expect(inputBoxFromPane(BRANCH_WRAPPED)).toBe(
    "❯ set up a loop to check every few hours",
  );
});

test("branch label trailing a wrapped transcript line still bounds the composer", () => {
  expect(inputBoxFromPane(BRANCH_INLINE)).toBe("❯ ");
});

test("a queued send's own text is findable in the branch composer", () => {
  // deliver() substring-matches its needle against this region; an empty region
  // is what stranded the send in a retype loop.
  const pane = BRANCH_WRAPPED.replace(
    "❯ set up a loop to check every few hours",
    "❯ ack test 2",
  );
  expect(inputBoxFromPane(pane)).toContain("ack test 2");
});

test("a multi-line draft between the borders is returned whole", () => {
  const pane = [
    "(Branch) ──",
    "❯ first line",
    "  second line",
    RULE_77,
    "─".repeat(8),
    "  ⏵⏵ bypass permissions on (shift+tab to cycle)",
    "",
  ].join("\n");
  expect(inputBoxFromPane(pane)).toBe("❯ first line\n  second line");
});

test("Codex single-line composer fallback is unaffected", () => {
  expect(inputBoxFromPane("some output\n› draft text\n")).toBe("draft text");
  // Numbered selector rows are prompts, not an editable composer.
  expect(inputBoxFromPane("choose:\n› 1. Yes\n")).toBeNull();
});

test("isRuleLine accepts every border Claude draws and rejects content", () => {
  expect(isRuleLine(RULE_77)).toBe(true);
  expect(isRuleLine("─".repeat(8))).toBe(true); // wrap continuation
  expect(isRuleLine("(Branch) ──")).toBe(true); // label prefix, 2 dashes
  expect(isRuleLine("──── my-session ──")).toBe(true); // centred label
  expect(isRuleLine(RULE_77 + "   ")).toBe(true); // trailing whitespace

  expect(isRuleLine("❯ draft")).toBe(false); // composer content
  expect(isRuleLine("  ⏵⏵ bypass permissions on (shift+tab to cycle)")).toBe(false);
  expect(isRuleLine("")).toBe(false);
  expect(isRuleLine("─")).toBe(false); // a lone dash is not a border
  // A composer line must never be mistaken for its own border.
  expect(isRuleLine("❯ see the diagram ──")).toBe(false);
  // Prose that merely ends in a rule is too long to be a label.
  expect(isRuleLine("a".repeat(60) + "──")).toBe(false);
});
