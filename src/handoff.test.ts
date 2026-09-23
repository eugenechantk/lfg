import { describe, expect, test } from "bun:test";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { prepareHandoff } from "./handoff.ts";
import { managedSessionArgv, managedCodexSessionArgv } from "./tmux.ts";

describe("cross-tool handoff", () => {
  test("desktop uses configured defaults while explicit iOS selections are retained", () => {
    const base = { name: "handoff-test", cwd: "/tmp", prompt: "read context" };
    expect(managedSessionArgv({ ...base, useConfiguredModelDefault: true })).not.toContain("--model");
    expect(managedSessionArgv(base)).toContain("--model");
    const explicit = managedSessionArgv({ ...base, useConfiguredModelDefault: true, model: "sonnet" });
    expect(explicit[explicit.indexOf("--model") + 1]).toBe("sonnet");
    expect(managedCodexSessionArgv(base)).not.toContain("--model");
    expect(managedCodexSessionArgv({ ...base, model: "gpt-5.6-sol" })).toContain("gpt-5.6-sol");
  });

  test("Codex history is carried to Claude with modern user turns and raw tools", async () => {
    const root = await mkdtemp(join(tmpdir(), "lfg-handoff-codex-"));
    try {
      const source = join(root, "rollout.jsonl");
      const rows = [
        { type: "session_meta", payload: { cwd: root } },
        { type: "response_item", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "Keep ORCHID BRIDGE 472" }], internal_chat_message_metadata_passthrough: { content_item_kinds: ["user.text"] } } },
        { type: "response_item", payload: { type: "function_call", name: "exec_command", call_id: "c1", arguments: '{"cmd":"pwd"}' } },
        { type: "response_item", payload: { type: "function_call_output", call_id: "c1", output: "raw tool output" } },
        { type: "response_item", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Remembered; awaiting instruction." }] } },
      ];
      const raw = rows.map(x => JSON.stringify(x)).join("\n");
      await writeFile(source, raw);
      const result = await prepareHandoff({ sourceAgent: "codex", targetAgent: "claude", sessionId: "codex-source", transcript: source, cwd: root, outputRoot: join(root, "handoffs") });
      expect(await readFile(result.rawPath, "utf8")).toBe(raw);
      expect(result.rawPath).toEndWith("codex-transcript.jsonl");
      expect(await readFile(result.contextPath, "utf8")).toContain("Keep ORCHID BRIDGE 472");
      expect(await readFile(result.contextPath, "utf8")).toContain("Remembered; awaiting instruction.");
      expect(result.prompt).toContain("from Codex to Claude Code");
      expect(await readFile(source, "utf8")).toBe(raw);
    } finally { await rm(root, { recursive: true, force: true }); }
  });
  test("preserves a full snapshot, tools and original; drops only an incomplete final row", async () => {
    const root = await mkdtemp(join(tmpdir(), "lfg-handoff-test-"));
    try {
      const source = join(root, "source.jsonl");
      const rows = Array.from({ length: 150 }, (_, n) => JSON.stringify({
        type: n % 2 ? "assistant" : "user", uuid: `turn-${n}`, cwd: root,
        message: { role: n % 2 ? "assistant" : "user", content: `message ${n}` },
      }));
      rows.push(JSON.stringify({ type: "assistant", message: { role: "assistant", content: [
        { type: "tool_use", name: "Read", input: { file_path: "/tmp/important" } },
      ] } }));
      const complete = rows.join("\n") + "\n";
      const original = complete + '{"unfinished":';
      await writeFile(source, original);
      const prepared = await prepareHandoff({ sourceAgent: "claude", targetAgent: "codex", sessionId: "source-id", transcript: source, cwd: root, outputRoot: join(root, "handoffs") });
      expect(await readFile(prepared.rawPath, "utf8")).toBe(complete);
      const readable = await readFile(prepared.contextPath, "utf8");
      expect(readable).toContain("message 0");
      expect(readable).toContain("message 149");
      expect(prepared.prompt).toContain(prepared.contextPath);
      expect(prepared.prompt).toContain("wait for my next instruction");
      expect(await readFile(source, "utf8")).toBe(original);
      await writeFile(source, original + "later change");
      expect(await readFile(prepared.rawPath, "utf8")).toBe(complete);
    } finally { await rm(root, { recursive: true, force: true }); }
  });

  test("rejects absent cwd and empty conversations", async () => {
    const root = await mkdtemp(join(tmpdir(), "lfg-handoff-test-"));
    try {
      const source = join(root, "empty.jsonl");
      await writeFile(source, "");
      await expect(prepareHandoff({ sourceAgent: "claude", targetAgent: "codex", sessionId: "source", transcript: source, cwd: join(root, "missing"), outputRoot: root })).rejects.toThrow("directory");
      await expect(prepareHandoff({ sourceAgent: "claude", targetAgent: "codex", sessionId: "source", transcript: source, cwd: root, outputRoot: root })).rejects.toThrow("conversation");
    } finally { await rm(root, { recursive: true, force: true }); }
  });
});
