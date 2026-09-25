import { describe, expect, it } from "bun:test";
import {
  BUNDLED_MODEL_CATALOG,
  isSafeModelId,
  mergeWithBundledFallbacks,
  parseClaudeCatalog,
  parseCodexModelListOutput,
} from "./model-catalog.ts";

describe("automatic CLI model catalog", () => {
  it("reads Claude Code's visible main catalog and account default", () => {
    const parsed = parseClaudeCatalog(JSON.stringify({
      version: 2,
      catalog: {
        config: {
          models: [
            { id: "claude-opus-5-5", name: "Opus 5.5", section: "main" },
            { id: "claude-fable-5-1", name: "Fable 5.1", section: "main" },
            { id: "claude-opus-5", name: "Opus 5", section: "overflow" },
            { id: "bad model; rm -rf", name: "Unsafe", section: "main" },
          ],
        },
        state: { model: "claude-fable-5-1" },
      },
    }), "2.1.280");

    expect(parsed).toEqual({
      version: "2.1.280",
      defaultModel: "claude-fable-5-1",
      models: ["claude-opus-5-5", "claude-fable-5-1"],
    });
  });

  it("reads the visible Codex app-server page and provider default", () => {
    const output = [
      JSON.stringify({ id: 1, result: { userAgent: "lfg-model-catalog/0.156.0" } }),
      JSON.stringify({ method: "configWarning", params: { summary: "ignored" } }),
      JSON.stringify({
        id: 2,
        result: {
          data: [
            { model: "gpt-6-astra", hidden: false, isDefault: true },
            { model: "gpt-6-sol", hidden: false, isDefault: false },
            { model: "gpt-hidden", hidden: true, isDefault: false },
            { model: "gpt-6-sol", hidden: false, isDefault: false },
          ],
          nextCursor: null,
        },
      }),
    ].join("\n");

    expect(parseCodexModelListOutput(output, "0.156.0")).toEqual({
      version: "0.156.0",
      defaultModel: "gpt-6-astra",
      models: ["gpt-6-astra", "gpt-6-sol"],
    });
  });

  it("accepts provider model IDs but rejects command and slash-command injection", () => {
    for (const id of ["claude-opus-5-5", "gpt-6.sol:fast", "o3_mini"]) {
      expect(isSafeModelId(id)).toBe(true);
    }
    for (const id of ["", "two models", "/model opus", "opus\n/help", "$(touch /tmp/x)", "x".repeat(81)]) {
      expect(isSafeModelId(id)).toBe(false);
    }
  });

  it("falls back per agent when discovery is absent or malformed", () => {
    expect(mergeWithBundledFallbacks({ claude: null, codex: null })).toEqual(BUNDLED_MODEL_CATALOG);
    expect(BUNDLED_MODEL_CATALOG.agents.claude).toEqual({
      version: null,
      defaultModel: "opus",
      models: ["opus", "fable", "sonnet", "haiku"],
    });
    expect(BUNDLED_MODEL_CATALOG.agents.codex).toEqual({
      version: null,
      defaultModel: "gpt-5.6-sol",
      models: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"],
    });
    expect(BUNDLED_MODEL_CATALOG.agents.claude.models).not.toContain("claude-opus-5-5");
    expect(BUNDLED_MODEL_CATALOG.agents.codex.models).not.toContain("gpt-6-astra");
    expect(mergeWithBundledFallbacks({
      claude: { version: "2.1.280", defaultModel: "claude-opus-5-5", models: ["claude-opus-5-5"] },
      codex: null,
    })).toEqual({
      agents: {
        claude: { version: "2.1.280", defaultModel: "claude-opus-5-5", models: ["claude-opus-5-5"] },
        codex: BUNDLED_MODEL_CATALOG.agents.codex,
      },
    });
  });
});
