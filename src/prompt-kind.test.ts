import { describe, expect, test } from "bun:test";
import { parsePrompt } from "./tmux.ts";
import { classifyPanePrompt, permissionFromToolUse, PromptClock } from "./prompt-kind.ts";

// Real captures from Claude Code v2.1.280 on a 100-column pane (2026-10-15),
// with the scratch folder path shortened to a repo path.
const permissionPane = [
  "",
  "❯ Run this exact shell command with the Bash tool and nothing else: echo s2-fixture-check > out.txt",
  "",
  "⏺ Running the specified echo command",
  "  ⎿  $ echo s2-fixture-check > out.txt",
  "",
  "────────────────────────────────────────────────────────────────────────────────────────────────────",
  " Bash command",
  "",
  "   echo s2-fixture-check > out.txt",
  "   Run the specified echo command",
  "",
  " Do you want to proceed?",
  " ❯ 1. Yes",
  "   2. Yes, and always allow access to /Users/eugene/dev/personal/lfg/.claude/worktrees/sessions-redesi",
  "      gn-s2/scratch from this project",
  "   3. No",
  "",
  " Esc to cancel · Tab to amend",
].join("\n");

const planPane = [
  "  ⎿  /plan to preview",
  "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔",
  "",
  "  ────────────────────────────────────────────────────────────────────────────────────────────────",
  "   Ready to code?",
  "",
  "   Here is Claude's plan:",
  "  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌",
  "   Plan: Add LICENSE, .gitignore, and update README",
  "",
  "   Steps",
  "",
  "   1. Add LICENSE",
  "      - MIT License, copyright holder \"Eugene Chan\", year 2026.",
  "   2. Add .gitignore",
  "      - Generic baseline: OS cruft (.DS_Store), editor dirs (.vscode/, .idea/).",
  "   3. Update README.md",
  "      - Append a short \"License\" line pointing to LICENSE.",
  "  ────────────────────────────────────────────────────────────────────────────────────────────────",
  "   Claude has written up a plan and is ready to execute. Would you like to proceed?",
  "",
  "   ❯ 1. Yes, auto-accept edits",
  "     2. Yes, manually approve edits",
  "     3. Tell Claude what to change",
  "        shift+tab to approve with this feedback",
  "",
  "   ctrl+g to edit in Nvim · ~/.claude/plans/plan-a-three-step-change-idempotent-gem.md",
].join("\n");

const questionPane = [
  "⏺ Here is the current status and I need you to pick the deployment path.",
  "────────────────────────────────────────────────────────────────────────────────",
  " ☐ Deploy",
  "",
  "Which deployment approach should we use?",
  "",
  "❯ 1. Local Fastlane first",
  "  2. GitHub Actions now",
  "  3. Type something.",
  "────────────────────────────────────────────────────────────────────────────────",
  "  4. Chat about this",
  "",
  "Enter to select · ↑/↓ to navigate · Esc to cancel",
].join("\n");

function classify(pane: string) {
  const p = parsePrompt(pane);
  expect(p).not.toBeNull();
  return classifyPanePrompt(pane, p!);
}

describe("classifyPanePrompt (B4)", () => {
  test("a Bash permission dialog: kind, tool, command and its description", () => {
    const c = classify(permissionPane);
    expect(c.kind).toBe("permission");
    expect(c.permission).toEqual({
      tool: "Bash",
      command: "echo s2-fixture-check > out.txt",
      detail: "Run the specified echo command",
    });
  });

  test("a plan approval: kind, the plan text undented, and the plan file", () => {
    const c = classify(planPane);
    expect(c.kind).toBe("plan");
    expect(c.plan?.file).toBe("~/.claude/plans/plan-a-three-step-change-idempotent-gem.md");
    expect(c.plan?.text.split("\n").slice(0, 5)).toEqual([
      "Plan: Add LICENSE, .gitignore, and update README",
      "",
      "Steps",
      "",
      "1. Add LICENSE",
    ]);
    expect(c.plan?.text).toContain("   - MIT License");
    expect(c.plan?.text).not.toContain("Would you like to proceed");
  });

  test("an AskUserQuestion selector is a question", () => {
    expect(classify(questionPane)).toEqual({ kind: "question" });
  });

  test("a non-Bash permission keeps the dialog's question as its detail", () => {
    const pane = [
      "────────────────────────────────────────────────────────────────────────────────",
      " Edit file",
      " ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌",
      " 12 -  let a = 1",
      " 12 +  let a = 2",
      " ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌",
      " Do you want to make this edit to Foo.swift?",
      " ❯ 1. Yes",
      "   2. Yes, allow all edits during this session (shift+tab)",
      "   3. No",
    ].join("\n");
    const c = classify(pane);
    expect(c.kind).toBe("permission");
    expect(c.permission).toEqual({ tool: "Edit", command: "", detail: "Do you want to make this edit to Foo.swift?" });
  });
});

describe("permissionFromToolUse (transcript enrichment)", () => {
  test("Bash gives the exact command and description", () => {
    expect(permissionFromToolUse("Bash", { command: "bundle exec fastlane beta", description: "Upload" }))
      .toEqual({ tool: "Bash", command: "bundle exec fastlane beta", detail: "Upload" });
  });
  test("file tools give the path", () => {
    expect(permissionFromToolUse("Write", { file_path: "/repo/LICENSE", content: "MIT" }))
      .toEqual({ tool: "Write", command: "/repo/LICENSE" });
    expect(permissionFromToolUse("WebFetch", { url: "https://lfg.app" }))
      .toEqual({ tool: "WebFetch", command: "https://lfg.app" });
  });
});

describe("PromptClock (B3)", () => {
  const q = (question: string, context?: string) => ({ question, options: [{ index: 1, label: "Yes" }], context });
  const asked = (p: unknown) => (p as { askedAt?: number } | null)?.askedAt;

  test("the same prompt keeps its first-seen time, even as its context grows", () => {
    const clock = new PromptClock();
    expect(asked(clock.stamp("s1", q("Ship it?"), 1_000))).toBe(1_000);
    expect(asked(clock.stamp("s1", q("Ship it?", "Build 205 passed"), 5_000))).toBe(1_000);
  });

  test("a different prompt restarts the clock; no prompt forgets it", () => {
    const clock = new PromptClock();
    clock.stamp("s1", q("Ship it?"), 1_000);
    expect(asked(clock.stamp("s1", q("Upload now?"), 2_000))).toBe(2_000);
    expect(clock.stamp("s1", null, 3_000)).toBeNull();
    expect(asked(clock.stamp("s1", q("Upload now?"), 4_000))).toBe(4_000);
  });

  test("a prompt that already knows when it was asked keeps that time", () => {
    const clock = new PromptClock();
    expect(asked(clock.stamp("s1", { ...q("Sign in"), askedAt: 500 }, 9_000))).toBe(500);
  });
});
