import { afterEach, describe, expect, test } from "bun:test";
import {
  ask,
  askJson,
  DEFAULT_MODEL,
  extractJson,
  setTransportForTests,
} from "./claude.ts";

describe("extractJson", () => {
  test("parses a bare array or object", () => {
    expect(extractJson('[{"id":"a"}]')).toEqual([{ id: "a" }]);
    expect(extractJson('{"ok":true}')).toEqual({ ok: true });
  });

  test("tolerates surrounding whitespace", () => {
    expect(extractJson('\n\n  [1,2]  \n')).toEqual([1, 2]);
  });

  test("parses a fenced block, with or without the json tag", () => {
    expect(extractJson('```json\n[{"id":"a"}]\n```')).toEqual([{ id: "a" }]);
    expect(extractJson("```\n[1,2]\n```")).toEqual([1, 2]);
  });

  test("parses a fenced block wrapped in prose", () => {
    const text = 'Sure, here you go:\n\n```json\n{"a":1}\n```\n\nHope that helps!';
    expect(extractJson(text)).toEqual({ a: 1 });
  });

  test("parses JSON embedded in prose with no fence", () => {
    expect(extractJson('Here: [{"id":"a"}] — done')).toEqual([{ id: "a" }]);
  });

  test("prefers the payload that starts earlier when both brackets appear", () => {
    // Prose mentioning braces must not shadow the real array.
    expect(extractJson('The result [1,2] uses {curly} syntax')).toEqual([1, 2]);
  });

  test("spans the widest match, so nested structures survive", () => {
    expect(extractJson('x [[1,2],[3,4]] y')).toEqual([
      [1, 2],
      [3, 4],
    ]);
  });

  test("returns null for output with no JSON at all", () => {
    // Null means "no answer this round" — a normal outcome for these tasks.
    for (const t of ["", "I cannot do that", "```\nnot json\n```", "{{{"]) {
      expect(extractJson(t)).toBeNull();
    }
  });

  test("preserves JSON primitives that are legitimately falsy", () => {
    expect(extractJson("false")).toBe(false);
    expect(extractJson("0")).toBe(0);
  });

  test("a bare `null` reply reads as no answer", () => {
    expect(extractJson("null")).toBeNull();
  });
});

// --- service behaviour, with the subprocess transport stubbed out ---

afterEach(() => setTransportForTests(null));

describe("ask", () => {
  test("passes prompt, system and the default model to the transport", async () => {
    const seen: unknown[] = [];
    setTransportForTests(async (o) => {
      seen.push({ prompt: o.prompt, system: o.system, model: o.model });
      return "hi";
    });
    await ask({ prompt: "p", system: "s" });
    expect(seen).toEqual([{ prompt: "p", system: "s", model: DEFAULT_MODEL }]);
  });

  test("an explicit model overrides the default", async () => {
    let model = "";
    setTransportForTests(async (o) => ((model = o.model), "x"));
    await ask({ prompt: "p", model: "opus" });
    expect(model).toBe("opus");
  });

  test("retries once by default, then succeeds", async () => {
    let calls = 0;
    setTransportForTests(async () => {
      if (++calls === 1) throw new Error("transient");
      return "second time";
    });
    expect(await ask({ prompt: "p" })).toBe("second time");
    expect(calls).toBe(2);
  });

  test("gives up after the retry budget and surfaces the last error", async () => {
    let calls = 0;
    setTransportForTests(async () => {
      calls++;
      throw new Error("still broken");
    });
    await expect(ask({ prompt: "p" })).rejects.toThrow("still broken");
    expect(calls).toBe(2); // 1 attempt + 1 retry
  });

  test("retries: 0 means a single attempt", async () => {
    let calls = 0;
    setTransportForTests(async () => {
      calls++;
      throw new Error("nope");
    });
    await expect(ask({ prompt: "p", retries: 0 })).rejects.toThrow("nope");
    expect(calls).toBe(1);
  });

  test("serializes concurrent calls — never two subprocesses at once", async () => {
    // The guard against a task looping `ask` over N items and fanning out
    // subprocesses on the single Bun event loop.
    let inFlight = 0;
    let maxInFlight = 0;
    setTransportForTests(async () => {
      maxInFlight = Math.max(maxInFlight, ++inFlight);
      await new Promise((r) => setTimeout(r, 5));
      inFlight--;
      return "ok";
    });
    await Promise.all([1, 2, 3, 4].map(() => ask({ prompt: "p" })));
    expect(maxInFlight).toBe(1);
  });

  test("a failing call does not wedge the queue for the next caller", async () => {
    let calls = 0;
    setTransportForTests(async () => {
      if (++calls <= 2) throw new Error("boom");
      return "recovered";
    });
    await expect(ask({ prompt: "a", retries: 1 })).rejects.toThrow("boom");
    expect(await ask({ prompt: "b" })).toBe("recovered");
  });
});

describe("askJson", () => {
  const validate = (v: unknown) => (Array.isArray(v) ? (v as number[]) : null);

  test("returns the validated value", async () => {
    setTransportForTests(async () => "```json\n[1,2,3]\n```");
    expect(await askJson({ prompt: "p", validate })).toEqual([1, 2, 3]);
  });

  test("returns null when the reply contains no JSON", async () => {
    setTransportForTests(async () => "I could not do that");
    expect(await askJson({ prompt: "p", validate })).toBeNull();
  });

  test("returns null when validation rejects the shape", async () => {
    // A hallucinated shape must never reach the caller's state.
    setTransportForTests(async () => '{"not":"an array"}');
    expect(await askJson({ prompt: "p", validate })).toBeNull();
  });

  test("an empty array is a real answer, not a rejection", async () => {
    setTransportForTests(async () => "[]");
    expect(await askJson({ prompt: "p", validate })).toEqual([]);
  });
});
