// SendUserFile is how an agent hands a produced file (chart, screenshot,
// report) to the user. As a plain tool line the paths were buried in JSON and
// no client rendered them, so the deliverable was the one thing you couldn't
// open. These drive the real transcript line shapes — copied verbatim from a
// SendUserFile turn under ~/.claude/projects — through the normalizer and
// assert the call becomes prose + markdown file references the client's media
// scanner already knows how to attach.
import { describe, expect, test } from "bun:test";
import { normalizeLineMessages, sendUserFileText } from "./sessions.ts";

function useLine(input: unknown): string {
  return JSON.stringify({
    type: "assistant",
    uuid: "u1",
    timestamp: new Date(0).toISOString(),
    message: {
      role: "assistant",
      content: [{ type: "tool_use", id: "toolu_1", name: "SendUserFile", input }],
    },
  });
}

function resultLine(paths: string[]): string {
  return JSON.stringify({
    type: "user",
    uuid: "u2",
    timestamp: new Date(0).toISOString(),
    message: {
      role: "user",
      content: [
        {
          tool_use_id: "toolu_1",
          type: "tool_result",
          content: `${paths.length} files delivered to user.\n${paths.map((p) => `  ${p} → file_uuid: abc`).join("\n")}`,
        },
      ],
    },
    toolUseResult: {
      caption: "cap",
      display: "render",
      attachments: paths.map((path) => ({ path, size: 1, isImage: false, pathValidated: true })),
    },
  });
}

describe("SendUserFile renders as content", () => {
  test("caption becomes prose and each file a markdown reference", () => {
    const msgs = normalizeLineMessages(
      useLine({
        files: ["/Users/e/dev/out/chart.png", "/Users/e/dev/out/report.pdf"],
        caption: "Revenue chart and the write-up.",
        status: "normal",
        display: "render",
      }),
    );
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.kind).toBe("text");
    expect(msgs[0]!.role).toBe("assistant");
    // Images use image syntax (clients strip it from prose once attached);
    // everything else stays a link so the filename is tappable inline too.
    expect(msgs[0]!.text).toBe(
      "Revenue chart and the write-up.\n\n![chart.png](/Users/e/dev/out/chart.png)\n\n[report.pdf](/Users/e/dev/out/report.pdf)",
    );
  });

  test("no caption still yields the file references", () => {
    const msgs = normalizeLineMessages(useLine({ files: ["/tmp/demo.mp4"] }));
    expect(msgs[0]!.kind).toBe("text");
    expect(msgs[0]!.text).toBe("[demo.mp4](/tmp/demo.mp4)");
  });

  test("the delivery receipt is dropped instead of echoing the paths", () => {
    // The receipt restates every path plus an upload uuid directly beneath the
    // attachments — pure duplication, and unreadable as a raw tool line.
    expect(normalizeLineMessages(resultLine(["/Users/e/dev/out/chart.png"]))).toEqual([]);
  });

  test("an ordinary tool_result is untouched", () => {
    const line = JSON.stringify({
      type: "user",
      uuid: "u3",
      timestamp: new Date(0).toISOString(),
      message: {
        role: "user",
        content: [{ tool_use_id: "toolu_9", type: "tool_result", content: "ok" }],
      },
      toolUseResult: { stdout: "ok" },
    });
    const msgs = normalizeLineMessages(line);
    expect(msgs).toHaveLength(1);
    expect(msgs[0]!.kind).toBe("tool_result");
  });

  test("a malformed call falls back to the normal tool line", () => {
    // No usable files — better a JSON tool line than a silently empty turn.
    for (const bad of [{}, { files: [] }, { files: "nope" }, null]) {
      const msgs = normalizeLineMessages(useLine(bad));
      expect(msgs).toHaveLength(1);
      expect(msgs[0]!.kind).toBe("tool_use");
    }
  });

  test("other tools are unaffected", () => {
    const line = JSON.stringify({
      type: "assistant",
      uuid: "u4",
      timestamp: new Date(0).toISOString(),
      message: {
        role: "assistant",
        content: [{ type: "tool_use", id: "t", name: "Read", input: { file_path: "/a/b.ts" } }],
      },
    });
    expect(normalizeLineMessages(line)[0]!.kind).toBe("tool_use");
  });

  test("sendUserFileText ignores blank entries and trims paths", () => {
    expect(sendUserFileText({ files: ["  /tmp/a.png  ", "", "   "], caption: "  " })).toBe(
      "![a.png](/tmp/a.png)",
    );
  });
});

describe("paths containing spaces", () => {
  // A working directory like `~/dev/inbox/AI girl game` is ordinary. `(/a/b c.png)`
  // is not a link destination to a spec-following markdown parser, and a bare
  // `)` would end the destination early, so those paths go in angle brackets.
  const spaced = "/Users/e/dev/inbox/AI girl game/creative/storyboard-v3.png";

  test("a path with a space is wrapped in CommonMark angle brackets", () => {
    expect(sendUserFileText({ files: [spaced] })).toBe(`![storyboard-v3.png](<${spaced}>)`);
  });

  test("a path with a paren is wrapped too", () => {
    const p = "/Users/e/out/clip (final).mp4";
    expect(sendUserFileText({ files: [p] })).toBe(`[clip (final).mp4](<${p}>)`);
  });

  test("an ordinary path keeps the bare form older clients already parse", () => {
    expect(sendUserFileText({ files: ["/Users/e/out/chart.png"] })).toBe(
      "![chart.png](/Users/e/out/chart.png)",
    );
  });

  test("a path already containing angle brackets stays bare rather than corrupt", () => {
    const p = "/Users/e/out/a<b>c.png";
    expect(sendUserFileText({ files: [p] })).toBe(`![a<b>c.png](${p})`);
  });
});
