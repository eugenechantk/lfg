import { describe, expect, test } from "bun:test";
import { afterAll } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { recentMessages, recentUserTurns, unwrapPastedContent } from "./sessions.ts";

// Claude Code 2.1.278 began wrapping bracketed-paste input in
// `<pasted_content id="XXXX">…</pasted_content id="XXXX">`. lfg delivers every
// multi-line message from the phone by bracketed paste (`sendq` -> `tmuxPaste`,
// because `send-keys -l` submits at the first newline), so from 2.1.278 on the
// wrapper is on essentially every message Eugene sends from the client.
//
// Shapes below are verbatim from a real 2.1.278 transcript
// (~/.claude/projects/-Users-eugenechan-dev-personal-lfg/de8afc53-….jsonl).

const dir = mkdtempSync(join(tmpdir(), "lfg-pasted-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

let seq = 0;
function transcript(lines: unknown[]): string {
  const p = join(dir, `t${seq++}.jsonl`);
  writeFileSync(p, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  return p;
}

const REAL = '\n\n<pasted_content id="c020">\nDo u think we can simplify the architecture?\n\nOr not\n</pasted_content id="c020">\n';

describe("unwrapPastedContent", () => {
  test("keeps the body and drops the wrapper", () => {
    expect(unwrapPastedContent(REAL)).toBe(
      "Do u think we can simplify the architecture?\n\nOr not",
    );
  });

  test("leaves untagged text byte-for-byte alone", () => {
    const plain = "  But I can't get to the Air how can I login?\n";
    expect(unwrapPastedContent(plain)).toBe(plain);
  });

  test("keeps text typed around the pasted block", () => {
    const mixed = 'look at this:\n\n<pasted_content id="ab12">\nstack trace\n</pasted_content id="ab12">\n';
    expect(unwrapPastedContent(mixed)).toBe("look at this:\n\nstack trace");
  });

  test("unwraps the whitespace-collapsed form the title readers produce", () => {
    const collapsed = '<pasted_content id="c020"> Do u think we can simplify? </pasted_content id="c020">';
    expect(unwrapPastedContent(collapsed)).toBe("Do u think we can simplify?");
  });

  test("accepts a well-formed closing tag, in case that is corrected upstream", () => {
    expect(unwrapPastedContent('<pasted_content id="c020">\nbody\n</pasted_content>')).toBe("body");
  });

  test("unwraps several blocks in one turn", () => {
    const two =
      '<pasted_content id="aa">\nfirst\n</pasted_content id="aa">\nand\n<pasted_content id="bb">\nsecond\n</pasted_content id="bb">';
    expect(unwrapPastedContent(two)).toBe("first\nand\nsecond");
  });

  test("drops a tag left dangling by a truncated transcript window", () => {
    expect(unwrapPastedContent('<pasted_content id="c020">\nhalf a message')).toBe("half a message");
    expect(unwrapPastedContent('trailing half\n</pasted_content id="c020">')).toBe("trailing half");
  });

  test("does not touch the escaped form Claude Code writes when the user quotes a tag", () => {
    const quoted = 'why do we have <\\pasted_content id="c020">…</ tags now?';
    expect(unwrapPastedContent(quoted)).toBe(quoted);
  });
});

describe("transcript rendering", () => {
  test("the user bubble shows the body, not the wrapper", async () => {
    const p = transcript([
      { type: "user", timestamp: "2026-09-20T07:07:16.845Z", uuid: "u1", message: { role: "user", content: REAL } },
    ]);
    const msgs = await recentMessages(p, 10);
    expect(msgs.map((m) => m.text)).toEqual([
      "Do u think we can simplify the architecture?\n\nOr not",
    ]);
  });

  test("a content-array text block is unwrapped too", async () => {
    const p = transcript([
      {
        type: "user",
        timestamp: "2026-09-20T07:07:16.845Z",
        uuid: "u2",
        message: { role: "user", content: [{ type: "text", text: REAL }] },
      },
    ]);
    const msgs = await recentMessages(p, 10);
    expect(msgs.map((m) => m.text)).toEqual([
      "Do u think we can simplify the architecture?\n\nOr not",
    ]);
  });

  // The regression that mattered: `userTurnFromLine` discards any turn whose
  // text starts with "<" as Claude Code machinery (`<command-name>`,
  // `<local-command-stdout>`). A wrapped turn starts with "<pasted_content",
  // so from 2.1.278 every multi-line phone message silently vanished from
  // session titles and the user-turn digest.
  test("a wrapped turn still counts as a user turn for titles and the digest", async () => {
    const p = transcript([
      { type: "user", message: { content: REAL } },
    ]);
    expect(await recentUserTurns(p, 5)).toEqual([
      "Do u think we can simplify the architecture? Or not",
    ]);
  });

  test("genuine Claude Code machinery is still dropped", async () => {
    const p = transcript([
      { type: "user", message: { content: "<command-name>/clear</command-name>" } },
      { type: "user", message: { content: REAL } },
    ]);
    expect(await recentUserTurns(p, 5)).toEqual([
      "Do u think we can simplify the architecture? Or not",
    ]);
  });
});
