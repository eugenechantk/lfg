import { describe, expect, it } from "bun:test";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { codexPromptFromCmd, firstUserTextFromTop, pickCodexThread } from "./sessions.ts";

type Thread = {
  id: string;
  path: string;
  cwd: string | null;
  createdAt: number | null;
  updatedAt: number | null;
  firstUserText: string | null;
};

const T0 = 1_782_885_876_000; // process startedAt used across cases

function thread(over: Partial<Thread> & { id: string }): Thread {
  return {
    path: `/rollout-${over.id}.jsonl`,
    cwd: "/Users/eugenechan/dev/inbox",
    createdAt: T0 + 8_000,
    updatedAt: T0 + 8_000,
    firstUserText: null,
    ...over,
  };
}

async function writeRollout(lines: unknown[]): Promise<string> {
  const path = join(tmpdir(), `lfg-codex-bind-${randomUUID()}.jsonl`);
  await Bun.write(path, lines.map((line) => JSON.stringify(line)).join("\n"));
  return path;
}

describe("pickCodexThread — promptless (interactive codex)", () => {
  it("binds an interactive codex to its same-cwd rollout written just after launch", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got?.id).toBe("a");
  });

  it("does not bind a rollout from a different cwd", () => {
    const t = thread({ id: "a", cwd: "/other/dir" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("does not bind a stale rollout created well before launch", () => {
    const t = thread({ id: "a", createdAt: T0 - 5 * 60_000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("does not bind a rollout created long after launch (a newer session)", () => {
    const t = thread({ id: "a", createdAt: T0 + 10 * 60_000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("skips already-claimed rollouts", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: null },
      [t],
      new Set(["a"]),
    );
    expect(got).toBeNull();
  });

  it("binds two interactive codex in the same cwd each to its nearest-launch rollout", () => {
    const startA = T0;
    const startB = T0 + 60_000;
    const rollA = thread({ id: "a", createdAt: startA + 5_000 });
    const rollB = thread({ id: "b", createdAt: startB + 5_000 });
    const threads = [rollA, rollB];
    const claimed = new Set<string>();

    const gotA = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: startA, prompt: null },
      threads,
      claimed,
    );
    expect(gotA?.id).toBe("a");
    claimed.add(gotA!.id);

    const gotB = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: startB, prompt: null },
      threads,
      claimed,
    );
    expect(gotB?.id).toBe("b");
  });

  it("returns null when startedAt is unknown (can't disambiguate promptless)", () => {
    const t = thread({ id: "a" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: null, prompt: null },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });
});

describe("pickCodexThread — prompt match (regression)", () => {
  it("binds by matching first user text, freshest wins", () => {
    const older = thread({ id: "old", firstUserText: "fix the bug", updatedAt: T0 });
    const newer = thread({ id: "new", firstUserText: "fix the bug", updatedAt: T0 + 1000 });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: "fix the bug" },
      [older, newer],
      new Set(),
    );
    expect(got?.id).toBe("new");
  });

  it("does not bind when no thread's prompt matches", () => {
    const t = thread({ id: "a", firstUserText: "something else" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt: "fix the bug" },
      [t],
      new Set(),
    );
    expect(got).toBeNull();
  });

  it("matches multi-line prompts decoded from ps octal escapes", () => {
    const prompt = codexPromptFromCmd("codex --model gpt-5.5 -- fix the bug\\012\\012Then add tests");
    expect(prompt).toBe("fix the bug\n\nThen add tests");

    const t = thread({ id: "a", firstUserText: "fix the bug\n\nThen add tests" });
    const got = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt },
      [t],
      new Set(),
    );
    expect(got?.id).toBe("a");
  });

  it("binds two identical-prompt codex processes to two different rollouts", () => {
    const prompt = "Does lfg work for codex?\n\nIf so, update the selector.";
    const newest = thread({ id: "new", firstUserText: prompt, updatedAt: T0 + 2_000 });
    const oldest = thread({ id: "old", firstUserText: prompt, updatedAt: T0 + 1_000 });
    const threads = [oldest, newest];
    const claimed = new Set<string>();

    const gotA = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt },
      threads,
      claimed,
    );
    expect(gotA?.id).toBe("new");
    claimed.add(gotA!.id);

    const gotB = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/inbox", startedAt: T0, prompt },
      threads,
      claimed,
    );
    expect(gotB?.id).toBe("old");
    expect(gotB?.id).not.toBe(gotA?.id);
  });

  it("binds identical prompts to the rollout created nearest each process start", () => {
    const prompt =
      "Does lfg work for codex?\n\nIf so, can we update the model selectors to the latest codex model versions";
    const procAStartedAt = Date.parse("2026-07-31T20:21:08+08:00");
    const procBStartedAt = Date.parse("2026-07-31T20:21:22+08:00");
    const rolloutA = thread({
      id: "019fb81f-0a99-7490-9082-4b4cf3849db3",
      cwd: "/Users/eugenechan/dev/personal/lfg",
      createdAt: Date.parse("2026-07-31T20:21:09+08:00"),
      updatedAt: Date.parse("2026-07-31T20:21:24+08:00"),
      firstUserText: prompt,
    });
    const rolloutB = thread({
      id: "019fb81f-3dd5-7fe0-ab68-fa81255055ad",
      cwd: "/Users/eugenechan/dev/personal/lfg",
      createdAt: Date.parse("2026-07-31T20:21:23+08:00"),
      updatedAt: Date.parse("2026-07-31T20:21:25+08:00"),
      firstUserText: prompt,
    });
    const threads = [rolloutA, rolloutB];
    const claimed = new Set<string>();

    const gotA = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/personal/lfg", startedAt: procAStartedAt, prompt },
      threads,
      claimed,
    );
    expect(gotA?.id).toBe("019fb81f-0a99-7490-9082-4b4cf3849db3");
    claimed.add(gotA!.id);

    const gotB = pickCodexThread(
      { cwd: "/Users/eugenechan/dev/personal/lfg", startedAt: procBStartedAt, prompt },
      threads,
      claimed,
    );
    expect(gotB?.id).toBe("019fb81f-3dd5-7fe0-ab68-fa81255055ad");
  });
});

describe("firstUserTextFromTop — codex rollout prompt resolution", () => {
  it("prefers event_msg user_message over injected response_item context", async () => {
    const path = await writeRollout([
      {
        type: "response_item",
        payload: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "# AGENTS.md instructions\n\n<INSTRUCTIONS>\n..." }],
        },
      },
      {
        type: "event_msg",
        payload: { type: "user_message", message: "Does lfg work for codex?\n\nIf so, ship it." },
      },
    ]);

    await expect(firstUserTextFromTop(path)).resolves.toBe("Does lfg work for codex?\n\nIf so, ship it.");
  });

  it("falls back to the first non-injected response_item user message", async () => {
    const path = await writeRollout([
      {
        type: "response_item",
        payload: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "<environment_context>\n  <cwd>/tmp</cwd>" }],
        },
      },
      {
        type: "response_item",
        payload: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "Fix the transcript binding." }],
        },
      },
    ]);

    await expect(firstUserTextFromTop(path)).resolves.toBe("Fix the transcript binding.");
  });

  it("returns null when the scanned user messages are all injected context", async () => {
    const path = await writeRollout([
      {
        type: "response_item",
        payload: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "# AGENTS.md instructions\n\n<INSTRUCTIONS>\n..." }],
        },
      },
      {
        type: "response_item",
        payload: {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: "<user_instructions>\nBe concise." }],
        },
      },
    ]);

    await expect(firstUserTextFromTop(path)).resolves.toBeNull();
  });
});
