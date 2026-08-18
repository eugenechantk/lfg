import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  createCodexNormalizationState,
  normalizeLineMessages,
  recentMessages,
} from "./sessions.ts";

const timestamp = "2026-08-14T09:11:29.541Z";

function record(type: string, payload: Record<string, unknown>, ts = timestamp): string {
  return JSON.stringify({ timestamp: ts, type, payload });
}

function customCall(input: string, callID = "call_1"): string {
  return record("response_item", {
    type: "custom_tool_call",
    id: `ctc_${callID}`,
    status: "completed",
    call_id: callID,
    name: "exec",
    input,
  });
}

function customOutput(output: unknown, callID = "call_1"): string {
  return record(
    "response_item",
    { type: "custom_tool_call_output", id: `ctco_${callID}`, call_id: callID, output },
    "2026-08-14T09:11:29.802Z",
  );
}

function functionCall(name: string, args: unknown, callID = `call_${name}`): string {
  return record("response_item", {
    type: "function_call",
    id: `fc_${callID}`,
    call_id: callID,
    name,
    arguments: typeof args === "string" ? args : JSON.stringify(args),
  });
}

function functionOutput(output: unknown, callID: string): string {
  return record("response_item", {
    type: "function_call_output",
    id: `fco_${callID}`,
    call_id: callID,
    output,
  });
}

function patchApplyEnd(overrides: Record<string, unknown> = {}): string {
  return record(
    "event_msg",
    {
      type: "patch_apply_end",
      call_id: "exec-patch-1",
      success: true,
      stdout: "Success. Updated the following files:\nM /repo/src/app.ts\n",
      stderr: "",
      changes: {
        "/repo/src/app.ts": {
          type: "update",
          unified_diff: "@@ -1 +1 @@\n-old\n+new\n",
        },
        "/repo/src/new.ts": {
          type: "add",
          content: "export const value = 1;\n",
        },
      },
      ...overrides,
    },
    "2026-08-14T09:14:48.632Z",
  );
}

