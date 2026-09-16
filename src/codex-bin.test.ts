import { describe, expect, it } from "bun:test";
import { mkdirSync, mkdtempSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { codexBin, codexErrorFromPane, codexPaneSettled, parseCodexVersion, pickNewestCodex } from "./tmux.ts";

describe("codexPaneSettled — the composer is the only positive bootstrap signal", () => {
  it("is true once BOTH the composer row and the model · cwd status line render", () => {
    expect(codexPaneSettled("• Starting MCP servers (4/6)\n› Summarize recent commits\n  gpt-6-astra high · ~/x\n")).toBe(true);
    expect(codexPaneSettled("› Ask Codex to do anything\n  gpt-6-astra high fast · ~/dev/personal/fiftyworkout\n")).toBe(true);
  });
  it("is false for the composer without the status line (0.153.4 draws it before thread/resume resolves)", () => {
    expect(codexPaneSettled("› Ask Codex to do anything\n  ? for shortcuts\n")).toBe(false);
  });
  it("is false for startup selectors, warnings, a blank pane, and a dead pane", () => {
    expect(codexPaneSettled("  ✨ Update available! 0.146.0 -> 0.153.4\n› 1. Update now (runs `bun install -g @openai/codex`)\n  2. Skip\n")).toBe(false);
    expect(codexPaneSettled("> You are in /tmp\n› 1. Yes, continue\n  2. No, quit\n")).toBe(false);
    expect(codexPaneSettled("⚠ `--dangerously-bypass-hook-trust` is enabled.\n")).toBe(false);
    expect(codexPaneSettled("")).toBe(false);
    expect(codexPaneSettled("Error: Failed to resume session\nPane is dead (status 1)\n")).toBe(false);
  });
});

describe("codex binary resolution — newest copy wins", () => {
  it("parses the CLI's version banner", () => {
    expect(parseCodexVersion("codex-cli 0.153.4\n")).toBe("0.153.4");
    expect(parseCodexVersion("codex-cli 0.146.0")).toBe("0.146.0");
    expect(parseCodexVersion("")).toBeNull();
    expect(parseCodexVersion("command not found")).toBeNull();
  });

  it("prefers the higher version even when it is later in PATH order", () => {
    // The real 2026-09-06 shape: homebrew first on the server PATH at 0.146,
    // codex's own updater put 0.153.4 in ~/.bun/bin, which the server never saw.
    const best = pickNewestCodex([
      { path: "/opt/homebrew/bin/codex", version: "0.146.0" },
      { path: "/Users/e/.bun/bin/codex", version: "0.153.4" },
    ]);
    expect(best?.path).toBe("/Users/e/.bun/bin/codex");
  });

  it("compares numerically, not lexically", () => {
    const best = pickNewestCodex([
      { path: "/a/codex", version: "0.9.0" },
      { path: "/b/codex", version: "0.153.4" },
      { path: "/c/codex", version: "0.100.0" },
    ]);
    expect(best?.path).toBe("/b/codex");
  });

  it("keeps PATH order on ties and never picks an unknown version over a known one", () => {
    expect(
      pickNewestCodex([
        { path: "/first/codex", version: "0.153.4" },
        { path: "/second/codex", version: "0.153.4" },
      ])?.path,
    ).toBe("/first/codex");
    expect(
      pickNewestCodex([
        { path: "/broken/codex", version: null },
        { path: "/ok/codex", version: "0.146.0" },
      ])?.path,
    ).toBe("/ok/codex");
    // Only unknowns: still returns something so the failure surfaces at spawn.
    expect(pickNewestCodex([{ path: "/x/codex", version: null }])?.path).toBe("/x/codex");
    expect(pickNewestCodex([])).toBeNull();
  });
});

describe("codexBin — re-resolves when an install changes", () => {
  const fake = (dir: string, version: string) => {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "codex"), `#!/bin/sh\necho codex-cli ${version}\n`, { mode: 0o755 });
  };
  it("picks the newest on PATH, then follows an upgrade without a restart", () => {
    const root = mkdtempSync(join(tmpdir(), "lfg-codexbin-"));
    const a = join(root, "a");
    const b = join(root, "b");
    fake(a, "0.146.0");
    fake(b, "0.153.4");
    const env = { PATH: `${a}:${b}`, HOME: root } as NodeJS.ProcessEnv;
    expect(codexBin(env)).toBe(join(b, "codex"));
    // A self-update lands in `a` (new content + mtime): the cached answer must not stick.
    fake(a, "0.200.0");
    const later = new Date(Date.now() + 5000);
    utimesSync(join(a, "codex"), later, later);
    expect(codexBin(env)).toBe(join(a, "codex"));
    // Same installs, same answer, no re-probe needed.
    expect(codexBin(env)).toBe(join(a, "codex"));
    expect(codexBin({ ...env, LFG_CODEX_BIN: "/pinned/codex" })).toBe("/pinned/codex");
  });
});

