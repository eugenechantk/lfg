import { describe, expect, it } from "bun:test";
import { managedSessionArgv } from "./tmux.ts";

const ID = "11111111-2222-3333-4444-555555555555";

describe("managedSessionArgv — fork vs resume vs fresh", () => {
  it("a fresh session carries no --resume or --fork-session", () => {
    const argv = managedSessionArgv({ name: "lfg-a", cwd: "/tmp" });
    expect(argv).not.toContain("--resume");
    expect(argv).not.toContain("--fork-session");
    expect(argv).toContain("--model");
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
