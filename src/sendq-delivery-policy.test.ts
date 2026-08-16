import { beforeEach, describe, expect, test } from "bun:test";
import {
  __resetSendqForTests,
  composerTextHoldsNeedle,
  clearResolved,
  enqueueMessage,
  getMessage,
  pendingDeliveryDisposition,
  removeMessage,
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
