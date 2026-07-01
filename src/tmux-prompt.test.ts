import { test, expect, describe } from "bun:test";
import { parsePrompt } from "./tmux.ts";

// A real AskUserQuestion selector as captured from a live tmux pane. The
// assistant preamble ("⏺ …", wrapped) sits above the box's top separator; the
// header chip, question, and numbered options are inside the box. The whole
// turn is NOT in the transcript JSONL until answered, so this pane is the only
// live source of the preamble — parsePrompt must surface it as `context`.
const askUserQuestionPane = [
  "",
  "❯ Ask me the deployment question again now: first write one sentence of context",
  '  as text ("Here is the current status..."), then call AskUserQuestion.',
  "",
  "⏺ Here is the current status and I need you to pick the deployment path before I",
  "  continue.",
  "────────────────────────────────────────────────────────────────────────────────",
  " ☐ Deploy",
  "",
  "Which deployment approach should we use?",
  "",
  "❯ 1. Local Fastlane first",
  "     Prove signing locally before CI",
  "  2. GitHub Actions now",
  "     Go straight to remote CI with match",
  "  3. Manual upload",
  "     One-off Transporter upload, no pipeline",
  "  4. Type something.",
  "────────────────────────────────────────────────────────────────────────────────",
  "  5. Chat about this",
  "",
  "Enter to select · ↑/↓ to navigate · Esc to cancel",
].join("\n");

// A permission prompt with no assistant preamble bullet above the box — context
// must be undefined, not a stray scrape of unrelated lines.
const bareSelectorPane = [
  "────────────────────────────────────────────────────────────────────────────────",
  " Do you want to proceed?",
  "",
  "❯ 1. Yes",
  "  2. No",
  "────────────────────────────────────────────────────────────────────────────────",
  "Enter to select · ↑/↓ to navigate · Esc to cancel",
].join("\n");

describe("parsePrompt context scrape", () => {
  test("captures the wrapped assistant preamble above the selector", () => {
    const p = parsePrompt(askUserQuestionPane);
    expect(p).not.toBeNull();
    expect(p!.question).toBe("Which deployment approach should we use?");
    expect(p!.options.map((o) => o.label)).toEqual([
      "Local Fastlane first",
      "GitHub Actions now",
      "Manual upload",
      "Type something.",
      "Chat about this",
    ]);
    // Unwrapped, bullet stripped, wrap-joined.
    expect(p!.context).toBe(
      "Here is the current status and I need you to pick the deployment path before I continue.",
    );
  });

  // Pane-fallback (used in the window before Claude flushes the tool call to the
  // transcript) must capture the FULL wrapped question and each option's
  // description — not just the last question line with bare labels.
  test("captures a wrapped question and per-option descriptions", () => {
    const pane = [
      "  ...tail of the user prompt that scrolled up",
      "────────────────────────────────────────────────────────────────────────────────",
      " ☐ Deploy",
      "",
      "Given the current signing setup and the fact that we have not yet proven the",
      "archive works locally, which end-to-end deployment approach do you want to",
      "commit to for shipping this build to TestFlight today?",
      "",
      "❯ 1. Local Fastlane first, then wire up GitHub Actions CI later",
      "     Prove signing and archive locally on your Mac before adding remote CI.",
      "     Safest, easiest to debug.",
      "  2. Full GitHub Actions CI now",
      "     Go straight to remote CI with match. More moving parts and harder to debug",
      "     the first run.",
      "  3. Type something.",
      "────────────────────────────────────────────────────────────────────────────────",
      "  4. Chat about this",
      "Enter to select · ↑/↓ to navigate · Esc to cancel",
    ].join("\n");
    const p = parsePrompt(pane);
    expect(p).not.toBeNull();
    expect(p!.question).toBe(
      "Given the current signing setup and the fact that we have not yet proven the archive works locally, which end-to-end deployment approach do you want to commit to for shipping this build to TestFlight today?",
    );
    expect(p!.options[0]).toMatchObject({
      index: 1,
      label: "Local Fastlane first, then wire up GitHub Actions CI later",
      description:
        "Prove signing and archive locally on your Mac before adding remote CI. Safest, easiest to debug.",
    });
    expect(p!.options[1]).toMatchObject({
      index: 2,
      label: "Full GitHub Actions CI now",
      description:
        "Go straight to remote CI with match. More moving parts and harder to debug the first run.",
    });
    // The "Type something." affordance carries no description.
    expect(p!.options[2].description).toBeUndefined();
  });

  test("no preamble bullet → context undefined", () => {
    const p = parsePrompt(bareSelectorPane);
    expect(p).not.toBeNull();
    expect(p!.context).toBeUndefined();
  });

  // When the "⏺" bullet has scrolled off, the indented lines above the box are
  // ambiguous — they could be a scrolled-off assistant preamble OR the user's
  // own (scrolled-off) prompt. We must NOT surface them as context, or the panel
  // echoes the user's prompt back as fake "explanation". Require the bullet.
  test("bullet scrolled off → context undefined (never echo the user prompt)", () => {
    const pane = [
      '  ...options (1) label "Local Fastlane first" description "prove signing',
      '  locally", (2) label "GitHub Actions now". Wait for my answer.',
      "────────────────────────────────────────────────────────────────────────────────",
      " ☐ Deploy",
      "",
      "Which deployment path?",
      "",
      "❯ 1. Local Fastlane",
      "     prove signing locally",
      "  2. GitHub Actions",
      "     remote CI",
      "────────────────────────────────────────────────────────────────────────────────",
      "  3. Chat about this",
      "Enter to select · ↑/↓ to navigate · Esc to cancel",
    ].join("\n");
    const p = parsePrompt(pane);
    expect(p).not.toBeNull();
    expect(p!.context).toBeUndefined();
  });
});
