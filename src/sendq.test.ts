import { describe, test, expect } from "bun:test";
import { reconcileQueuedCore, type QueuedMsg } from "./sendq.ts";

const GRACE = 10_000;

function qmsg(over: Partial<QueuedMsg> = {}): QueuedMsg {
  return {
    id: "m1",
    clientId: "c1",
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

// --- absorbed-mid-turn handling (2026-09-07) -------------------------------
// Claude Code absorbs mid-turn messages into the running turn; the transcript
// only records that as a queue-operation line, which the normaliser now turns
// into a user text turn. These cover the sendq side: instant promotion when
// that turn is journaled, sustained-idle gating, and refusing to re-drive on a
// window that cannot prove absence.
import { IdleConfirmer, promoteSurfacedCore } from "./sendq.ts";

describe("promoteSurfacedCore", () => {
  test("promotes the queued message whose text the user turn contains", () => {
    const hit = qmsg({ id: "hit", updatedAt: 0 });
    const miss = qmsg({ id: "miss", text: "something else entirely", updatedAt: 0 });
    const promoted = promoteSurfacedCore([hit, miss], hit.text, 5_000);
    expect(promoted.map((m) => m.id)).toEqual(["hit"]);
    expect(hit.status).toBe("delivered");
    expect(hit.updatedAt).toBe(5_000);
    expect(miss.status).toBe("queued");
  });

  test("only touches queued rows — pending, sending and terminal rows are left alone", () => {
    const rows = (["pending", "sending", "delivered", "failed"] as const).map((status) =>
      qmsg({ id: status, status }),
    );
    expect(promoteSurfacedCore(rows, rows[0].text, 1)).toEqual([]);
    for (const r of rows) expect(r.status).toBe(r.id as QueuedMsg["status"]);
  });

  test("ignores an empty or unrelated turn", () => {
    const m = qmsg();
    expect(promoteSurfacedCore([m], "", 1)).toEqual([]);
    expect(promoteSurfacedCore([m], "<task-notification>x</task-notification>", 1)).toEqual([]);
    expect(m.status).toBe("queued");
  });
});

describe("IdleConfirmer", () => {
  test("a single idle capture is not confirmation", () => {
    const c = new IdleConfirmer(3_000);
    expect(c.observe("s", true, 0)).toBe(false);
  });

  test("idle held across polls for the window confirms", () => {
    const c = new IdleConfirmer(3_000);
    c.observe("s", true, 0);
    expect(c.observe("s", true, 2_999)).toBe(false);
    expect(c.observe("s", true, 3_000)).toBe(true);
    expect(c.observe("s", true, 9_000)).toBe(true);
  });

  test("a busy capture (or our own delivery) resets the streak", () => {
    const c = new IdleConfirmer(3_000);
    c.observe("s", true, 0);
    expect(c.observe("s", false, 1_000)).toBe(false);
    expect(c.observe("s", true, 4_000)).toBe(false); // streak restarted at 4s
    expect(c.observe("s", true, 7_000)).toBe(true);
  });

  test("sessions are independent", () => {
    const c = new IdleConfirmer(3_000);
    c.observe("a", true, 0);
    expect(c.observe("b", true, 5_000)).toBe(false);
    expect(c.observe("a", true, 5_000)).toBe(true);
  });
});

describe("reconcileQueuedCore: transcript window coverage", () => {
  test("does not re-drive when the window starts after the message was queued", () => {
    // Window's oldest message is newer than the queued row: a long turn's tool
    // calls pushed the absorbed turn out of view. Absence is unproven — hold.
    const m = qmsg({ createdAt: 1_000, updatedAt: 1_000 });
    const { changed, kick } = reconcileQueuedCore([m], [], {
      idleConfirmed: true,
      now: GRACE + 20_000,
      windowStartTs: 50_000,
    });
    expect(changed).toBe(false);
    expect(kick).toBe(false);
    expect(m.status).toBe("queued");
  });

  test("re-drives when the window reaches back past the message", () => {
    const m = qmsg({ createdAt: 60_000, updatedAt: 60_000 });
    const { kick } = reconcileQueuedCore([m], [], {
      idleConfirmed: true,
      now: 60_000 + GRACE + 1,
      windowStartTs: 50_000,
    });
    expect(kick).toBe(true);
    expect(m.status).toBe("pending");
  });

  test("a surfaced message is promoted regardless of coverage", () => {
    const m = qmsg({ createdAt: 1_000, updatedAt: 1_000 });
    reconcileQueuedCore([m], [m.text], { idleConfirmed: true, now: 99_000, windowStartTs: 50_000 });
    expect(m.status).toBe("delivered");
  });
});
