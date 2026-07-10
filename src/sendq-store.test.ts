import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Journal } from "./journal.ts";
import {
  __journalQueueTerminalForTests,
  __resetSendqForTests,
  enqueueMessage,
  getMessage,
  getMessageByClientId,
  listQueue,
  recordImmediateMessage,
  setSendqJournal,
  setSendqStore,
  type QueuedMsg,
} from "./sendq.ts";
import { SendqStore, type SendqRowInput } from "./sendq-store.ts";

let dir: string;
let dbPath: string;
let store: SendqStore;

function row(over: Partial<SendqRowInput> = {}): SendqRowInput {
  return {
    id: "m1",
    sessionId: "s1",
    clientId: "c1",
    text: "hello",
    status: "pending",
    attempts: 0,
    createdAt: 1,
    updatedAt: 1,
    ...over,
  };
}

beforeEach(() => {
  __resetSendqForTests();
  dir = mkdtempSync(join(tmpdir(), "lfg-sendq-"));
  dbPath = join(dir, "journal.db");
  store = SendqStore.open(dbPath);
});

afterEach(() => {
  __resetSendqForTests();
  store.close();
  rmSync(dir, { recursive: true, force: true });
});

describe("SendqStore", () => {
  test("round-trips rows and upserts status mutations", () => {
    store.upsert(row());
    expect(store.findByClientId("s1", "c1")).toEqual({
      id: "m1",
      sessionId: "s1",
      clientId: "c1",
      text: "hello",
      status: "pending",
      error: null,
      attempts: 0,
      redeliveries: 0,
      createdAt: 1,
      updatedAt: 1,
    });

    store.upsert(row({ status: "failed", error: "no pane", attempts: 3, updatedAt: 2 }));
    expect(store.findById("m1")?.status).toBe("failed");
    expect(store.findById("m1")?.error).toBe("no pane");
    expect(store.findById("m1")?.attempts).toBe(3);
  });

  test("recovers non-terminal rows and downgrades sending to pending", () => {
    store.upsert(row({ id: "p", clientId: "cp", status: "pending", createdAt: 1 }));
    store.upsert(row({ id: "s", clientId: "cs", status: "sending", createdAt: 2 }));
    store.upsert(row({ id: "q", clientId: "cq", status: "queued", createdAt: 3 }));
    store.upsert(row({ id: "d", clientId: "cd", status: "delivered", createdAt: 4 }));

    setSendqStore(store);

    expect(listQueue("s1").map((m) => [m.id, m.status])).toEqual([
      ["p", "pending"],
      ["s", "pending"],
      ["q", "queued"],
    ]);
    expect(store.findById("s")?.status).toBe("pending");
  });

  test("dedupes enqueue by sessionId and clientId", () => {
    setSendqStore(store);

    const first = enqueueMessage("s1", "send once", {
      clientId: "client-1",
      autoKick: false,
    });
    const second = enqueueMessage("s1", "send once duplicate", {
      clientId: "client-1",
      autoKick: false,
    });

    expect(second.duplicate).toBe(true);
    expect(second.id).toBe(first.id);
    expect(second.text).toBe("send once");
    expect(listQueue("s1").map((m) => m.id)).toEqual([first.id]);
  });

  test("records immediate delivered rows for duplicate-safe non-queue sends", () => {
    setSendqStore(store);

    const first = recordImmediateMessage("s1", "headless send", "client-1");
    const second = getMessageByClientId("s1", "client-1");

    expect(second?.duplicate).toBe(true);
    expect(second?.id).toBe(first.id);
    expect(second?.status).toBe("delivered");
    expect(listQueue("s1")).toEqual([]);
  });

  test("prunes oldest delivered and failed rows while retaining queued rows", () => {
    for (let i = 0; i < 14; i++) {
      store.upsert(
        row({
          id: `t${i}`,
          clientId: `ct${i}`,
          status: i % 2 === 0 ? "delivered" : "failed",
          createdAt: i,
          updatedAt: i,
        }),
      );
    }
    store.upsert(row({ id: "queued", clientId: "cq", status: "queued", createdAt: 99, updatedAt: 99 }));

    const dropped = store.pruneTerminal("s1", 12);

    expect(dropped).toEqual(["t0", "t1"]);
    expect(store.findById("t0")).toBeNull();
    expect(store.findById("t2")?.status).toBe("delivered");
    expect(store.findById("queued")?.status).toBe("queued");
  });
});

describe("sendq durable integration", () => {
  test("journals delivered and failed terminal acks", () => {
    const journal = Journal.open(join(dir, "acks.db"));
    setSendqJournal(journal);
    const delivered: QueuedMsg = {
      id: "m1",
      clientId: "c1",
      text: "hi",
      status: "delivered",
      attempts: 1,
      createdAt: 1,
      updatedAt: 2,
    };
    const failed: QueuedMsg = {
      ...delivered,
      id: "m2",
      clientId: "c2",
      status: "failed",
      error: "no pane",
    };

    __journalQueueTerminalForTests("s1", delivered, "turn-1");
    __journalQueueTerminalForTests("s1", failed);

    const rows = journal.since(0);
    expect(rows.map((r) => r.type)).toEqual(["queue", "queue"]);
    expect(JSON.parse(rows[0].payload)).toEqual({
      kind: "delivered",
      clientId: "c1",
      msgId: "m1",
      userTurnId: "turn-1",
    });
    expect(JSON.parse(rows[1].payload)).toEqual({
      kind: "failed",
      clientId: "c2",
      msgId: "m2",
    });
    journal.close();
  });

  test("restart simulation reloads pending rows from the same database", () => {
    setSendqStore(store);
    const messages = [0, 1, 2].map((i) =>
      enqueueMessage("s1", `message ${i}`, {
        clientId: `client-${i}`,
        autoKick: false,
      }),
    );
    expect(listQueue("s1").map((m) => m.id)).toEqual(messages.map((m) => m.id));

    __resetSendqForTests();
    store.close();
    store = SendqStore.open(dbPath);
    setSendqStore(store);

    expect(listQueue("s1").map((m) => [m.id, m.text, m.status])).toEqual(
      messages.map((m, i) => [m.id, `message ${i}`, "pending"]),
    );
    expect(messages.map((m) => getMessage("s1", m.id)?.clientId)).toEqual([
      "client-0",
      "client-1",
      "client-2",
    ]);
  });
});
