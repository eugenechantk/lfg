import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import {
  __resetSendqForTests, enqueueMessage, getMessage, listQueue, noteSurfacedUserTurn,
  retractMessage, setSendqStore, sendNow,
} from "./sendq.ts";
import { SendqStore } from "./sendq-store.ts";
import type { NativeQueueRetraction } from "./native-queue.ts";

let store: SendqStore;
beforeEach(() => { __resetSendqForTests(); store = new SendqStore(new Database(":memory:")); setSendqStore(store); });
afterEach(() => { __resetSendqForTests(); store.close(); });

function queued(text: string, clientId = text) {
  const row = enqueueMessage("s", text, { autoKick: false, clientId });
  row.status = "queued";
  store.upsert({ ...row, sessionId: "s" });
  return row;
}
function dependencies(retract: (opts: NativeQueueRetraction) => Promise<boolean>) {
  return {
    session: async () => ({ agent: "claude", tmuxTarget: "test:0.0" }),
    transcript: async () => "/test/transcript.jsonl", retract, autoKick: false,
  };
}

describe("provider-aware queue removal and editing", () => {
  test("the row stays durable until native deletion confirms", async () => {
    const row = queued("original");
    expect(await retractMessage("s", row.id, true, dependencies(async opts => {
      expect(getMessage("s", row.id)?.status).toBe("queued");
      expect(store.findById(row.id)?.status).toBe("queued");
      expect(opts.text).toBe("original");
      return true;
    }))).toBe(true);
    expect(getMessage("s", row.id)).toBeNull();
    expect(store.findById(row.id)).toBeNull();
  });

  test("Claude recall preserves siblings, duplicate text, and terminal-originated input", async () => {
    const first = queued("same", "first");
    const selected = queued("same", "selected");
    const third = queued("keep\nexact whitespace  ");
    const held = enqueueMessage("s", "not submitted yet", { autoKick: false });
    expect(await retractMessage("s", selected.id, true, dependencies(async opts => {
      opts.onRecalled(["same", "same", "from terminal", "keep\nexact whitespace  "]);
      // Retained inputs have already been persisted before the TUI is cleared.
      expect(store.findById(first.id)?.status).toBe("pending");
      expect(store.findById(third.id)?.text).toBe("keep\nexact whitespace  ");
      return true;
    }))).toBe(true);
    expect(listQueue("s").map(row => row.text)).toEqual(["same", "from terminal", "keep\nexact whitespace  ", "not submitted yet"]);
    expect(getMessage("s", held.id)?.status).toBe("pending");
  });

  test("failed or uncertain retraction keeps the row", async () => {
    const row = queued("keep me");
    expect(await retractMessage("s", row.id, false, dependencies(async () => false))).toBe(false);
    expect(getMessage("s", row.id)?.status).toBe("queued");
    expect(await retractMessage("s", row.id, false, dependencies(async () => { throw Error("timeout"); }))).toBe(false);
    expect(store.findById(row.id)?.status).toBe("queued");
  });

  test("consumption during retraction wins over cancellation", async () => {
    const row = queued("delivery race");
    expect(await retractMessage("s", row.id, true, dependencies(async () => {
      noteSurfacedUserTurn("s", { id: "real-turn", role: "user", kind: "text", text: row.text, ts: Date.now() });
      return true;
    }))).toBe(false);
    expect(getMessage("s", row.id)?.status).toBe("delivered");
  });

  test("a delivered receipt can be dismissed but never returned for editing", async () => {
    const row = queued("already consumed");
    row.status = "delivered";
    const deps = dependencies(async () => { throw Error("must not touch the provider"); });
    expect(await retractMessage("s", row.id, true, deps)).toBe(false);
    expect(getMessage("s", row.id)).not.toBeNull();
    expect(await retractMessage("s", row.id, false, deps)).toBe(true);
  });

  test("an in-flight submission settles before native removal starts", async () => {
    const row = queued("in flight");
    row.status = "sending";
    const removal = retractMessage("s", row.id, true, dependencies(async () => true));
    row.status = "queued";
    expect(await removal).toBe(true);
  });

  test("another remove and send-now cannot interfere with native recall", async () => {
    const row = queued("selected");
    let release!: () => void;
    const held = new Promise<void>(resolve => { release = resolve; });
    const removal = retractMessage("s", row.id, true, dependencies(async () => { await held; return true; }));
    await Bun.sleep(0);
    expect(await retractMessage("s", row.id, true, dependencies(async () => true))).toBe(false);
    expect(await sendNow("s", row.id)).toBe(false);
    release();
    expect(await removal).toBe(true);
  });

  test("native recall waits for another row already typing into the shared composer", async () => {
    const selected = queued("selected native entry");
    const active = queued("another in-flight send");
    active.status = "sending";
    let recalled = false;
    const removal = retractMessage("s", selected.id, true, dependencies(async () => {
      expect(active.status).not.toBe("sending");
      recalled = true;
      return true;
    }));
    await Bun.sleep(10);
    expect(recalled).toBe(false);
    active.status = "queued";
    expect(await removal).toBe(true);
    expect(getMessage("s", active.id)?.status).toBe("queued");
  });

  test("a failed composer clear keeps every recalled input recoverable", async () => {
    const row = queued("selected");
    expect(await retractMessage("s", row.id, true, dependencies(async opts => {
      opts.onRecalled(["selected", "terminal sibling"]);
      return false;
    }))).toBe(false);
    expect(getMessage("s", row.id)?.status).toBe("pending");
    expect(listQueue("s").map(m => m.text)).toEqual(["selected", "terminal sibling"]);
    expect(store.recoverable().map(m => m.text)).toEqual(["selected", "terminal sibling"]);
  });
});
