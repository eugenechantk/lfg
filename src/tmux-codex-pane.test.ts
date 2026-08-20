// Regression cover for codex sends dying as "queued" → "not sent" (and, on long
// sessions, "message never left the input box after retries").
//
// src/tmux.ts's pane parsers were written against Claude's TUI. Codex draws a
// different one, and the Claude-shaped scans mis-read it two ways:
//
//   * no bordered composer, so busyChromeRegions fell back to a 6-line tail —
//     too short once codex renders its own queue notice, which pushes the
//     `Working (…)` meter out of the window. A busy codex then read IDLE, which
//     made reconcileQueued re-drive the message twice and fail it.
//   * codex prints rule lines anyway (`─ Worked for 1m 17s ─` after every turn,
//     plus plain runs in agent output). With two on screen the composer scan
//     paired them and returned the AGENT'S OUTPUT as "the composer".
//
// Every fixture below is a verbatim `tmux capture-pane` tail: the codex ones
// from scratch session `sendqrepro` and live session `codexy-173947-78289`, the
// Claude ones from the shapes already covered in tmux-composer-border.test.ts.
// See .claude/diagnosis-codex-send-not-sent-20260806.md.
import { test, expect, describe } from "bun:test";
import {
  backgroundProcessCount,
  inputBoxFromPane,
  isBusy,
  codexComposerIndex,
} from "./tmux";

const RULE_77 = "─".repeat(77);

// Busy codex, mid tool call, with codex's OWN queue notice on screen. This is
// the exact frame that read idle: the meter is 6 lines above the composer.
const CODEX_BUSY_WITH_QUEUE = [
  "• Running the requested command now.",
  "",
  "• Working (1m 16s • esc to interrupt) · 1 background terminal running · /ps to",
  "",
  "• Messages to be submitted after next tool call (press esc to interrupt and se",
  "  immediately)",
  "  ↳ run the shell command: sleep 120; then reply DONE2",
  "",
  "› Write tests for @filename",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/lfg-sendq-repro",
  "",
].join("\n");

// Busy codex with nothing queued — the meter sits just above the composer, so
// even the old 6-line tail caught this one. Must keep working.
const CODEX_BUSY_PLAIN = [
  "• Running the requested command now.",
  "",
  "• Working (11s • esc to interrupt) · 1 background terminal running · /ps to vie…",
  "",
  "› Write tests for @filename",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/lfg-sendq-repro",
  "",
].join("\n");

// Codex can finish its own response while a spawned shell keeps running. The
// background terminal is still session work even though the main meter is idle.
const CODEX_IDLE_WITH_BACKGROUND = [
  "• The server is ready; leaving it running for the preview.",
  "",
  "─ Worked for 8s " + "─".repeat(63),
  "",
  "  2 background terminals running · /ps to view · /stop to close",
  "",
  "› Write tests for @filename",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/lfg-sendq-repro",
  "",
].join("\n");

// Idle codex right after a turn: one `─ Worked for … ─` separator.
const CODEX_IDLE_WORKED = [
  "• LONGACK",
  "",
  "─ Worked for 2m 10s " + "─".repeat(57),
  "",
  "",
  "› Write tests for @filename",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/lfg-sendq-repro",
  "",
].join("\n");

// Idle codex on a long session: THREE rule lines. The composer scan paired the
// bottom two and returned the assistant's summary as "the composer".
const CODEX_MULTI_RULE = [
  "─".repeat(60),
  "  Actions taken",
  "",
  "  - Restarted /Applications/lfg.app.",
  "─".repeat(60),
  "  Verification run",
  "",
  "  - Live window inspection: PASS.",
  "  - Installed binary: 25 tests passed.",
  "  - Installed code signature: valid.",
  "",
  "─ Worked for 1m 17s " + "─".repeat(57),
  "",
  "",
  "› Summarize recent commits",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/lfg · Main [default]",
  "",
].join("\n");

// The composer actually holding a draft the send queue typed.
const CODEX_TYPED_DRAFT = CODEX_IDLE_WORKED.replace(
  "› Write tests for @filename",
  "› reply with just the word FOLLOWUP",
);

// The reported failed follow-up from codexy-153628-89613. Codex renders pasted
// paragraphs as continuation lines, not a collapsed "[Pasted text]" chip. The
// send queue's 48-character confirmation prefix crosses from the first line
// into the second, so returning only the `›` line makes a successful paste look
// absent and every retry appends another copy.
const CODEX_MULTILINE_DRAFT = [
  "─ Worked for 1m 17s " + "─".repeat(57),
  "",
  "",
  "› I think the character emotions is too sad",
  "",
  "  Is it because my motion reference I have no emotions? Or is it my character",
  "  reference has no emotions",
  "",
  "  I want the emotions to be energetic and lively",
  "",
  "  gpt-5.6-sol high fast · ~/dev/personal/fiftyworkout",
  "",
].join("\n");

