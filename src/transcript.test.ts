// The property that matters: a growing window turns "not in my window" (a
// silent miss that looked like missing data) into "not in the transcript".
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { head, scanBack, scanBackWithReader, tail, windowFromSlice } from "./transcript.ts";

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

  test("walks a large miss in disjoint bounded slices instead of rereading the growing tail", async () => {
    const rows = [
      JSON.stringify({ type: "user", text: "buried" }),
      ...Array.from({ length: 80 }, (_, i) =>
        JSON.stringify({ type: "assistant", text: `${i}:${"x".repeat(73)}` }),
      ),
    ];
    const text = rows.join("\n") + "\n";
    const bytes = Buffer.from(text);
    const reads: Array<[number, number]> = [];

    const found = await scanBackWithReader(
      bytes.length,
      pickUser,
      async (start, end) => {
        reads.push([start, end]);
        return bytes.subarray(start, end);
      },
      { startBytes: 64, maxStepBytes: 256 },
    );

    expect(found).toBe("buried");
    expect(reads.length).toBeGreaterThan(2);
    expect(reads.every(([start, end]) => end - start <= 256)).toBe(true);
    for (let i = 1; i < reads.length; i++) {
      expect(reads[i][1]).toBe(reads[i - 1][0]);
    }
    expect(reads.reduce((sum, [start, end]) => sum + end - start, 0)).toBe(bytes.length);
  });

  test("reassembles a JSONL record split across backward slice boundaries", async () => {
    const rows = [
      JSON.stringify({ type: "user", text: "crosses-boundaries-" + "z".repeat(90) }),
      JSON.stringify({ type: "assistant", text: "tail" }),
    ];
    const bytes = Buffer.from(rows.join("\n") + "\n");
    const found = await scanBackWithReader(
      bytes.length,
      pickUser,
      async (start, end) => bytes.subarray(start, end),
      { startBytes: 17, maxStepBytes: 23 },
    );
    expect(found).toBe("crosses-boundaries-" + "z".repeat(90));
  });

  test("maxScanBytes stops the walk early and reads nothing past the budget", async () => {
    const rows = [
      JSON.stringify({ type: "user", text: "buried" }),
      ...Array.from({ length: 80 }, (_, i) =>
        JSON.stringify({ type: "assistant", text: `${i}:${"x".repeat(73)}` }),
      ),
    ];
    const bytes = Buffer.from(rows.join("\n") + "\n");
    const reads: Array<[number, number]> = [];

    const found = await scanBackWithReader(
      bytes.length,
      pickUser,
      async (start, end) => {
        reads.push([start, end]);
        return bytes.subarray(start, end);
      },
      { startBytes: 64, maxStepBytes: 256, maxScanBytes: 512 },
    );

    // The only user row is at the head, far outside the budget.
    expect(found).toBe(null);
    const scanned = reads.reduce((sum, [start, end]) => sum + end - start, 0);
    expect(scanned).toBeLessThan(bytes.length);
    // A budget may overshoot by at most the range that straddles it, never more.
    expect(scanned).toBeLessThanOrEqual(512 + 256);
  });

  test("maxScanBytes still returns a hit that lies inside the budget", async () => {
    const rows = [
      JSON.stringify({ type: "assistant", text: "old" }),
      JSON.stringify({ type: "user", text: "recent" }),
      JSON.stringify({ type: "assistant", text: "newest" }),
    ];
    const bytes = Buffer.from(rows.join("\n") + "\n");
    const found = await scanBackWithReader(
      bytes.length,
      pickUser,
      async (start, end) => bytes.subarray(start, end),
      { startBytes: 16, maxStepBytes: 32, maxScanBytes: bytes.length },
    );
    expect(found).toBe("recent");
  });

  test("omitting maxScanBytes keeps the walk-to-the-head guarantee", async () => {
    const rows = [
      JSON.stringify({ type: "user", text: "buried" }),
      ...Array.from({ length: 80 }, (_, i) =>
        JSON.stringify({ type: "assistant", text: `${i}:${"x".repeat(73)}` }),
      ),
    ];
    const bytes = Buffer.from(rows.join("\n") + "\n");
    const found = await scanBackWithReader(
      bytes.length,
      pickUser,
      async (start, end) => bytes.subarray(start, end),
      { startBytes: 64, maxStepBytes: 256 },
    );
    expect(found).toBe("buried");
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
