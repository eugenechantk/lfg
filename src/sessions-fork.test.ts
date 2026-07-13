import { afterAll, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { snapshotMessages } from "./sessions.ts";

const dir = mkdtempSync(join(tmpdir(), "lfg-sessions-fork-test-"));
const transcript = join(dir, "source.jsonl");

beforeEach(() => {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
});

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

function line(id: string, text: string): string {
  return JSON.stringify({
    type: "user",
    uuid: id,
    timestamp: "2026-07-13T00:00:00.000Z",
    message: { role: "user", content: text },
  }) + "\n";
}

describe("snapshotMessages", () => {
  test("drops a trailing partial line when the cap lands mid-line", async () => {
    const first = line("m1", "first");
    const second = line("m2", "second");
    writeFileSync(transcript, first + second);

    const msgs = await snapshotMessages(transcript, 0, {
      maxBytes: first.length + Math.floor(second.length / 2),
    });

    expect(msgs.map((m) => m.text)).toEqual(["first"]);
  });

  test("serves the full transcript when the cap reaches the file size", async () => {
    const first = line("m1", "first");
    const second = line("m2", "second");
    writeFileSync(transcript, first + second);

    const msgs = await snapshotMessages(transcript, 0, {
      maxBytes: first.length + second.length,
    });

    expect(msgs.map((m) => m.text)).toEqual(["first", "second"]);
  });
});
