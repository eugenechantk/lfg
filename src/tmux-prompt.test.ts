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

  test("no preamble bullet → context undefined", () => {
    const p = parsePrompt(bareSelectorPane);
    expect(p).not.toBeNull();
    expect(p!.context).toBeUndefined();
  });
});
