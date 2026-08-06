// Codex rollouts carry no per-message model — the model lives in one
// `turn_context` row per turn. Line shapes below are verbatim (trimmed) from a
// real rollout under ~/.codex/sessions.
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { lastCodexModel } from "./sessions.ts";

function withRollout(lines: string[], fn: (path: string) => Promise<void>) {
  const dir = mkdtempSync(join(tmpdir(), "lfg-codex-model-"));
  const path = join(dir, "rollout.jsonl");
  writeFileSync(path, lines.map((l) => l + "\n").join(""));
  return fn(path).finally(() => rmSync(dir, { recursive: true, force: true }));
}

const sessionMeta = JSON.stringify({
  timestamp: "2026-08-05T15:10:10.719Z",
  type: "session_meta",
  payload: {
    session_id: "019fd279-92f0-7072-86cd-ef47809882f3",
    cwd: "/Users/eugenechan/dev/personal/lfg",
    originator: "codex-tui",
    // Note: no `model` here — only the provider. This is why session_meta can't
    // be the source.
    model_provider: "openai-long-timeout",
  },
});

function turnContext(model: string, turn: string): string {
  return JSON.stringify({
    timestamp: "2026-08-05T15:10:49.396Z",
    type: "turn_context",
    payload: { turn_id: turn, cwd: "/x", approval_policy: "never", model },
  });
}

function responseItem(text: string): string {
  return JSON.stringify({
    timestamp: "2026-08-05T15:10:50.000Z",
    type: "response_item",
    payload: { type: "message", role: "assistant", content: [{ type: "output_text", text }] },
  });
}

describe("lastCodexModel", () => {
  test("reads the model off turn_context", async () => {
    await withRollout([sessionMeta, turnContext("gpt-5.6-sol", "t1"), responseItem("hi")], async (p) => {
      expect(await lastCodexModel(p)).toBe("gpt-5.6-sol");
    });
  });

  test("newest turn wins, so a mid-session switch is reflected", async () => {
    await withRollout(
      [
        sessionMeta,
        turnContext("gpt-5.6-sol", "t1"),
        responseItem("first"),
        turnContext("gpt-5.6-codex-max", "t2"),
        responseItem("second"),
      ],
      async (p) => {
        expect(await lastCodexModel(p)).toBe("gpt-5.6-codex-max");
      },
    );
  });

  test("null before the first turn — the caller falls back to the launch arg", async () => {
    await withRollout([sessionMeta], async (p) => {
      expect(await lastCodexModel(p)).toBeNull();
    });
  });

  test("scans past a long tail of response items to reach the turn_context", async () => {
    // A busy turn buries turn_context under hundreds of rows; scanBack must grow
    // its window rather than report "no model".
    const noise = Array.from({ length: 400 }, (_, i) => responseItem("x".repeat(200) + i));
    await withRollout([sessionMeta, turnContext("gpt-5.6-sol", "t1"), ...noise], async (p) => {
      expect(await lastCodexModel(p)).toBe("gpt-5.6-sol");
    });
  });

  test("survives a truncated/garbage line", async () => {
    await withRollout([sessionMeta, turnContext("gpt-5.6-sol", "t1"), '{"type":"resp'], async (p) => {
      expect(await lastCodexModel(p)).toBe("gpt-5.6-sol");
    });
  });
});