// A codex selector: numbered `›` rows are options, not somewhere to type.
const CODEX_SELECTOR = [
  "  Choose an option",
  "",
  "› 1. Yes, proceed",
  "  2. No, cancel",
  "",
].join("\n");

// Claude shapes — must be untouched by the codex branch.
const CLAUDE_IDLE = [
  "                      Update available! Run: brew upgrade claude-code@latest",
  RULE_77,
  "❯ ",
  RULE_77,
  "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents           /rc",
  "",
].join("\n");

const CLAUDE_BUSY = [
  "✶ Crunching… (5m 50s · ↓ 2.2k tokens)",
  RULE_77,
  "❯ ",
  RULE_77,
  "  ⏵⏵ bypass permissions on · esc to interrupt · ← for agents            /rc",
  "",
].join("\n");

describe("codex busy detection", () => {
  test("busy WITH codex's queue notice reads busy (the reported bug)", () => {
    // Was false: the meter fell outside the 6-line tail, so lfg believed a
    // mid-turn codex was idle, re-drove the message twice, then failed it.
    expect(isBusy(CODEX_BUSY_WITH_QUEUE)).toBe(true);
  });

  test("plain busy codex still reads busy", () => {
    expect(isBusy(CODEX_BUSY_PLAIN)).toBe(true);
  });

  test("background terminals keep an otherwise idle codex session busy", () => {
    expect(backgroundProcessCount(CODEX_IDLE_WITH_BACKGROUND)).toBe(2);
    expect(isBusy(CODEX_IDLE_WITH_BACKGROUND)).toBe(true);
  });

  test("background terminal copy in agent prose is not counted", () => {
    expect(backgroundProcessCount(CODEX_IDLE_WORKED.replace(
      "• LONGACK",
      "• The requested label is ‘2 background terminals running’.",
    ))).toBe(0);
  });

  test("idle codex reads idle", () => {
    expect(isBusy(CODEX_IDLE_WORKED)).toBe(false);
    expect(isBusy(CODEX_MULTI_RULE)).toBe(false);
  });

  test("agent prose quoting the interrupt hint does not pin codex busy", () => {
    // The codex chrome region isn't fenced by a border, and this repo's own
    // sessions discuss busy detection constantly — hence the tighter markers.
    const quoting = CODEX_IDLE_WORKED.replace(
      "• LONGACK",
      "• The footer reads \"esc to interrupt\" while a turn is in flight.",
    );
    expect(isBusy(quoting)).toBe(false);
  });
});

describe("codex composer", () => {
  test("multi-rule pane yields the composer, not the agent's output", () => {
    // Was the assistant's summary text ("• The app was still running…").
    expect(inputBoxFromPane(CODEX_MULTI_RULE)).toBe("Summarize recent commits");
  });

  test("a typed draft is visible to the send queue", () => {
    expect(inputBoxFromPane(CODEX_TYPED_DRAFT)).toBe("reply with just the word FOLLOWUP");
  });

  test("a multiline draft includes Codex continuation lines", () => {
    expect(inputBoxFromPane(CODEX_MULTILINE_DRAFT)).toBe([
      "I think the character emotions is too sad",
      "",
      "Is it because my motion reference I have no emotions? Or is it my character",
      "reference has no emotions",
      "",
      "I want the emotions to be energetic and lively",
    ].join("\n"));
  });

  test("busy pane's composer is still readable", () => {
    expect(inputBoxFromPane(CODEX_BUSY_WITH_QUEUE)).toBe("Write tests for @filename");
  });

  test("a numbered selector is not an editable composer", () => {
    expect(codexComposerIndex(CODEX_SELECTOR.split("\n"))).toBeNull();
    expect(inputBoxFromPane(CODEX_SELECTOR)).toBeNull();
  });
});

describe("claude panes are unaffected", () => {
  test("claude shapes are not detected as codex", () => {
    expect(codexComposerIndex(CLAUDE_IDLE.split("\n"))).toBeNull();
    expect(codexComposerIndex(CLAUDE_BUSY.split("\n"))).toBeNull();
  });

  test("claude busy/idle unchanged", () => {
    expect(isBusy(CLAUDE_BUSY)).toBe(true);
    expect(isBusy(CLAUDE_IDLE)).toBe(false);
  });

  test("claude composer unchanged", () => {
    expect(inputBoxFromPane(CLAUDE_IDLE)).toBe("❯ ");
  });
});
