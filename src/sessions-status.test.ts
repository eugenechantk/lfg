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

// Codex has its own error vocabulary: no isApiErrorMessage, no HTTP status —
// just `task_complete.error.codex_error_info` + prose. These are the exact
// messages from the Sep 2026 rollouts that shipped invisibly.
describe("computeStatus — codex turn errors", () => {
  const codexError = (message: string, codex_error_info: string, ts = 0): string =>
    JSON.stringify({
      timestamp: new Date(ts).toISOString(),
      type: "event_msg",
      payload: { type: "task_complete", turn_id: "t", last_agent_message: null, error: { message, codex_error_info } },
    });
  const usageLimit =
    "You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at 9:00 PM.";

  test("usage limit is blocked as out_of_credits, with codex's message as the detail", () => {
    const r = classify(codexError(usageLimit, "usage_limit_exceeded"), null);
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("out_of_credits");
    // The reset time is the one thing the user needs; keep the sentence intact.
    expect(r.statusDetail).toBe(usageLimit);
  });

  test("an unsupported / too-new model is model_unavailable", () => {
    const wrap = (message: string) =>
      JSON.stringify({ type: "error", status: 400, error: { type: "invalid_request_error", message } });
    const unsupported = classify(
      codexError(wrap("The 'gpt-5.4' model is not supported when using Codex with a ChatGPT account."), "other"),
      null,
    );
    expect(unsupported.statusReason).toBe("model_unavailable");
    expect(unsupported.statusDetail).toBe(
      "The 'gpt-5.4' model is not supported when using Codex with a ChatGPT account.",
    );
    const tooNew = classify(
      codexError(
        wrap("The 'gpt-6-astra' model requires a newer version of Codex. Please upgrade to the latest app or CLI."),
        "other",
      ),
      null,
    );
    expect(tooNew.statusReason).toBe("model_unavailable");
  });

  test("any other codex turn error is blocked as unknown with the first line", () => {
    const r = classify(
      codexError("unexpected status 404 Not Found: Unknown error, url: https://chatgpt.com/backend-api/codex/responses", "other"),
      null,
    );
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("unknown");
    expect(r.statusDetail).toMatch(/^unexpected status 404 Not Found/);
  });

  test("a codex 403 HTML page is NOT routed to the /login advice", () => {
    // It's an edge/Cloudflare page from chatgpt.com, not an auth failure.
    const r = classify(codexError("unexpected status 403 Forbidden: <html><body>blocked</body></html>", "other"), null);
    expect(r.status).toBe("blocked");
    expect(r.statusReason).toBe("unknown");
  });

  test("selection: a later codex user row does not erase the block", async () => {
    // Same latch as the Claude case above, on the codex rollout shape: the
    // codex list path used to grade `previewLast` (any role), so sending into
    // the wedged session flipped it back to "ok".
    const dir = mkdtempSync(join(tmpdir(), "status-codex-"));
    const p = join(dir, "rollout.jsonl");
    const userRow = JSON.stringify({
      timestamp: new Date(1).toISOString(),
      type: "event_msg",
      payload: { type: "user_message", message: "are you there?" },
    });
    writeFileSync(p, [codexError(usageLimit, "usage_limit_exceeded"), userRow].join("\n") + "\n");
    const r = statusForTest(await lastAssistantForTest(p), null);
    expect(r.statusReason).toBe("out_of_credits");
    rmSync(dir, { recursive: true, force: true });
  });
});
