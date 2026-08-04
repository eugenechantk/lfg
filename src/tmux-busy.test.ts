import { test, expect, describe } from "bun:test";
import { isBusy } from "./tmux.ts";

// The pane footer rotates through hints mid-turn; "esc to interrupt" is only
// sometimes present. These panes deliberately use a NON-"esc" footer so the
// test exercises the meter signal, not the footer fallback.
const footer = "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents";
const composer = ["─────", "❯ ", "─────", footer].join("\n");
const pane = (spinnerLine: string) => `${spinnerLine}\n${composer}`;

describe("isBusy", () => {
  test("normal token meter → busy", () => {
    expect(isBusy(pane("✢ Cerebrating… (2m 34s · ↓ 9.7k tokens)"))).toBe(true);
  });

  // Regression: extended-thinking meter has no "tokens" word. Previously this
  // read idle whenever the footer wasn't on "esc to interrupt", firing a
  // spurious "Finished" push while the agent was still thinking.
  test("extended-thinking meter (no 'tokens') → busy", () => {
    expect(isBusy(pane("✶ Authoring design artboards… (5m 56s · still thinking with medium effort)"))).toBe(true);
  });

  test("seconds-only meter → busy", () => {
    expect(isBusy(pane("· Working… (45s · ↑ 1.2k tokens)"))).toBe(true);
  });

  test("zero-minute meter → busy", () => {
    expect(isBusy(pane("· Working… (5m 0s · ↓ 15.7k tokens)"))).toBe(true);
  });

  test("first-frame footer hint → busy (fallback)", () => {
    const f = "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt";
    expect(isBusy(`✻ Thinking…\n─────\n❯ \n─────\n${f}`)).toBe(true);
  });

  test("finished turn (past-tense summary, no live clock) → idle", () => {
    expect(isBusy(pane("✻ Baked for 18m 45s"))).toBe(false);
  });

  test("plain idle composer → idle", () => {
    expect(isBusy(`⏺ Done.\n${composer}`)).toBe(false);
  });

  // A stray "(3s)" in transcript output must not be mistaken for the live meter
  // (no "·" separator → not the clock).
  test("stray parenthesized duration in output → idle", () => {
    expect(isBusy(pane("⏺ The build completed (3s) successfully."))).toBe(false);
  });
});

// Regression: both markers used to be tested against the WHOLE pane, so an
// agent that merely PRINTED one of them pinned itself busy forever. This bit a
// real session (cy-163217-77946) whose own answer explained busy detection —
// the phrase sat in the transcript, paneBusy stayed true past its TTL refresh
// after refresh, and the client showed "running" indefinitely with the send
// queue holding messages for an idle session.
describe("isBusy ignores the transcript above the composer", () => {
  const idleFooter = "  ⏵⏵ bypass permissions on (shift+tab to cycle) · ← for agents";
  const busyFooter = "  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt · ← for …";
  const withTranscript = (body: string, footer: string) =>
    [body, "✻ Churned for 3m 54s", "─────", "❯ ", "─────", footer, "  /rc"].join("\n");

  test("agent prose containing 'esc to interrupt' → idle", () => {
    const body = [
      "⏺ A session that is still live but hung — pane alive, still showing",
      "  esc to interrupt — stays busy: true legitimately, because the pane is",
      "  the authority and it still claims to be running.",
    ].join("\n");
    expect(isBusy(withTranscript(body, idleFooter))).toBe(false);
  });

  test("agent prose quoting a live meter → idle", () => {
    const body = '⏺ The meter renders as "✶ Crunching… (5m 50s · ↓ 2.2k tokens)".';
    expect(isBusy(withTranscript(body, idleFooter))).toBe(false);
  });

  // The prose must not suppress a genuine signal either.
  test("prose mentions the hint while the footer really shows it → busy", () => {
    const body = "⏺ We detect a turn by scraping esc to interrupt from the footer.";
    expect(isBusy(withTranscript(body, busyFooter))).toBe(true);
  });

  // Real capture shape: the meter is separated from the composer by the tip and
  // update-notice lines, so the lookback window has to clear them.
  test("meter above tip + update notice → busy", () => {
    const p = [
      "⏺ Running the build.",
      "",
      "✶ Crunching… (5m 50s · ↓ 2.2k tokens)",
      "  ⎿  Tip: Paste images into Claude Code using control+v (not cmd+v!)",
      "                      Update available! Run: brew upgrade claude-code@latest",
      "─────",
      "❯ ",
      "─────",
      idleFooter,
      "  /rc",
    ].join("\n");
    expect(isBusy(p)).toBe(true);
  });

  // A wide border wraps into two consecutive rule lines; collapsing the run is
  // what keeps the lookback window anchored to the right side of the composer.
  test("wrapped composer borders → meter still found", () => {
    const p = [
      "✶ Crunching… (45s · ↓ 1.2k tokens)",
      "─────",
      "──",
      "❯ ",
      "─────",
      "──",
      idleFooter,
    ].join("\n");
    expect(isBusy(p)).toBe(true);
  });

  // Codex renders a single `›` prompt line with no border box: fall back to the
  // pane tail, never the whole scrollback.
  test("borderless pane falls back to the tail, not the scrollback", () => {
    const stale = Array.from({ length: 30 }, () => "⏺ mentions esc to interrupt").join("\n");
    expect(isBusy(`${stale}\n${["", "", "", "", "", "› "].join("\n")}`)).toBe(false);
    expect(isBusy(`⏺ done\n› working (12s · ↓ 1k tokens)`)).toBe(true);
  });
});