describe("Codex CLI transcript parity", () => {
  test("renders patch summaries with the CLI's Edited/Added labels and line counts", () => {
    const state = createCodexNormalizationState();
    normalizeLineMessages(
      record("session_meta", { type: "session_meta", cwd: "/repo" }),
      state,
    );
    const messages = normalizeLineMessages(patchApplyEnd(), state);

    expect(messages).toHaveLength(1);
    expect(messages[0]).toMatchObject({
      role: "assistant",
      kind: "tool_use",
      text:
        "Edited 2 files (+2 -1)\n" +
        "src/app.ts (+1 -1)\n@@ -1 +1 @@\n-old\n+new\n\n" +
        "src/new.ts (+1 -0)\nexport const value = 1;",
      ts: Date.parse("2026-08-14T09:14:48.632Z"),
    });
  });

  test("renders single-file and failed patch cells like the CLI", () => {
    const one = normalizeLineMessages(
      patchApplyEnd({
        changes: { "/repo/new.ts": { type: "add", content: "one\ntwo\n" } },
      }),
    )[0];
    expect(one?.text).toBe("Added /repo/new.ts (+2 -0)\none\ntwo");

    expect(
      normalizeLineMessages(
        patchApplyEnd({ success: false, status: "failed", changes: {}, stderr: "Patch rejected" }),
      )[0],
    ).toMatchObject({ kind: "tool_result", text: "Failed to apply patch\nPatch rejected" });
    expect(normalizeLineMessages(patchApplyEnd({ changes: {}, stdout: "", stderr: "" }))).toEqual(
      [],
    );
  });

  test("keeps CLI-relative patch paths when a paged transcript starts after session_meta", async () => {
    const dir = mkdtempSync(join(tmpdir(), "lfg-codex-parity-"));
    const path = join(dir, "rollout.jsonl");
    try {
      writeFileSync(
        path,
        [
          record("session_meta", { cwd: "/repo" }),
          record("event_msg", { type: "future_bookkeeping", detail: "x".repeat(4096) }),
          patchApplyEnd({ changes: { "/repo/src/app.ts": { type: "update", unified_diff: "+new\n" } } }),
          "",
        ].join("\n"),
      );
      const messages = await recentMessages(path, 20, { maxBytes: 1024 });
      expect(messages.at(-1)?.text).toBe("Edited src/app.ts (+1 -0)\n+new");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("turns Code Mode exec wrappers into Ran/Explored cells and strips the envelope", () => {
    const state = createCodexNormalizationState();
    expect(
      normalizeLineMessages(
        customCall('const r = await tools.exec_command({"cmd":"bun test"}); text(r.output);'),
        state,
      )[0],
    ).toMatchObject({ kind: "tool_use", text: "Ran\nbun test" });
    expect(
      normalizeLineMessages(
        customOutput([
          { type: "input_text", text: "Script completed\nWall time 0.4 seconds\nOutput:\n" },
          { type: "input_text", text: "12 pass\n" },
        ]),
        state,
      )[0],
    ).toMatchObject({ kind: "tool_result", text: "12 pass" });

    const explored = normalizeLineMessages(
      customCall(
        'const r = await tools.exec_command({"cmd":"sed -n \'1,80p\' src/app.ts && rg -n \'TODO\' src"}); text(r.output);',
        "call_explore",
      ),
      state,
    )[0];
    expect(explored?.text).toBe("Explored\nRead src/app.ts\nSearch TODO in src");

    const looped = normalizeLineMessages(
      customCall(
        'const cmds = ["sed -n \'1,20p\' README.md", "rg -n \'TODO\' src"]; for (const cmd of cmds) { const r = await tools.exec_command({cmd}); text(r.output); }',
        "call_loop",
      ),
      state,
    )[0];
    expect(looped?.text).toBe("Explored\nRead README.md\nSearch TODO in src");

    expect(
      normalizeLineMessages(
        functionCall("exec_command", { cmd: "git status --short" }, "call_direct_exec"),
        state,
      )[0]?.text,
    ).toBe("Ran\ngit status --short");
    expect(
      normalizeLineMessages(functionOutput(" M src/app.ts", "call_direct_exec"), state)[0]?.text,
    ).toBe("M src/app.ts");
  });

  test("shows plan updates without exposing orchestration JavaScript", () => {
    const state = createCodexNormalizationState();
    const messages = normalizeLineMessages(
      customCall(
        'const r = await tools.update_plan({explanation:"Tests are green.",plan:[{step:"Audit records",status:"completed"},{step:"Fix rendering",status:"in_progress"},{step:"Verify",status:"pending"}]}); text(r);',
        "call_plan",
      ),
      state,
    );
    expect(messages[0]?.text).toBe(
      "Updated Plan\nTests are green.\n✔ Audit records\n□ Fix rendering\n□ Verify",
    );
    expect(normalizeLineMessages(customOutput("ok", "call_plan"), state)).toEqual([]);
  });

  test("uses specialized web, image, MCP, context, and sub-agent cells", () => {
    const state = createCodexNormalizationState();
    expect(
      normalizeLineMessages(
        customCall(
          'const r = await tools.web__run({"search_query":[{"q":"Codex TUI"}]}); text(r);',
          "call_web",
        ),
        state,
      )[0]?.text,
    ).toBe("Searching the web");
    expect(normalizeLineMessages(customOutput("results", "call_web"), state)).toEqual([]);
    expect(
      normalizeLineMessages(
        record("event_msg", {
          type: "web_search_end",
          call_id: "web_1",
          query: "fallback",
          action: { type: "find_in_page", url: "https://example.com", pattern: "Codex" },
        }),
        state,
      )[0]?.text,
    ).toBe("Searched the web for 'Codex' in https://example.com");

    expect(
      normalizeLineMessages(
        functionCall("view_image", { path: "/repo/screenshot.png" }, "call_image"),
        state,
      )[0]?.text,
    ).toBe("Viewed Image\n/repo/screenshot.png");
    expect(normalizeLineMessages(functionOutput("ok", "call_image"), state)).toEqual([]);
    expect(
      normalizeLineMessages(
        record("event_msg", {
          type: "image_generation_end",
          status: "completed",
          revised_prompt: "A cat in sunlight",
          saved_path: "/repo/cat.png",
        }),
        state,
      )[0]?.text,
    ).toBe("Generated Image:\nA cat in sunlight\nSaved to: /repo/cat.png");

    const mcp = normalizeLineMessages(
      record("event_msg", {
        type: "mcp_tool_call_end",
        call_id: "mcp_1",
        invocation: { server: "search", tool: "find_docs", arguments: { query: "ratatui" } },
        result: { Ok: { content: [{ type: "text", text: "Found the docs" }], isError: false } },
      }),
      state,
    )[0];
    expect(mcp).toMatchObject({
      kind: "tool_use",
      text: 'Called search.find_docs({"query":"ratatui"})\nFound the docs',
    });

    expect(
      normalizeLineMessages(record("event_msg", { type: "context_compacted" }), state)[0]?.text,
    ).toBe("Context compacted");
    expect(
      normalizeLineMessages(
        record("event_msg", {
          type: "sub_agent_activity",
          event_id: "evt_1",
          agent_path: "/root/audit",
          kind: "started",
        }),
        state,
      )[0]?.text,
    ).toBe("Started `/root/audit`");
  });

  test("surfaces hidden Codex image output as a served markdown attachment", async () => {
    const state = createCodexNormalizationState();
    const bytes = Buffer.from("codex-image-one");
    normalizeLineMessages(
      functionCall("view_image", { path: "/repo/screenshot.png" }, "call_image_output"),
      state,
    );

    const messages = normalizeLineMessages(
      functionOutput(
        [
          { type: "input_text", text: "internal tool envelope" },
          {
            type: "input_image",
            image_url: `data:image/png;base64,${bytes.toString("base64")}`,
            detail: "high",
          },
        ],
        "call_image_output",
      ),
      state,
    );

    expect(messages).toHaveLength(1);
    expect(messages[0]).toMatchObject({ role: "assistant", kind: "text" });
    expect(messages[0]?.text).toMatch(/^!\[image\.png\]\(\/.*\/image\.png\)$/);
    expect(messages[0]?.text).not.toContain("base64");
    expect(messages[0]?.text).not.toContain("internal tool envelope");
    const path = messages[0]!.text.match(/\((.*)\)$/)?.[1];
    expect(path).toBeTruthy();
    expect(Buffer.from(await Bun.file(path!).arrayBuffer())).toEqual(bytes);
    rmSync(path!.replace(/\/image\.png$/, ""), { recursive: true, force: true });
  });

  test("preserves multiple Codex image blocks without leaking their base64 payloads", async () => {
    const state = createCodexNormalizationState();
    const first = Buffer.from("first-image");
    const second = Buffer.from("second-image");
    normalizeLineMessages(
      functionCall("exec_command", { cmd: "render screenshots" }, "call_multi_image"),
      state,
    );

    const messages = normalizeLineMessages(
      functionOutput(
        [
          { type: "input_text", text: "Script completed\nWall time 0.1 seconds\nOutput:\nrendered" },
          { type: "input_image", image_url: `data:image/png;base64,${first.toString("base64")}` },
          { type: "input_image", image_url: `data:image/jpeg;base64,${second.toString("base64")}` },
        ],
        "call_multi_image",
      ),
      state,
    );

    expect(messages.map((message) => message.kind)).toEqual(["tool_result", "text", "text"]);
    expect(messages[0]?.text).toBe("rendered");
    expect(messages.slice(1).map((message) => message.text)).toEqual([
      expect.stringMatching(/^!\[image\.png\]\(\/.*\/image\.png\)$/),
      expect.stringMatching(/^!\[image\.jpg\]\(\/.*\/image\.jpg\)$/),
    ]);
    expect(new Set(messages.slice(1).map((message) => message.id)).size).toBe(2);
    expect(JSON.stringify(messages)).not.toContain("base64");

    const paths = messages.slice(1).map((message) => message.text.match(/\((.*)\)$/)![1]);
    expect(Buffer.from(await Bun.file(paths[0]).arrayBuffer())).toEqual(first);
    expect(Buffer.from(await Bun.file(paths[1]).arrayBuffer())).toEqual(second);
    for (const path of paths) {
      rmSync(path.replace(/\/image\.(?:png|jpg)$/, ""), { recursive: true, force: true });
    }
  });

  test("collapses direct MCP call lifecycles into one stable CLI activity", () => {
    const state = createCodexNormalizationState();
    const started = normalizeLineMessages(
      record("response_item", {
        type: "function_call",
        id: "fc_1",
        call_id: "call_js",
        namespace: "mcp__node_repl",
        name: "js",
        arguments: '{"title":"Inspect workspace","code":"1 + 1"}',
      }),
      state,
    )[0];
    expect(started?.text).toBe(
      'Called node_repl.js({"title":"Inspect workspace","code":"1 + 1"})',
    );
    const completed = normalizeLineMessages(
      record("event_msg", {
        type: "mcp_tool_call_end",
        call_id: "call_js",
        invocation: {
          server: "node_repl",
          tool: "js",
          arguments: { title: "Inspect workspace", code: "1 + 1" },
        },
        result: { Ok: { content: [{ type: "text", text: "2" }], isError: false } },
      }),
      state,
    )[0];
    expect(completed).toMatchObject({
      id: started?.id,
      ts: started?.ts,
      text: 'Called node_repl.js({"title":"Inspect workspace","code":"1 + 1"})\n2',
    });
    expect(normalizeLineMessages(functionOutput("2", "call_js"), state)).toEqual([]);

    expect(
      normalizeLineMessages(
        customCall(
          'const r = await tools.mcp__node_repl__js({"title":"Inspect","code":"2 + 2"}); text(r);',
          "call_wrapped_mcp",
        ),
        state,
      ),
    ).toEqual([]);
    expect(normalizeLineMessages(customOutput("4", "call_wrapped_mcp"), state)).toEqual([]);
  });

  test("REST transcript scans return one completed MCP cell, not lifecycle duplicates", async () => {
    const dir = mkdtempSync(join(tmpdir(), "lfg-codex-mcp-"));
    const path = join(dir, "rollout.jsonl");
    try {
      writeFileSync(
        path,
        [
          record("session_meta", { cwd: "/repo" }),
          record("response_item", {
            type: "function_call",
            call_id: "call_mcp",
            name: "js",
            namespace: "mcp__node_repl",
            arguments: '{"code":"1 + 1"}',
          }),
          record("event_msg", {
            type: "mcp_tool_call_end",
            call_id: "call_mcp",
            invocation: { server: "node_repl", tool: "js", arguments: { code: "1 + 1" } },
            result: { Ok: { content: [{ type: "text", text: "2" }], isError: false } },
          }),
          functionOutput("2", "call_mcp"),
          "",
        ].join("\n"),
      );
      const messages = await recentMessages(path, 20, { maxBytes: null });
      expect(messages).toHaveLength(1);
      expect(messages[0]?.text).toBe('Called node_repl.js({"code":"1 + 1"})\n2');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("shows direct generic calls as Called and hides CLI-hidden bookkeeping", () => {
    const state = createCodexNormalizationState();
    expect(
      normalizeLineMessages(functionCall("js", { code: "1 + 1" }, "call_generic"), state)[0]
        ?.text,
    ).toBe('Called js({"code":"1 + 1"})');
    expect(normalizeLineMessages(functionOutput("2", "call_generic"), state)[0]?.text).toBe("2");

    expect(
      normalizeLineMessages(
        record("response_item", {
          type: "local_shell_call",
          call_id: "shell_1",
          status: "completed",
          action: { type: "exec", command: ["git", "status", "--short"] },
        }),
        state,
      )[0]?.text,
    ).toBe("Ran\ngit status --short");

    for (const [type, payloadType] of [
      ["event_msg", "token_count"],
      ["event_msg", "task_started"],
      ["event_msg", "task_complete"],
      ["event_msg", "thread_settings_applied"],
      ["turn_context", undefined],
      ["world_state", undefined],
      ["inter_agent_communication_metadata", undefined],
    ] as const) {
      expect(
        normalizeLineMessages(record(type, payloadType ? { type: payloadType } : {}), state),
      ).toEqual([]);
    }
  });

  test("replays legacy CLI-visible commands, images, notices, and review markers", () => {
    const state = createCodexNormalizationState();
    normalizeLineMessages(record("session_meta", { cwd: "/repo" }), state);
    const commandCall = normalizeLineMessages(
      functionCall("exec_command", { cmd: "sed -n '1,20p' src/app.ts" }, "legacy_exec"),
      state,
    )[0];
    const commandEnd = normalizeLineMessages(
      record("event_msg", {
        type: "exec_command_end",
        call_id: "legacy_exec",
        command: ["/bin/zsh", "-lc", "sed -n '1,20p' src/app.ts"],
        status: "completed",
      }),
      state,
    )[0];
    expect(commandEnd).toMatchObject({
      id: commandCall?.id,
      text: "Explored\nRead src/app.ts",
    });

    const imageCall = normalizeLineMessages(
      functionCall("view_image", { path: "/repo/screen.png" }, "legacy_image"),
      state,
    )[0];
    const imageEvent = normalizeLineMessages(
      record("event_msg", {
        type: "view_image_tool_call",
        call_id: "legacy_image",
        path: "/repo/screen.png",
      }),
      state,
    )[0];
    expect(imageEvent).toMatchObject({ id: imageCall?.id, text: "Viewed Image\nscreen.png" });

    expect(
      normalizeLineMessages(record("event_msg", { type: "error", message: "Network failed" }), state)[0]
        ?.text,
    ).toBe("Network failed");
    expect(
      normalizeLineMessages(record("event_msg", { type: "warning", message: "Retrying" }), state)[0]
        ?.text,
    ).toBe("Warning\nRetrying");
    expect(
      normalizeLineMessages(
        record("event_msg", {
          type: "deprecation_notice",
          summary: "Old option is deprecated",
          details: "Use the new option.",
        }),
        state,
      )[0]?.text,
    ).toBe("Old option is deprecated\nUse the new option.");
    expect(
      normalizeLineMessages(
        record("event_msg", {
          type: "entered_review_mode",
          user_facing_hint: "current changes",
        }),
        state,
      )[0]?.text,
    ).toBe("Code review started: current changes");
    expect(
      normalizeLineMessages(record("event_msg", { type: "exited_review_mode" }), state)[0]?.text,
    ).toBe("Code review finished");
  });

  test("tool discovery and collaboration plumbing do not leak as raw blocks", () => {
    const state = createCodexNormalizationState();
    expect(
      normalizeLineMessages(
        record("response_item", { type: "tool_search_call", call_id: "search_tools" }),
        state,
      ),
    ).toEqual([]);
    expect(
      normalizeLineMessages(functionCall("spawn_agent", { task_name: "audit" }, "call_spawn"), state),
    ).toEqual([]);
    expect(normalizeLineMessages(functionOutput("spawned", "call_spawn"), state)).toEqual([]);

    expect(
      normalizeLineMessages(functionCall("wait_agent", { timeout_ms: 30_000 }, "call_wait"), state)[0]
        ?.text,
    ).toBe("Waiting for agents");
    expect(
      normalizeLineMessages(
        functionOutput('{"message":"Wait timed out.","timed_out":true}', "call_wait"),
        state,
      )[0]?.text,
    ).toBe("Finished waiting\nNo agents completed yet");

    expect(
      normalizeLineMessages(
        record("event_msg", { type: "turn_aborted", reason: "interrupted" }),
        state,
      )[0]?.text,
    ).toBe(
      "Conversation interrupted - tell the model what to do differently. " +
        "Something went wrong? Hit `/feedback` to report the issue.",
    );
  });

  test("malformed and unknown records fail safely", () => {
    expect(normalizeLineMessages("not json")).toEqual([]);
    expect(normalizeLineMessages(record("event_msg", { type: "future_bookkeeping" }))).toEqual([]);
  });
});
