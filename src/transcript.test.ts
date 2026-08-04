// The property that matters: a growing window turns "not in my window" (a
// silent miss that looked like missing data) into "not in the transcript".
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { head, scanBack, tail, windowFromSlice } from "./transcript.ts";

const dir = mkdtempSync(join(tmpdir(), "lfg-transcript-"));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

function write(name: string, lines: string[]): string {
  const p = join(dir, name);
  writeFileSync(p, lines.join("\n") + "\n");
  return p;
}

const pickUser = (line: string): string | null => {
  try {
    const x = JSON.parse(line) as { type?: string; text?: string };
    return x.type === "user" ? (x.text ?? null) : null;
  } catch {
    return null;
  }
};

describe("windowFromSlice", () => {
  test("drops the partial first line when the window starts mid-file", () => {
    const w = windowFromSlice('e":"abc"}\n{"type":"user"}\n', 4096);
    expect(w.lines).toEqual(['{"type":"user"}']);
    expect(w.atHead).toBe(false);
  });

  test("keeps every line when the window starts at byte 0", () => {
    const w = windowFromSlice('{"a":1}\n{"b":2}\n', 0);
    expect(w.lines).toEqual(['{"a":1}', '{"b":2}']);
    expect(w.atHead).toBe(true);
  });
});

describe("scanBack", () => {
  test("finds a match inside the first window", () => {
    const p = write("near.jsonl", [
      JSON.stringify({ type: "user", text: "old" }),
      JSON.stringify({ type: "assistant", text: "reply" }),
      JSON.stringify({ type: "user", text: "newest" }),
    ]);
    expect(scanBack(p, pickUser)).resolves.toBe("newest");
  });

  test("grows past a huge tail to find an answer a fixed window would miss", async () => {
    // One enormous tool output between the answer and the tail — the exact shape
    // that used to return null and render "no last message".
    const filler = JSON.stringify({ type: "assistant", text: "x".repeat(200_000) });
    const p = write("far.jsonl", [
      JSON.stringify({ type: "user", text: "buried" }),
      filler,
      filler,
    ]);
    // A fixed 64K window cannot reach it...
    const fixed = await tail(p, 64 * 1024);
    expect(fixed.lines.some((l) => pickUser(l) === "buried")).toBe(false);
    expect(fixed.atHead).toBe(false);
    // ...but scanBack starting at the same 64K grows until it does.
    await expect(scanBack(p, pickUser, { startBytes: 64 * 1024 })).resolves.toBe("buried");
  });

  test("null means absent from the transcript, not absent from the window", async () => {
    const p = write("none.jsonl", [
      JSON.stringify({ type: "assistant", text: "a".repeat(150_000) }),
      JSON.stringify({ type: "assistant", text: "b" }),
    ]);
    await expect(scanBack(p, pickUser, { startBytes: 1024 })).resolves.toBeNull();
  });

  test("a missing file yields null rather than throwing", async () => {
    await expect(scanBack(join(dir, "nope.jsonl"), pickUser)).resolves.toBeNull();
  });

  test("scans newest-first", async () => {
    const p = write("order.jsonl", [
      JSON.stringify({ type: "user", text: "first" }),
      JSON.stringify({ type: "user", text: "second" }),
    ]);
    await expect(scanBack(p, pickUser)).resolves.toBe("second");
  });
});

describe("head", () => {
  test("reads from the start of the file", async () => {
    const p = write("head.jsonl", [
      JSON.stringify({ type: "user", text: "first" }),
      JSON.stringify({ type: "user", text: "second" }),
    ]);
    const lines = await head(p, 64 * 1024);
    expect(pickUser(lines[0])).toBe("first");
  });
});
