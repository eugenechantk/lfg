import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { messagePage, recentMessages } from "./sessions.ts";

// `recentMessages(path, n, { maxBytes: null })` streams the transcript instead
// of materializing it as one string — a 511 MB Codex rollout otherwise peaked
// near 2 GB of RSS per call and pushed `lfg serve` past its 4 GB ceiling, which
// drops every /api/events stream and reads on the phone as "host disconnected".
//
// The invariant these tests hold is equality with the string path. Passing a
// `maxBytes` larger than the file makes the bounded reader start at byte 0, so
// both paths see the exact same bytes and must produce the exact same messages.
const WHOLE_FILE = 1024 * 1024 * 1024;

const timestamp = "2026-08-14T09:11:29.541Z";

function record(type: string, payload: Record<string, unknown>): string {
  return JSON.stringify({ timestamp, type, payload });
}

function userMessage(text: string): string {
  return record("event_msg", { type: "user_message", message: text });
}

function withFixture(lines: string[], run: (path: string) => Promise<void>) {
  const dir = mkdtempSync(join(tmpdir(), "lfg-msg-stream-"));
  const path = join(dir, "rollout.jsonl");
  try {
    writeFileSync(path, lines.join("\n"));
    return run(path).finally(() => rmSync(dir, { recursive: true, force: true }));
  } catch (err) {
    rmSync(dir, { recursive: true, force: true });
    throw err;
  }
}

async function bothReaders(path: string) {
  const streamed = await recentMessages(path, 0, { maxBytes: null });
  const wholeString = await recentMessages(path, 0, { maxBytes: WHOLE_FILE });
  return { streamed, wholeString };
}

describe("streamed whole-transcript reads", () => {
  test("matches the string reader on a plain transcript", async () => {
    await withFixture(
      [
        record("session_meta", { cwd: "/repo" }),
        userMessage("first"),
        userMessage("second"),
        userMessage("third"),
        "",
      ],
      async (path) => {
        const { streamed, wholeString } = await bothReaders(path);
        expect(streamed.map((m) => m.text)).toEqual(["first", "second", "third"]);
        expect(streamed).toEqual(wholeString);
      },
    );
  });

  test("reassembles records that span many stream chunks", async () => {
    // Real rollouts average ~137 KB per row; several megabytes guarantees the
    // record is split across chunk boundaries and must be carried and rejoined.
    const huge = "x".repeat(5 * 1024 * 1024);
    await withFixture(
      [userMessage("before"), userMessage(huge), userMessage("after"), ""],
      async (path) => {
        const { streamed, wholeString } = await bothReaders(path);
        expect(streamed.map((m) => m.text)).toEqual(["before", huge, "after"]);
        expect(streamed).toEqual(wholeString);
      },
    );
  });

  test("keeps multi-byte characters intact across a carried boundary", async () => {
    // Emoji are 4 UTF-8 bytes, so padding to an odd length all but guarantees
    // one lands astride a chunk edge. Decoding halves independently would
    // corrupt the JSON and silently drop the whole record.
    const wide = `${"漢字🙂".repeat(400_000)}末`;
    await withFixture([userMessage(wide), userMessage("tail"), ""], async (path) => {
      const { streamed, wholeString } = await bothReaders(path);
      expect(streamed.map((m) => m.text)).toEqual([wide, "tail"]);
      expect(streamed).toEqual(wholeString);
    });
  });

  test("keeps the final record when the file has no trailing newline", async () => {
    await withFixture([userMessage("only"), userMessage("last")], async (path) => {
      const { streamed, wholeString } = await bothReaders(path);
      expect(streamed.map((m) => m.text)).toEqual(["only", "last"]);
      expect(streamed).toEqual(wholeString);
    });
  });

  test("returns nothing for an empty transcript", async () => {
    await withFixture([""], async (path) => {
      const { streamed, wholeString } = await bothReaders(path);
      expect(streamed).toEqual([]);
      expect(streamed).toEqual(wholeString);
    });
  });
});

describe("byte-bounded backward transcript pages", () => {
  test("walks the full transcript without duplicates while keeping each messages array bounded", async () => {
    await withFixture(
      Array.from({ length: 7 }, (_, index) => userMessage(`${index}:${"x".repeat(400)}`)),
      async (path) => {
        const maxBytes = 1_100;
        const received: string[] = [];
        let before: number | null = null;

        do {
          const page = await messagePage(path, { before, limit: 7, maxBytes });
          expect(Buffer.byteLength(JSON.stringify(page.messages))).toBeLessThanOrEqual(maxBytes);
          expect(page.messages.length).toBeGreaterThan(0);
          received.unshift(...page.messages.map((message) => message.text));
          before = page.nextBefore;
        } while (before != null);

        expect(received).toEqual(
          Array.from({ length: 7 }, (_, index) => `${index}:${"x".repeat(400)}`),
        );
      },
    );
  });

  test("returns one oversized message so the cursor always makes progress", async () => {
    await withFixture([userMessage("first"), userMessage("x".repeat(4_000))], async (path) => {
      const page = await messagePage(path, { limit: 2, maxBytes: 32 });

      expect(page.messages.map((message) => message.text)).toEqual(["x".repeat(4_000)]);
      expect(page.nextBefore).toBe(1);
    });
  });
});
