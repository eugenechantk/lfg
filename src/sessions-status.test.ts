// computeStatus is reached through normalizeLineMessages + listSessions, so
// these drive it the way the server does: real transcript line shapes in, a
// status classification out. Line shapes are verbatim from real transcripts
// under ~/.claude/projects (error="authentication_failed", apiErrorStatus=403).
import { describe, expect, test } from "bun:test";
import { normalizeLineMessages, statusForTest } from "./sessions.ts";

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
