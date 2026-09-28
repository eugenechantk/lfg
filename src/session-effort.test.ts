import { describe, expect, it } from "bun:test";
import {
  codexEffortFromPane,
  codexReasoningOption,
  effortSwitchBlocker,
  launchFlag,
  liveLaunchSetting,
  validateEffortForAgent,
} from "./session-effort.ts";

describe("effort validation", () => {
  it("accepts each CLI's levels and nothing that could reach a shell", () => {
    expect(validateEffortForAgent("claude", "xhigh")).toBeNull();
    expect(validateEffortForAgent("codex", "ultra")).toBeNull();
    // `--effort` has no ultra; Codex models do.
    expect(validateEffortForAgent("claude", "ultra")).toMatch(/does not accept/);
    for (const bad of ["", "High", "high; rm -rf ~", "--model", "auto"]) {
      expect(validateEffortForAgent("codex", bad)).toMatch(/unknown effort/);
    }
  });
});

describe("launch flags", () => {
  it("reads both spellings and ignores lookalikes", () => {
    expect(launchFlag("claude --model opus --effort max", "--effort")).toBe("max");
    expect(launchFlag("claude --effort=low --resume x", "--effort")).toBe("low");
    expect(launchFlag("claude --model claude-opus-5 --effort high", "--model")).toBe("claude-opus-5");
    expect(launchFlag("claude --dangerously-skip-permissions", "--effort")).toBeNull();
    expect(launchFlag("claude --effortless x", "--effort")).toBeNull();
  });
});

describe("live Claude setting precedence", () => {
  const started = 1_000_000;
  it("trusts the transcript once this process has written a turn", () => {
    // An in-TUI /effort after launch shows up here and must beat the stale flag.
    expect(liveLaunchSetting({ flag: "max", transcript: "low", transcriptAt: started + 5, processStartedAt: started })).toBe("low");
  });
  it("trusts the launch flag right after a relaunch, before any new turn", () => {
    expect(liveLaunchSetting({ flag: "max", transcript: "high", transcriptAt: started - 5, processStartedAt: started })).toBe("max");
  });
  it("falls back to the older transcript when the process has no flag", () => {
    expect(liveLaunchSetting({ flag: null, transcript: "high", transcriptAt: started - 5, processStartedAt: started })).toBe("high");
    expect(liveLaunchSetting({ flag: null, transcript: null, transcriptAt: null, processStartedAt: started })).toBeNull();
  });
  it("uses the transcript when the process start is unknown", () => {
    expect(liveLaunchSetting({ flag: "max", transcript: "low", transcriptAt: null, processStartedAt: null })).toBe("low");
  });
});

describe("Codex effort from the footer", () => {
  it("reads the level after the model", () => {
    expect(codexEffortFromPane("› Ask Codex to do anything\n  GPT-6-Sol high fast · ~/dev/inbox        ⚠ 2 warnings · f2 to view\n")).toBe("high");
    expect(codexEffortFromPane("  GPT-6-Sol xhigh fast · ~/dev/inbox")).toBe("xhigh");
    expect(codexEffortFromPane("  GPT-5.6-Sol ultra · ~/project · Main [default]")).toBe("ultra");
  });
  it("returns null while the footer is animating or hidden by a picker", () => {
    expect(codexEffortFromPane("» Ask Codex to do anything\n                    U L T R A                ⚠ 2 warnings · f2 to view")).toBeNull();
    expect(codexEffortFromPane("  Select Reasoning Level for GPT-6-Sol\n  enter default · s session · esc back")).toBeNull();
    expect(codexEffortFromPane("  GPT-6-Sol fast · ~/dev/inbox")).toBeNull();
    expect(codexEffortFromPane(null)).toBeNull();
  });
});

describe("Codex reasoning picker rows", () => {
  it("maps the rows codex-cli 0.156 renders", () => {
    expect(codexReasoningOption("Low               Fast responses with lighter reasoning")).toBe("low");
    expect(codexReasoningOption("Medium (default)  Balances speed and reasoning depth")).toBe("medium");
    expect(codexReasoningOption("High (current)    Greater reasoning depth")).toBe("high");
    expect(codexReasoningOption("Extra high (current)  Extra high reasoning depth")).toBe("xhigh");
    expect(codexReasoningOption("More reasoning… (current)  Max and Ultra consume usage limits faster")).toBe("more");
    expect(codexReasoningOption("Max    For difficult problems · higher usage")).toBe("max");
    expect(codexReasoningOption("Ultra  For demanding work using multiple agents")).toBe("ultra");
    expect(codexReasoningOption("GPT-6-Sol (current)    Workhorse model")).toBeNull();
  });
});

describe("effort change guard", () => {
  it("refuses while the session is working, queued or asking", () => {
    expect(effortSwitchBlocker("claude", { busy: true, queued: false, prompting: false })).toMatch(/Claude to finish/);
    expect(effortSwitchBlocker("codex", { busy: false, queued: true, prompting: false })).toMatch(/queued messages/);
    expect(effortSwitchBlocker("codex", { busy: false, queued: false, prompting: true })).toMatch(/Answer Codex/);
    expect(effortSwitchBlocker("claude", { busy: false, queued: false, prompting: false })).toBeNull();
  });
});
