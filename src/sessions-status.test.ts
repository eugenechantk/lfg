// computeStatus is reached through normalizeLineMessages + listSessions, so
// these drive it the way the server does: real transcript line shapes in, a
// status classification out. Line shapes are verbatim from real transcripts
// under ~/.claude/projects (error="authentication_failed", apiErrorStatus=403).
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { lastAssistantForTest, normalizeLineMessages, statusForTest } from "./sessions.ts";
import { sessionDisplayState } from "./session-state.ts";

function assistantLine(extra: Record<string, unknown>, text: string): string {
  return JSON.stringify({
    type: "assistant",
    uuid: "u1",
    timestamp: new Date(0).toISOString(),
    message: { role: "assistant", model: "<synthetic>", content: [{ type: "text", text }] },
    ...extra,
  });
}

function classify(line: string, liveModel: string | null = "<synthetic>") {
  const msgs = normalizeLineMessages(line);
  return statusForTest(msgs[msgs.length - 1] ?? null, liveModel);
}

describe("computeStatus — structured signals", () => {
  test("auth failure is blocked (used to report a healthy ok)", () => {
    // Verbatim real shape: this matched none of the prose patterns, so a
    // logged-out host reported "ok" while every single turn failed.
    const r = classify(
      assistantLine(
        { isApiErrorMessage: true, error: "authentication_failed", apiErrorStatus: 403 },
        "Please run /login · API Error: 403 Request not allowed",
      ),
    );
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("auth_required");
  });

  test("a bare 401 is blocked even without the error code", () => {
    const r = classify(assistantLine({ isApiErrorMessage: true, apiErrorStatus: 401 }, "API Error: 401"));
    expect(r.statusReason).toBe("auth_required");
  });

  test("an unrecognised API error is blocked as unknown, not silently ok", () => {
    const r = classify(
      assistantLine(
        { isApiErrorMessage: true, error: "some_future_code", apiErrorStatus: 500 },
        "API Error: 500 upstream exploded\nsecond line",
      ),
    );
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("unknown");
    // Surfaces the raw first line so the user can read what actually happened.
    expect(r.statusDetail).toBe("API Error: 500 upstream exploded");
  });

  test("an apiError turn with NO structured signal stays ok", () => {
    // Real shape: isApiErrorMessage with neither code nor status. Not a block —
    // treating it as one would invent outages.
    const r = classify(assistantLine({ isApiErrorMessage: true }, "No response requested."), null);
    expect(r.status).toBe("ok");
  });
});

describe("computeStatus — prose labelling still works", () => {
  test("model unavailable", () => {
    const r = classify(
      assistantLine(
        { isApiErrorMessage: true },
        "There's an issue with the selected model (claude-opus-9). It may not exist or you may not have access to it. Run /model to switch.",
      ),
    );
    expect(r.statusReason).toBe("model_unavailable");
    expect(r.statusDetail).toContain("claude-opus-9");
  });

  test("out of credits", () => {
    const r = classify(assistantLine({ isApiErrorMessage: true }, "Your credit balance is too low"), null);
    expect(r.statusReason).toBe("out_of_credits");
  });
});

describe("computeStatus — prose is a labeller, not a gate", () => {
  test("a session merely discussing an error is not blocked", () => {
    // No isApiErrorMessage → not an API error, whatever the prose says. This is
    // the false-"build paused" case: a session shipping a fix for credit errors.
    const r = classify(
      JSON.stringify({
        type: "assistant",
        uuid: "u2",
        message: {
          role: "assistant",
          model: "claude-opus-5",
          content: [{ type: "text", text: "I fixed the 'credit balance is too low' handler and the model unavailable path." }],
        },
      }),
      "claude-opus-5",
    );
    expect(r.status).toBe("ok");
  });
});

/**
 * The OTHER half of the contract: which message computeStatus is handed.
 *
 * A wedged session reported "ok" for 8 hours not because the classifier was
 * wrong but because it was shown the wrong row — sending into a blocked session
 * made the user's own turn the tail, and the classifier gives up on a non-assistant
 * row. `lastAssistantMsg` is the fix, so these drive selection + classification
 * together over real multi-row transcripts.
 * See `.claude/diagnosis-stop-close-noop-20260806.md`.
 */
describe("computeStatus — selecting the row to classify", () => {
  const dir = mkdtempSync(join(tmpdir(), "status-select-"));
  let n = 0;
  const write = (rows: unknown[]): string => {
    const p = join(dir, `t${n++}.jsonl`);
    writeFileSync(p, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
    return p;
  };
  const authError = {
    type: "assistant",
    uuid: "e1",
    timestamp: new Date(0).toISOString(),
    isApiErrorMessage: true,
    error: "authentication_failed",
    apiErrorStatus: 403,
    message: {
      role: "assistant",
      model: "<synthetic>",
      content: [{ type: "text", text: "Please run /login · API Error: 403 Request not allowed" }],
    },
  };
  const userRow = (text: string) => ({
    type: "user",
    uuid: "u9",
    timestamp: new Date(1).toISOString(),
    message: { role: "user", content: [{ type: "text", text }] },
  });
  const goodReply = {
    type: "assistant",
    uuid: "g1",
    timestamp: new Date(2).toISOString(),
    message: { role: "assistant", model: "claude-opus-5", content: [{ type: "text", text: "Sure." }] },
  };

  const statusOf = async (rows: unknown[]) =>
    statusForTest(await lastAssistantForTest(write(rows)), "<synthetic>");

  // THE regression. Before the fix this returned "ok": the user row was the tail,
  // and the classifier bailed on a non-assistant role before reaching any branch.
  test("an API error is still found when a user turn is the last row", async () => {
    const r = await statusOf([authError, userRow("Can we look at the launchd scripts?")]);
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("auth_required");
  });

  test("still found past a run of attachment/meta rows", async () => {
    const r = await statusOf([
      authError,
      userRow("hello"),
      { type: "attachment", uuid: "a1" },
      { type: "attachment", uuid: "a2" },
      { type: "last-prompt" },
    ]);
    expect(r.statusReason).toBe("auth_required");
  });

  // The other direction: recovery must clear it, or "blocked" becomes its own
  // latch and we have merely moved the bug.
  test("a successful assistant turn AFTER the error clears blocked", async () => {
    const r = await statusOf([authError, userRow("retry"), goodReply]);
    expect(r.status).toBe("ok");
    expect(r.statusReason).toBeNull();
  });

  test("a transcript with no assistant turn at all is ok, not blocked", async () => {
    const r = await statusOf([userRow("first message of a brand new session")]);
    expect(r.status).toBe("ok");
  });

  test("the real wedged transcript reads blocked, and its display state agrees", async () => {
    // Replayed from the session in the diagnosis (rows 314/317): a 403 assistant
    // turn, then a user turn sent 33 hours later that never got a reply.
    const r = await statusOf([authError, userRow("Can we take a look at the launchd scripts?")]);
    expect(sessionDisplayState({ promptPresent: false, blocked: r.status === "blocked", busy: true }))
      .toBe("blocked");
  });

  process.on("exit", () => {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {}
  });
});
