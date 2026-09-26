import { describe, expect, test } from "bun:test";
import {
  codexAppServerClaims,
  externalResumeError,
  sessionControl,
  sessionSource,
} from "./sessions.ts";

describe("desktop session ownership", () => {
  test("only app-server rollouts open for writing become live external sessions", () => {
    const chatgpt = {
      pid: 42,
      cmd: "/Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://",
    };
    const idleEngine = { pid: 43, cmd: "/opt/homebrew/bin/codex app-server" };
    const tui = { pid: 44, cmd: "/opt/homebrew/bin/codex resume thread-b" };
    const threads = [
      { id: "thread-a", path: "/tmp/rollout-a.jsonl" },
      { id: "thread-b", path: "/tmp/rollout-b.jsonl" },
    ];

    const claims = codexAppServerClaims({
      procs: [chatgpt, idleEngine, tui],
      threads,
      openPathsByPid: new Map([
        [42, ["/tmp/rollout-a.jsonl"]],
        [43, []],
        [44, ["/tmp/rollout-b.jsonl"]],
      ]),
    });

    expect(claims.map((claim) => [claim.pid, claim.thread.id])).toEqual([[42, "thread-a"]]);
  });

  test("does not duplicate a rollout already claimed by a directly controlled session", () => {
    const claims = codexAppServerClaims({
      procs: [{ pid: 42, cmd: "codex app-server" }],
      threads: [{ id: "thread-a", path: "/tmp/rollout-a.jsonl" }],
      openPathsByPid: new Map([[42, ["/tmp/rollout-a.jsonl"]]]),
      claimedIds: new Set(["thread-a"]),
    });

    expect(claims).toEqual([]);
  });

  test("labels direct and external frontends without coupling ownership to provider", () => {
    expect(sessionControl("lfg-a:0.0")).toBe("direct");
    expect(sessionControl(null)).toBe("external");

    expect(sessionSource({
      agent: "codex",
      cmd: "/Applications/ChatGPT.app/Contents/Resources/codex app-server",
      tmuxTarget: null,
      managed: false,
    })).toBe("chatgpt-desktop");
    expect(sessionSource({
      agent: "claude",
      cmd: "/Applications/Claude.app/Contents/Resources/claude",
      tmuxTarget: null,
      managed: false,
    })).toBe("claude-desktop");
    expect(sessionSource({
      agent: "claude",
      cmd: "/opt/homebrew/bin/claude",
      tmuxTarget: null,
      managed: false,
    })).toBe("terminal");
    expect(sessionSource({
      agent: "codex",
      cmd: "/opt/homebrew/bin/codex",
      tmuxTarget: "lfg-a:0.0",
      managed: true,
    })).toBe("lfg");
  });

  test("refuses exact resume while an external frontend owns the writer", () => {
    expect(externalResumeError({ control: "direct", source: "lfg" })).toBeNull();
    expect(externalResumeError({
      control: "external",
      source: "chatgpt-desktop",
    })).toBe("session is active in ChatGPT Desktop; fork it to continue in LFG");
  });
});
