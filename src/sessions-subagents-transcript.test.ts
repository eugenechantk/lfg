import { describe, expect, test } from "bun:test";
import { normalizeLineMessages } from "./sessions.ts";

describe("Claude subagent transcript normalization", () => {
  test("renders a compact launch cell without the child prompt", () => {
    const line = JSON.stringify({
      type: "assistant",
      timestamp: "2026-08-20T04:00:00.000Z",
      uuid: "launch-row",
      message: {
        role: "assistant",
        content: [{
          type: "tool_use",
          id: "tool-secret",
          name: "Agent",
          input: {
            description: "Map studio app",
            prompt: "A long private prompt with implementation details",
            subagent_type: "Explore",
          },
        }],
      },
    });

    const messages = normalizeLineMessages(line);

    expect(messages).toHaveLength(1);
    expect(messages[0]).toMatchObject({ kind: "tool_use", text: "Started agent · Map studio app" });
    expect(messages[0].text).not.toContain("private prompt");
    expect(messages[0].text).not.toContain("tool-secret");
  });

  test("hides the internal asynchronous launch receipt", () => {
    const line = JSON.stringify({
      type: "user",
      timestamp: "2026-08-20T04:00:01.000Z",
      uuid: "receipt-row",
      message: {
        role: "user",
        content: [{
          type: "tool_result",
          tool_use_id: "tool-secret",
          content: [
            "Async agent launched successfully. (This tool result is internal metadata)",
            "agentId: secret-agent-id",
            "output_file: /private/tmp/secret-output.jsonl",
          ].join("\n"),
        }],
      },
    });

    expect(normalizeLineMessages(line)).toEqual([]);
  });
});
