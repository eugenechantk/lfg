import { describe, expect, it } from "bun:test";
import { DEFAULT_MODEL, claudeRelaunchArgv, managedCodexSessionArgv, managedSessionArgv } from "./tmux.ts";

const ID = "11111111-2222-3333-4444-555555555555";

describe("managedSessionArgv — fork vs resume vs fresh", () => {
  it("a fresh session carries no --resume or --fork-session", () => {
    const argv = managedSessionArgv({ name: "lfg-a", cwd: "/tmp" });
    expect(argv).not.toContain("--resume");
    expect(argv).not.toContain("--fork-session");
    expect(argv).toContain("--model");
    expect(argv[argv.indexOf("--model") + 1]).toBe(DEFAULT_MODEL);
  });

  it("resume carries --resume <id> but NOT --fork-session", () => {
    const argv = managedSessionArgv({ name: "lfg-b", cwd: "/tmp", resume: ID });
    expect(argv).toContain("--resume");
    expect(argv[argv.indexOf("--resume") + 1]).toBe(ID);
    expect(argv).not.toContain("--fork-session");
  });

  it("fork carries both --resume <id> and --fork-session, in that order", () => {
    const argv = managedSessionArgv({ name: "lfg-c", cwd: "/tmp", resume: ID, fork: true });
    const ri = argv.indexOf("--resume");
    const fi = argv.indexOf("--fork-session");
    expect(ri).toBeGreaterThanOrEqual(0);
    expect(argv[ri + 1]).toBe(ID);
    // --fork-session must follow --resume (it modifies the resume behavior).
    expect(fi).toBe(ri + 2);
  });

  it("fork WITHOUT resume is a no-op (fork only branches a resumed history)", () => {
    const argv = managedSessionArgv({ name: "lfg-d", cwd: "/tmp", fork: true });
    expect(argv).not.toContain("--fork-session");
    expect(argv).not.toContain("--resume");
  });

  it("the positional prompt sits after a `--` terminator", () => {
    const argv = managedSessionArgv({ name: "lfg-e", cwd: "/tmp", prompt: "hello" });
    const dash = argv.indexOf("--");
    expect(dash).toBeGreaterThanOrEqual(0);
    expect(argv[dash + 1]).toBe("hello");
  });
});

describe("managedCodexSessionArgv — resume and fork", () => {
  it("resume uses codex resume <id> <prompt> and does not pass --model", () => {
    const argv = managedCodexSessionArgv({
      name: "lfg-codex-r",
      cwd: "/tmp",
      resume: ID,
      model: "gpt-5.6-sol",
      prompt: "continue",
    });
    const ri = argv.indexOf("resume");

    expect(ri).toBeGreaterThanOrEqual(0);
    expect(argv[ri + 1]).toBe(ID);
    expect(argv[ri + 2]).toBe("continue");
    expect(argv).not.toContain("--model");
    expect(argv).toContain("--sandbox");
    expect(argv).toContain("--ask-for-approval");
    expect(argv).toContain("--cd");
    expect(argv).toContain("--add-dir");
  });

  it("fork uses codex fork <source-id> and keeps an explicit codex model", () => {
    const argv = managedCodexSessionArgv({
      name: "lfg-codex-f",
      cwd: "/tmp",
      resume: ID,
      fork: true,
      model: "gpt-5.6-sol",
    });
    const fi = argv.indexOf("fork");

    expect(fi).toBeGreaterThanOrEqual(0);
    expect(argv[fi + 1]).toBe(ID);
    expect(argv).toContain("--model");
    expect(argv[argv.indexOf("--model") + 1]).toBe("gpt-5.6-sol");
  });
});

describe("managedCodexSessionArgv — hook trust", () => {
  // codex refuses to run a hook without a `trusted_hash` in config.toml, and
  // does so SILENTLY: it exits 0, writes its rollout, and fires nothing. Without
  // this flag, lfg-spawned codex sessions get no turn state and no SessionEnd,
  // so `closed` degrades to the 90s lease expiry. The `codexy` alias in ~/.zshrc
  // carries the same flag so hand-started sessions behave identically.
  it("trusts lfg's own hooks so they actually run", () => {
    const argv = managedCodexSessionArgv({ name: "s", cwd: "/tmp/x" });
    expect(argv).toContain("--dangerously-bypass-hook-trust");
  });

  it("still present on the resume path", () => {
    const argv = managedCodexSessionArgv({ name: "s", cwd: "/tmp/x", resume: "abc-123" });
    expect(argv).toContain("--dangerously-bypass-hook-trust");
  });
});

describe("claudeRelaunchArgv — model and effort changes", () => {
  const base = { tmuxTarget: "lfg-x:0.0", cwd: "/tmp/x", sessionId: ID };
  const flag = (argv: string[], name: string) => (argv.includes(name) ? argv[argv.indexOf(name) + 1] : null);

  it("respawns the same pane on the same conversation", () => {
    const argv = claudeRelaunchArgv({ ...base, model: "sonnet" });
    expect(argv.slice(0, 3)).toEqual(["tmux", "respawn-pane", "-k"]);
    expect(flag(argv, "-t")).toBe("lfg-x:0.0");
    expect(flag(argv, "--resume")).toBe(ID);
  });

  it("an effort change pins effort and keeps the exact model", () => {
    const argv = claudeRelaunchArgv({ ...base, model: "claude-opus-5", effort: "max" });
    expect(flag(argv, "--model")).toBe("claude-opus-5");
    expect(flag(argv, "--effort")).toBe("max");
  });

  it("a model switch carries a session's explicit effort", () => {
    const argv = claudeRelaunchArgv({ ...base, model: "sonnet", effort: "low" });
    expect(flag(argv, "--model")).toBe("sonnet");
    expect(flag(argv, "--effort")).toBe("low");
  });

  it("omits what is unknown so Claude's own defaults apply", () => {
    const argv = claudeRelaunchArgv({ ...base, model: null, effort: null });
    expect(argv).not.toContain("--model");
    expect(argv).not.toContain("--effort");
  });
});
