import { describe, expect, it } from "bun:test";
import { claudeModelSwitchBlocker } from "./claude-model-switch.ts";

describe("Claude model switch relaunch policy", () => {
  it("allows an idle session to relaunch on the requested model", () => {
    expect(claudeModelSwitchBlocker({ busy: false, queued: false, prompting: false })).toBeNull();
  });

  it("does not kill active work, queued sends, or an unanswered prompt", () => {
    expect(claudeModelSwitchBlocker({ busy: true, queued: false, prompting: false }))
      .toBe("Wait for Claude to finish its current turn before switching models.");
    expect(claudeModelSwitchBlocker({ busy: false, queued: true, prompting: false }))
      .toBe("Wait for queued messages to finish before switching models.");
    expect(claudeModelSwitchBlocker({ busy: false, queued: false, prompting: true }))
      .toBe("Answer Claude's current prompt before switching models.");
  });
});