describe("codexErrorFromPane — reading a dead pane back", () => {
  // Verbatim capture of the failing resume, 120 cols, remain-on-exit on.
  const captured = [
    "  ✨ Update available! 0.146.0 -> 0.153.4",
    "  Release notes: https://github.com/openai/codex/releases/latest",
    "› 1. Update now (runs `bun install -g @openai/codex`)",
    "  2. Skip",
    "  3. Skip until next version",
    "  Press enter to continueError: Failed to resume session from /Users/eugenechan/.codex/sessions/2026/09/05/rollout-2026-",
    "09-05T22-45-02-01a07207-b399-7213-bb18-95fe1de17ca6.jsonl: thread/resume failed during TUI bootstrap: thread/resume fail",
    "ed: failed to deserialize stored thread item subagent-completed-01a0720b-1a65-7f10-a24a-f98447f96630: unknown variant `c",
    "ompleted`, expected one of `started`, `interacted`, `interrupted` (code -32603)",
    "Pane is dead (status 1, Sun Sep  6 18:12:03 2026)",
    "",
    "",
  ].join("\n");

  it("rejoins the hard-wrapped Error line and drops the tmux trailer", () => {
    const err = codexErrorFromPane(captured);
    expect(err).toStartWith("Error: Failed to resume session from ");
    expect(err).toContain("rollout-2026-09-05T22-45-02-01a07207-b399-7213-bb18-95fe1de17ca6.jsonl");
    expect(err).toContain("thread/resume failed during TUI bootstrap");
    expect(err).toContain("unknown variant `completed`, expected one of `started`, `interacted`, `interrupted` (code -32603)");
    expect(err).not.toContain("Pane is dead");
    expect(err).not.toContain("Press enter to continue");
  });

  it("falls back to the trailing block when the Error: head was lost to the alternate screen", () => {
    // Seen when the prompt is on argv: the first wrapped fragment never lands
    // in the normal screen, only the continuation lines + tmux's trailer do.
    const lostHead = [
      "399-7213-bb18-95fe1de17ca6.jsonl: thread/resume failed during TUI bootstrap: thread/resume failed: thread 01a07207-b399-",
      "7213-bb18-95fe1de17ca6 already has an active writer (code -32600)",
      "Pane is dead (status 1, Sun Sep  6 18:28:37 2026)",
      "",
    ].join("\n");
    const err = codexErrorFromPane(lostHead);
    expect(err).toContain("thread/resume failed during TUI bootstrap");
    expect(err).toContain("thread 01a07207-b399-7213-bb18-95fe1de17ca6 already has an active writer (code -32600)");
    expect(err).not.toContain("Pane is dead");
  });

  it("is null for a healthy pane", () => {
    expect(codexErrorFromPane("› Summarize recent commits\n  gpt-6-astra high · /tmp\n")).toBeNull();
    expect(codexErrorFromPane("")).toBeNull();
  });
});
