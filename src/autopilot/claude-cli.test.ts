import { describe, expect, test } from "bun:test";
import { buildArgs, parseEnvelope, scrubbedEnv } from "./claude-cli.ts";

describe("scrubbedEnv", () => {
  test("removes every API-key route so the CLI must use its OAuth session", () => {
    // The failure this prevents is silent: with any of these set the CLI keeps
    // working, but bills per-token API usage instead of the subscription.
    const env = scrubbedEnv({
      ANTHROPIC_API_KEY: "sk-ant-xxx",
      ANTHROPIC_AUTH_TOKEN: "tok",
      ANTHROPIC_BASE_URL: "https://proxy.example",
      PATH: "/usr/bin",
    });
    expect(env.ANTHROPIC_API_KEY).toBeUndefined();
    expect(env.ANTHROPIC_AUTH_TOKEN).toBeUndefined();
    expect(env.ANTHROPIC_BASE_URL).toBeUndefined();
    expect(env.PATH).toBe("/usr/bin"); // everything else survives
  });

  test("does not mutate the environment it was handed", () => {
    const base = { ANTHROPIC_API_KEY: "sk-ant-xxx" };
    scrubbedEnv(base);
    expect(base.ANTHROPIC_API_KEY).toBe("sk-ant-xxx");
  });
});

describe("buildArgs", () => {
  test("carries the isolation flags", () => {
    const args = buildArgs("haiku");
    expect(args).toEqual([
      "--print",
      "--output-format",
      "json",
      "--model",
      "haiku",
      "--disable-slash-commands",
      "--tools",
      "",
      "--strict-mcp-config",
    ]);
  });

  test("appends the system prompt only when there is one", () => {
    expect(buildArgs("haiku", "be terse")).toContain("--system-prompt");
    expect(buildArgs("haiku")).not.toContain("--system-prompt");
  });
});

describe("parseEnvelope", () => {
  const ok = {
    type: "result",
    subtype: "success",
    is_error: false,
    result: '[{"id":"a","title":"New name"}]',
    total_cost_usd: 0.0189,
    modelUsage: { "claude-haiku-4-5-20251001": { provider: "firstParty" } },
  };

  test("extracts the result text, cost and provider", () => {
    const out = parseEnvelope(JSON.stringify(ok));
    expect(out.text).toBe('[{"id":"a","title":"New name"}]');
    expect(out.costUsd).toBeCloseTo(0.0189);
    expect(out.provider).toBe("firstParty");
  });

  test("takes the last event when the CLI emits an array", () => {
    expect(parseEnvelope(JSON.stringify([{ type: "system" }, ok])).text).toBe(ok.result);
  });

  test("throws on an error envelope, surfacing the reason", () => {
    const bad = { ...ok, is_error: true, subtype: "error_during_execution", result: "boom" };
    expect(() => parseEnvelope(JSON.stringify(bad))).toThrow(/error_during_execution.*boom/s);
  });

  test("throws when the subtype is not success", () => {
    expect(() => parseEnvelope(JSON.stringify({ ...ok, subtype: "error_max_turns" }))).toThrow(
      /error_max_turns/,
    );
  });

  test("throws on empty or non-JSON output rather than returning silence", () => {
    // Silence here would read as "no session drifted", which is wrong and quiet.
    expect(() => parseEnvelope("")).toThrow(/no output/);
    expect(() => parseEnvelope("Killed: 9")).toThrow(/not JSON/);
  });

  test("a success envelope with no result yields empty text, not a throw", () => {
    expect(parseEnvelope(JSON.stringify({ type: "result", subtype: "success" })).text).toBe("");
  });
});
