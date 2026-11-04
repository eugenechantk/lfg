import { expect, test } from "bun:test";
import { chatNotificationInstructions, withNotificationInstructions } from "./session-notification-instructions";

// Alerts must say what the session built or fixed. Agents wrote "Build N is on
// TestFlight" and "Pro updated and verified" while the instruction only asked
// for "the concrete result"; the rule and its example are the fix.
test("agents are told to lead alerts with what was built or fixed", () => {
  const managed = withNotificationInstructions("Base prompt.", "lfg-abc123");
  expect(managed.startsWith("Base prompt.\n\n")).toBe(true);
  expect(managed).toContain("Start every message with what this session built or which problem it solved");
  expect(managed).toContain("not the steps, builds or checks");
  expect(managed).toContain("Describe the work done only when it built or fixed nothing.");
  expect(managed).toContain('"lfg-abc123"');
  expect(chatNotificationInstructions("chat-1")).toContain("Start with what was built or which problem was solved");
});
