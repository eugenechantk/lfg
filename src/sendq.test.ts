import { describe, test, expect } from "bun:test";
import { reconcileQueuedCore, type QueuedMsg } from "./sendq.ts";

const GRACE = 10_000;

function qmsg(over: Partial<QueuedMsg> = {}): QueuedMsg {
  return {
    id: "m1",
    text: "Actually never mind we can use dc instead",
    status: "queued",
    attempts: 1,
    createdAt: 0,
    updatedAt: 0,
    ...over,
  };
}

describe("reconcileQueuedCore", () => {
  test("promotes a queued message that has surfaced as a user turn", () => {
    const m = qmsg({ updatedAt: 1_000 });
    const { changed, kick } = reconcileQueuedCore([m], [m.text], {
      idleConfirmed: false,
      now: 2_000,
    });
    expect(changed).toBe(true);
    expect(kick).toBe(false);
    expect(m.status).toBe("delivered");
  });

  test("promotion wins over re-drive even when idle + aged", () => {
    // A message that both surfaced AND is old/idle must be delivered, not re-driven.
    const m = qmsg({ updatedAt: 0 });
    reconcileQueuedCore([m], [m.text], { idleConfirmed: true, now: GRACE + 5_000 });
    expect(m.status).toBe("delivered");
  });

  test("re-drives an aged queued message when the agent is idle (not picked up)", () => {
    const m = qmsg({ updatedAt: 0 });
    const { changed, kick } = reconcileQueuedCore([m], [], {
      idleConfirmed: true,
      now: GRACE + 1,
    });
    expect(changed).toBe(true);
    expect(kick).toBe(true); // caller must re-run the delivery loop
    expect(m.status).toBe("pending"); // reset so deliver() re-submits it
    expect(m.attempts).toBe(0); // fresh per-call retry budget
    expect(m.redeliveries).toBe(1);
  });

  test("fails only after the re-drive cap is exhausted", () => {
    const m = qmsg({ updatedAt: 0, redeliveries: 2 }); // MAX_REDELIVERIES
    const { changed, kick } = reconcileQueuedCore([m], [], {
      idleConfirmed: true,
      now: GRACE + 1,
    });
    expect(changed).toBe(true);
    expect(kick).toBe(false);
    expect(m.status).toBe("failed");
    expect(m.error).toMatch(/never picked this up/i);
  });

  test("does NOT re-drive while the agent is busy — still legitimately queued", () => {
    const m = qmsg({ updatedAt: 0 });
    const { changed, kick } = reconcileQueuedCore([m], [], {
      idleConfirmed: false,
      now: GRACE + 60_000,
    });
    expect(changed).toBe(false);
    expect(kick).toBe(false);
    expect(m.status).toBe("queued");
  });

  test("does NOT re-drive within the grace window even when idle", () => {
    const m = qmsg({ updatedAt: 0 });
    const { changed } = reconcileQueuedCore([m], [], {
      idleConfirmed: true,
      now: GRACE - 1,
    });
    expect(changed).toBe(false);
    expect(m.status).toBe("queued");
  });

  test("leaves already-terminal messages untouched", () => {
    const delivered = qmsg({ id: "d", status: "delivered", updatedAt: 0 });
    const failed = qmsg({ id: "f", status: "failed", updatedAt: 0 });
    const { changed } = reconcileQueuedCore([delivered, failed], [], {
      idleConfirmed: true,
      now: GRACE + 100_000,
    });
    expect(changed).toBe(false);
    expect(delivered.status).toBe("delivered");
    expect(failed.status).toBe("failed");
  });

  test("matches on a normalized prefix (whitespace-collapsed, wrapped turn)", () => {
    const m = qmsg({ text: "Send me the link please", updatedAt: 0 });
    const { changed } = reconcileQueuedCore([m], ["Send  me   the\nlink please now"], {
      idleConfirmed: false,
      now: 1,
    });
    expect(changed).toBe(true);
    expect(m.status).toBe("delivered");
  });
});
