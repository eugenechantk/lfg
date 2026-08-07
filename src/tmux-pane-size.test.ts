// The pane geometry that makes a question's preamble visible at all.
//
// Claude Code does not flush the assistant turn containing an interactive tool
// to its transcript until the question is answered, and it runs in the
// alternate screen (no scrollback). So the ONLY live copy of the prose the
// model wrote before asking is whatever currently fits on the tmux pane. At
// tmux's default 80x24 it does not fit, and the client showed a mid-sentence
// fragment or nothing — "the response before the question is cut off".
//
// These tests pin the two halves of the fix that are pure: every session lfg
// spawns asks for a tall pane, and the context scraper is willing to walk far
// enough up a tall pane to actually use it.
import { test, expect, describe } from "bun:test";
import {
  managedSessionArgv,
  paneSizeArgs,
  parsePrompt,
  PANE_COLS,
  PANE_ROWS,
} from "./tmux.ts";

describe("pane geometry", () => {
  test("is tall enough to hold a full turn plus a selector box", () => {
    // 24 rows cannot fit even a two-paragraph preamble + an AskUserQuestion box.
    expect(PANE_ROWS).toBeGreaterThanOrEqual(120);
  });

  test("paneSizeArgs are tmux new-session size flags", () => {
    expect(paneSizeArgs()).toEqual(["-x", String(PANE_COLS), "-y", String(PANE_ROWS)]);
  });

  test("managed sessions are spawned with the size, before -s", () => {
    const argv = managedSessionArgv({ name: "lfg-abc", cwd: "/tmp" });
    const y = argv.indexOf("-y");
    expect(argv[y + 1]).toBe(String(PANE_ROWS));
    // tmux only records default-size from flags given to new-session itself,
    // so the size must precede the session name / command.
    expect(y).toBeLessThan(argv.indexOf("-s"));
  });
});

// Build a pane whose assistant preamble is `bodyLines` rows tall, with the
// "⏺" bullet at the very top — i.e. exactly what a tall pane preserves and a
// 24-row pane destroys.
function paneWithPreamble(bodyLines: number): string {
  const lines = ["", "⏺ FIRST-LINE-OF-THE-ANSWER begins here."];
  for (let i = 0; i < bodyLines; i++) lines.push(`  continuation line ${i}`);
  lines.push(
    "─".repeat(80),
    " ☐ Approach",
    "",
    "Which option should we go with?",
    "",
    "❯ 1. OPTION ALPHA",
    "     Migrate up front.",
    "  2. OPTION BETA",
    "     Adapter now.",
    "  3. Type something.",
    "─".repeat(80),
    "  4. Chat about this",
    "",
    "Enter to select · ↑/↓ to navigate · Esc to cancel",
  );
  return lines.join("\n");
}

describe("contextAbovePrompt scan depth", () => {
  test("recovers a preamble far longer than the old 40-line cap", () => {
    // 120 body rows fits on a PANE_ROWS pane but blew past the old cap, which
    // silently clipped the top — the same visible symptom as a short pane.
    const p = parsePrompt(paneWithPreamble(120));
    expect(p).not.toBeNull();
    expect(p!.context ?? "").toContain("FIRST-LINE-OF-THE-ANSWER");
    expect(p!.context ?? "").toContain("continuation line 119");
  });

  test("still reaches the bullet at the full pane height", () => {
    const p = parsePrompt(paneWithPreamble(PANE_ROWS - 20));
    expect(p!.context ?? "").toContain("FIRST-LINE-OF-THE-ANSWER");
  });

  test("a clipped pane yields a fragment — the bug this geometry prevents", () => {
    // Simulate the old 24-row pane: the bullet has scrolled off entirely.
    const clipped = paneWithPreamble(200).split("\n").slice(-24).join("\n");
    const p = parsePrompt(clipped, "the user's unrelated prompt");
    expect(p!.context ?? "").not.toContain("FIRST-LINE-OF-THE-ANSWER");
  });
});
