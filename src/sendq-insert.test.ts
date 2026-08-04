// Insertion-confirmation policy: an unreadable composer is not evidence that
// the send failed. See .claude/feature/send-insert-unreadable-composer.md —
// treating null as failure is what stranded sends ("message never left the
// input box after retries") whose keystrokes had landed perfectly.
import { describe, expect, test } from "bun:test";
import { insertionOutcome } from "./sendq.ts";

describe("insertionOutcome", () => {
  test("composer holds our draft -> settled", () => {
    expect(insertionOutcome(true, false)).toBe("settled");
    // An open selector is irrelevant once we can see our own draft.
    expect(insertionOutcome(true, true)).toBe("settled");
  });

  test("composer is readable and our draft is absent -> retry", () => {
    // This is the only real evidence of a failed insertion: we could read the
    // box and our text was not in it.
    expect(insertionOutcome(false, false)).toBe("retry");
  });

  test("composer is unreadable -> submit unconfirmed, let the transcript judge", () => {
    // The regression this guards: a scrolled output view, an overlay, or an
    // unrecognised border shape (cf. the `(Branch) ──` bug) makes the parser
    // return null. That used to clear + retype 3x and fail.
    expect(insertionOutcome(null, false)).toBe("unconfirmed");
  });

  test("composer unreadable but a selector is open -> retry, never Enter into it", () => {
    // Enter here would pick an option in a permission/question dialog rather
    // than submit a message, so an unreadable composer is not enough.
    expect(insertionOutcome(null, true)).toBe("retry");
  });

  test("only an explicit false ever reports insertion failure", () => {
    const outcomes = [
      insertionOutcome(true, false),
      insertionOutcome(null, false),
    ];
    expect(outcomes.every((o) => o !== "retry")).toBe(true);
  });
});
