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
