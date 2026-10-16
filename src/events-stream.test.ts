import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Journal } from "./journal.ts";
import { journalEventStream } from "./events-stream.ts";

let dir: string;
let j: Journal;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "lfg-events-stream-"));
  j = Journal.open(join(dir, "journal.db"));
});

afterEach(() => {
  j.close();
  rmSync(dir, { recursive: true, force: true });
});

/** Read frames until `done` says stop or the deadline passes. */
async function readFrames(
  stream: ReadableStream<string>,
  done: (text: string) => boolean,
  ms = 1000,
): Promise<string> {
  const reader = stream.getReader();
  let text = "";
  const deadline = Date.now() + ms;
  try {
    while (!done(text) && Date.now() < deadline) {
      const next = await Promise.race([
        reader.read(),
        new Promise<null>((r) => setTimeout(() => r(null), Math.max(1, deadline - Date.now()))),
      ]);
      if (next === null || next.done) break;
      text += next.value;
    }
  } finally {
    await reader.cancel();
  }
  return text;
}

const rowIds = (text: string) => [...text.matchAll(/^id: (\d+)$/gm)].map((m) => Number(m[1]));

describe("journalEventStream", () => {
  test("an unserviceable cursor gets resync, then the events after the head", async () => {
    const before = j.append("s1", "busy", { sid: "s1", busy: true });
    // A cursor from a previous journal lifetime: ahead of head.
    expect(j.canServe(before + 50)).toBe(false);
    const stream = journalEventStream(j, before + 50, { heartbeatMs: 60_000 });
    // Appended after the client was told to adopt `before` as its cursor.
    setTimeout(() => {
      j.append("s1", "msg", { sid: "s1", m: { id: "reply" } });
      j.append("s1", "busy", { sid: "s1", busy: false });
    }, 20);
    const text = await readFrames(stream, (t) => rowIds(t).length >= 2);
    expect(text).toContain(`event: resync\ndata: {"head":${before}}`);
    expect(text).toContain(`: hb ${before}`);
    // The bug: the resync branch never subscribed, so this was [].
    expect(rowIds(text)).toEqual([before + 1, before + 2]);
    expect(text).toContain('"id":"reply"');
  });

  test("the resync head is never re-sent as an event", async () => {
    const head = j.append("s1", "busy", { sid: "s1", busy: true });
    const stream = journalEventStream(j, head + 1, { heartbeatMs: 60_000 });
    const text = await readFrames(stream, () => false, 100);
    expect(rowIds(text)).toEqual([]);
  });

  test("a serviceable cursor replays the backlog, then streams live", async () => {
    const a = j.append("s1", "busy", { sid: "s1", busy: true });
    const b = j.append("s1", "msg", { sid: "s1", m: { id: "m1" } });
    const stream = journalEventStream(j, a, { heartbeatMs: 60_000 });
    setTimeout(() => j.append("s1", "busy", { sid: "s1", busy: false }), 20);
    const text = await readFrames(stream, (t) => rowIds(t).length >= 2);
    expect(text).not.toContain("event: resync");
    expect(rowIds(text)).toEqual([b, b + 1]);
  });

  test("a cancelled stream unsubscribes from the journal", async () => {
    const start = j.listenerCount();
    const stream = journalEventStream(j, j.head() + 5, { heartbeatMs: 60_000 });
    expect(j.listenerCount()).toBe(start + 1);
    await stream.cancel();
    expect(j.listenerCount()).toBe(start);
  });
});
