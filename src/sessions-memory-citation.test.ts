import { describe, expect, test } from "bun:test";
import { normalizeLineMessages } from "./sessions.ts";

const timestamp = "2026-09-23T12:00:00.000Z";
const citationBlock = `<oai-mem-citation>
<citation_entries>
MEMORY.md:265-268|note=[LFG iOS session and transcript architecture scope]
MEMORY.md:328-333|note=[LFG transcript normalization and client verification guidance]
</citation_entries>
<rollout_ids>
01a07641-e0cf-7660-8394-3058cbd461dc
01a093a1-1ae0-7430-88cf-dbe2c8144ccb
</rollout_ids>
</oai-mem-citation>`;

function responseAssistant(text: string): string {
  return JSON.stringify({
    timestamp,
    type: "response_item",
    payload: {
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text }],
    },
  });
}

describe("Codex memory citation transcript rows", () => {
  test("splits the supplied block from assistant prose into a readable citation message", () => {
    const messages = normalizeLineMessages(
      responseAssistant(`Implemented and verified.\n\n${citationBlock}`),
    );

    expect(messages.map(({ role, kind, text }) => ({ role, kind, text }))).toEqual([
      { role: "assistant", kind: "text", text: "Implemented and verified." },
      {
        role: "assistant",
        kind: "memory_citation",
        text:
          "Memory sources\n" +
          "MEMORY.md:265-268\tLFG iOS session and transcript architecture scope\n" +
          "MEMORY.md:328-333\tLFG transcript normalization and client verification guidance\n" +
          "Prior sessions: 2",
      },
    ]);
    expect(messages[1].text).not.toContain("<oai-mem-citation>");
    expect(messages[1].text).not.toContain("01a07641");
  });

  test("supports a standalone citation block", () => {
    const messages = normalizeLineMessages(responseAssistant(citationBlock));

    expect(messages).toHaveLength(1);
    expect(messages[0]).toMatchObject({ role: "assistant", kind: "memory_citation" });
  });

  test("preserves prose around the block in source order with unique ids", () => {
    const messages = normalizeLineMessages(
      responseAssistant(`Before\n\n${citationBlock}\n\nAfter`),
    );

    expect(messages.map(({ kind, text }) => ({ kind, text: text.split("\n")[0] }))).toEqual([
      { kind: "text", text: "Before" },
      { kind: "memory_citation", text: "Memory sources" },
      { kind: "text", text: "After" },
    ]);
    expect(new Set(messages.map((message) => message.id)).size).toBe(3);
  });

  test("leaves malformed and unrelated assistant markup untouched", () => {
    const malformed = `<oai-mem-citation>\n<citation_entries>\nMEMORY.md:1-2|note=[Incomplete]`;
    const unrelated = "Use <citation_entries> as the container name.";

    expect(normalizeLineMessages(responseAssistant(malformed))[0]).toMatchObject({
      kind: "text",
      text: malformed,
    });
    expect(normalizeLineMessages(responseAssistant(unrelated))[0]).toMatchObject({
      kind: "text",
      text: unrelated,
    });
  });
});
