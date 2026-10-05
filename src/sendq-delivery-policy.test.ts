import { beforeEach, describe, expect, test } from "bun:test";
import {
  __resetSendqForTests,
  composerTextHoldsNeedle,
  clearResolved,
  claudeInterruptResolution,
  enqueueMessage,
  getMessage,
  pendingDeliveryDisposition,
  removeMessage,
  sendNowPlan,
} from "./sendq.ts";

describe("pending delivery policy", () => {
  test("Claude keeps using its native next-turn queue", () => {
    expect(pendingDeliveryDisposition("claude", false)).toBe("deliver");
    expect(pendingDeliveryDisposition("claude", true)).toBe("deliver");
  });

  test("Codex follow-ups wait in LFG until the active turn ends", () => {
    expect(pendingDeliveryDisposition("codex", true)).toBe("hold");
    expect(pendingDeliveryDisposition("codex", false)).toBe("deliver");
  });

  test("only an explicit send-now lets a busy Codex row reach its native queue", () => {
    expect(pendingDeliveryDisposition("codex", true, true)).toBe("deliver");
  });
});

describe("send-now sequencing policy", () => {
  test("busy Codex queues the replacement before Escape", () => {
    expect(sendNowPlan("codex", true, "pending")).toBe("deliver-then-interrupt");
  });

  test("busy Claude pending rows interrupt before first delivery", () => {
    expect(sendNowPlan("claude", true, "pending")).toBe("interrupt-then-deliver");
  });

  test("busy Claude queued rows resolve the native outcome after interrupting", () => {
    expect(sendNowPlan("claude", true, "queued")).toBe("interrupt-then-resolve");
  });

  test("an already-native-queued Codex message only needs the interrupt", () => {
    expect(sendNowPlan("codex", true, "queued")).toBe("interrupt-only");
  });

  test("a session that became idle is delivered without a stray Escape", () => {
    expect(sendNowPlan("codex", false, "pending")).toBe("deliver-only");
    expect(sendNowPlan("codex", false, "queued")).toBe("deliver-only");
    expect(sendNowPlan("claude", false, "pending")).toBe("deliver-only");
    expect(sendNowPlan("claude", false, "queued")).toBe("deliver-only");
  });
});

describe("Claude queued-message interrupt resolution", () => {
  const text = "Reply exactly NEW_DONE.";
  const line = (value: unknown) => JSON.stringify(value);
  const marker = line({
    type: "user",
    timestamp: "2026-09-30T06:38:03.883Z",
    message: { role: "user", content: [{ type: "text", text: "[Request interrupted by user]" }] },
  });

  test("an absorbed queue row belongs to the aborted turn and needs redelivery", () => {
    const lines = [
      line({ type: "queue-operation", operation: "enqueue", timestamp: "2026-09-30T06:38:01.499Z", content: text }),
      line({ type: "queue-operation", operation: "remove", reason: "absorbed_mid_turn", timestamp: "2026-09-30T06:38:03.775Z", content: text }),
      marker,
    ];
    expect(claudeInterruptResolution(lines, text, Date.parse("2026-09-30T06:38:01Z")))
      .toEqual({ kind: "absorbed" });
  });

  test("a native dequeue after Escape is already the fresh turn", () => {
    const lines = [
      line({ type: "queue-operation", operation: "enqueue", timestamp: "2026-09-30T06:38:01.499Z", content: text }),
      line({ type: "queue-operation", operation: "dequeue", timestamp: "2026-09-30T06:38:03.800Z" }),
      marker,
      line({
        type: "user",
        uuid: "fresh-turn",
        timestamp: "2026-09-30T06:38:03.999Z",
        promptSource: "queued",
        message: { role: "user", content: text },
      }),
    ];
    expect(claudeInterruptResolution(lines, text, Date.parse("2026-09-30T06:38:01Z")))
      .toEqual({ kind: "started", userTurnId: "fresh-turn" });
  });

  test("waits when the interrupt marker landed but Claude has not resolved its native queue yet", () => {
    const lines = [
      line({ type: "queue-operation", operation: "enqueue", timestamp: "2026-09-30T06:38:01.499Z", content: text }),
      marker,
    ];
    expect(claudeInterruptResolution(lines, text, Date.parse("2026-09-30T06:38:01Z")))
      .toEqual({ kind: "waiting-native-start" });
  });

  test("ignores matching history from before this queue row", () => {
    const old = line({
      type: "user",
      uuid: "old-turn",
      timestamp: "2026-09-30T06:30:00.000Z",
      promptSource: "typed",
      message: { role: "user", content: text },
    });
    expect(claudeInterruptResolution([old, marker], text, Date.parse("2026-09-30T06:38:01Z")))
      .toEqual({ kind: "waiting-native-start" });
  });
});

describe("composer insertion confirmation", () => {
  test("recognizes a literal normalized prefix", () => {
    expect(composerTextHoldsNeedle("first  line\nsecond line", "first line second")).toBe(true);
  });

  test("recognizes Claude and Codex collapsed paste markers", () => {
    expect(composerTextHoldsNeedle("[Pasted text +42 lines]", "not visible")).toBe(true);
    expect(composerTextHoldsNeedle("[Pasted Content 18324 chars]", "not visible")).toBe(true);
  });

  test("does not confuse an unrelated placeholder with the draft", () => {
    expect(composerTextHoldsNeedle("Write tests for @filename", "ship the release")).toBe(false);
  });
});

describe("native-queued message actions", () => {
  beforeEach(() => __resetSendqForTests());

  test("a message still held by LFG can be removed", () => {
    const msg = enqueueMessage("s1", "edit me", { autoKick: false });
    expect(removeMessage("s1", msg.id)).toBe(true);
    expect(getMessage("s1", msg.id)).toBeNull();
  });

  test("a message committed to the agent queue cannot be falsely removed", () => {
    const msg = enqueueMessage("s1", "already committed", { autoKick: false });
    msg.status = "queued";
    expect(removeMessage("s1", msg.id)).toBe(false);
    expect(getMessage("s1", msg.id)?.status).toBe("queued");
  });

  test("a message mid-keystroke cannot be falsely removed", () => {
    const msg = enqueueMessage("s1", "typing right now", { autoKick: false });
    msg.status = "sending";
    expect(removeMessage("s1", msg.id)).toBe(false);
    expect(getMessage("s1", msg.id)?.status).toBe("sending");
  });

  // A delivered row is a receipt for a turn the agent already ran, not pending
  // work. Rejecting its removal left the client with an undeletable bubble and
  // no honest way to dismiss it.
  test("a delivered message can be dismissed", () => {
    const msg = enqueueMessage("s1", "already ran", { autoKick: false });
    msg.status = "delivered";
    expect(removeMessage("s1", msg.id)).toBe(true);
    expect(getMessage("s1", msg.id)).toBeNull();
  });

  test("a failed message can be dismissed", () => {
    const msg = enqueueMessage("s1", "never landed", { autoKick: false });
    msg.status = "failed";
    expect(removeMessage("s1", msg.id)).toBe(true);
    expect(getMessage("s1", msg.id)).toBeNull();
  });

  test("clearing resolved rows retains a message committed to the agent queue", () => {
    const msg = enqueueMessage("s1", "still waiting natively", { autoKick: false });
    msg.status = "queued";
    expect(clearResolved("s1")).toBe(0);
    expect(getMessage("s1", msg.id)?.status).toBe("queued");
  });
});
