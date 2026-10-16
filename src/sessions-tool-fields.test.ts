// B11 (sessions-redesign-s2): tool rows carry what the app needs to fold them
// into steps and to pair a call with its result — `toolUseId` on both rows,
// plus `tool {name, target}` on Claude calls and `isError` on Claude results.
// The display text is unchanged, so older clients render exactly as before.
import { describe, expect, test } from "bun:test";
import { createCodexNormalizationState, normalizeLineMessages, toolTarget } from "./sessions.ts";

const ts = new Date(0).toISOString();

function claudeUse(name: string, input: unknown, id = "toolu_1"): string {
  return JSON.stringify({
    type: "assistant", uuid: "a1", timestamp: ts,
    message: { role: "assistant", content: [{ type: "tool_use", id, name, input }] },
  });
}

function claudeResult(content: string, opts: { id?: string; isError?: boolean } = {}): string {
  return JSON.stringify({
    type: "user", uuid: "u1", timestamp: ts,
    message: {
      role: "user",
      content: [{ type: "tool_result", tool_use_id: opts.id ?? "toolu_1", content, ...(opts.isError ? { is_error: true } : {}) }],
    },
  });
}

function codex(type: string, payload: Record<string, unknown>): string {
  return JSON.stringify({ timestamp: ts, type, payload });
}

describe("toolTarget", () => {
  test("names what each common tool acts on", () => {
    expect(toolTarget("Bash", { command: "bun test src/sessions.test.ts\necho done" })).toBe("bun test src/sessions.test.ts");
    expect(toolTarget("Read", { file_path: "/repo/ios/LFG/SessionStore.swift" })).toBe("/repo/ios/LFG/SessionStore.swift");
    expect(toolTarget("Edit", { file_path: "/repo/a.ts", old_string: "x" })).toBe("/repo/a.ts");
    expect(toolTarget("Write", { file_path: "/repo/b.ts" })).toBe("/repo/b.ts");
    expect(toolTarget("NotebookEdit", { notebook_path: "/repo/n.ipynb" })).toBe("/repo/n.ipynb");
    expect(toolTarget("Grep", { pattern: "forkSession", path: "src" })).toBe("forkSession");
    expect(toolTarget("Glob", { pattern: "**/*.swift" })).toBe("**/*.swift");
    expect(toolTarget("WebFetch", { url: "https://example.com/x" })).toBe("https://example.com/x");
    expect(toolTarget("WebSearch", { query: "swiftui glass" })).toBe("swiftui glass");
    expect(toolTarget("Agent", { description: "Find every fork caller" })).toBe("Find every fork caller");
  });

  test("returns undefined when there is nothing sensible to name", () => {
    expect(toolTarget("TodoWrite", { todos: [] })).toBeUndefined();
    expect(toolTarget("Bash", { command: "   " })).toBeUndefined();
    expect(toolTarget("Read", null)).toBeUndefined();
  });

  test("caps a very long target", () => {
    const long = "x".repeat(500);
    expect(toolTarget("Bash", { command: long })!.length).toBeLessThanOrEqual(240);
  });
});

describe("Claude tool rows", () => {
  test("a call carries its id, tool name and target; the text is unchanged", () => {
    const [m] = normalizeLineMessages(claudeUse("Bash", { command: "bun test" }));
    expect(m.kind).toBe("tool_use");
    expect(m.text.startsWith("Bash")).toBe(true);
    expect(m.toolUseId).toBe("toolu_1");
    expect(m.tool).toEqual({ name: "Bash", target: "bun test" });
  });

  test("a result carries the id it answers and whether it failed", () => {
    const [ok] = normalizeLineMessages(claudeResult("42 pass"));
    expect(ok.kind).toBe("tool_result");
    expect(ok.toolUseId).toBe("toolu_1");
    expect(ok.isError).toBe(false);
    const [bad] = normalizeLineMessages(claudeResult("Exit code 1", { isError: true }));
    expect(bad.isError).toBe(true);
  });

  test("an agent launch is a call too, named Agent with its description", () => {
    const [m] = normalizeLineMessages(claudeUse("Agent", { description: "Audit the fork tests", prompt: "…" }, "toolu_9"));
    expect(m.kind).toBe("tool_use");
    expect(m.toolUseId).toBe("toolu_9");
    expect(m.tool).toEqual({ name: "Agent", target: "Audit the fork tests" });
  });
});

describe("Codex tool rows", () => {
  test("a command and its output share the call id", () => {
    const state = createCodexNormalizationState();
    const [call] = normalizeLineMessages(codex("response_item", {
      type: "function_call", id: "fc_1", call_id: "call_7", name: "exec_command",
      arguments: JSON.stringify({ cmd: "bun test src/sessions.test.ts" }),
    }), state);
    const [out] = normalizeLineMessages(codex("response_item", {
      type: "function_call_output", id: "fco_1", call_id: "call_7", output: "42 pass",
    }), state);
    expect(call.kind).toBe("tool_use");
    expect(out.kind).toBe("tool_result");
    expect(call.toolUseId).toBe("call_7");
    expect(out.toolUseId).toBe("call_7");
  });
});
