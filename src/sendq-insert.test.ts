// Submit policy: type, Enter, let the transcript judge. No reading of the
// composer may block the Enter or fail the send — six weeks of sendq.log
// showed the pre-Enter confirmation rescued one send and failed 54 (see the
// submitOutcome comment in sendq.ts and
// .claude/feature/send-submit-transcript-authority.md).
import { describe, expect, test } from "bun:test";
import { submitOutcome } from "./sendq.ts";

describe("submitOutcome", () => {
  test("transcript growth is delivered, whatever the composer says", () => {
    for (const held of [true, false, null]) {
      expect(submitOutcome(true, held, false)).toBe("delivered");
      expect(submitOutcome(true, held, true)).toBe("delivered");
    }
  });

  test("draft gone from a readable composer -> queued (busy Claude took it)", () => {
    expect(submitOutcome(false, false, false)).toBe("queued");
  });

  test("unreadable composer is not evidence of failure -> queued", () => {
    // A scrolled view, an overlay opened by the submit, or a border shape the
    // parser can't follow. Treating this as failure is what stranded sends.
    expect(submitOutcome(false, null, false)).toBe("queued");
  });

  test("a slash command that left the box is delivered, not queued", () => {
    // /clear, /model … execute at once and never surface as a user turn.
    expect(submitOutcome(false, false, true)).toBe("delivered");
    expect(submitOutcome(false, null, true)).toBe("delivered");
  });

  test("only a POSITIVE 'still in the box' reading keeps watching", () => {
    expect(submitOutcome(false, true, false)).toBe("hold");
    expect(submitOutcome(false, true, true)).toBe("hold");
  });

  test("no observation ever yields a failure", () => {
    const all: string[] = [];
    for (const grew of [true, false])
      for (const held of [true, false, null])
        for (const cmd of [true, false]) all.push(submitOutcome(grew, held, cmd));
    expect(all).not.toContain("failed");
  });
});
