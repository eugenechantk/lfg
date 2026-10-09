import { describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  BUNDLED_MODEL_CATALOG,
  isSafeModelId,
  mergeWithBundledFallbacks,
  parseClaudeCatalog,
  parseCodexModelListOutput,
  parseLastGoodCatalog,
  readLastGoodCatalog,
  resolveModelCatalog,
  writeLastGoodCatalog,
} from "./model-catalog.ts";

describe("automatic CLI model catalog", () => {
  it("reads Claude Code's visible main catalog and account default", () => {
    const parsed = parseClaudeCatalog(JSON.stringify({
      version: 2,
      catalog: {
        config: {
          models: [
            {
              id: "claude-opus-5-5", name: "Opus 5.5", section: "main",
              thinking: { type: "effort", effort_options: [{ id: "low" }, { id: "xhigh" }, { id: "max" }, { id: "rm -rf" }] },
            },
            { id: "claude-fable-5-1", name: "Fable 5.1", section: "main" },
            { id: "claude-haiku-4-5", name: "Haiku 4.5", section: "main", thinking: { type: "none" } },
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
      models: ["claude-opus-5-5", "claude-fable-5-1", "claude-haiku-4-5"],
      // Fable carries no `thinking` block → unknown, so it is left out; Haiku's
      // `{ type: "none" }` is a real "no effort control".
      efforts: { "claude-opus-5-5": ["low", "xhigh", "max"], "claude-haiku-4-5": [] },
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
            {
              model: "gpt-6-astra", hidden: false, isDefault: true,
              supportedReasoningEfforts: [{ reasoningEffort: "low" }, { reasoningEffort: "ultra" }, { reasoningEffort: "bogus" }],
            },
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
      efforts: { "gpt-6-astra": ["low", "ultra"] },
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
      efforts: {},
    });
    expect(BUNDLED_MODEL_CATALOG.agents.codex).toEqual({
      version: null,
      defaultModel: "gpt-5.6-sol",
      models: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"],
      efforts: {},
    });
    expect(BUNDLED_MODEL_CATALOG.agents.claude.models).not.toContain("claude-opus-5-5");
    expect(BUNDLED_MODEL_CATALOG.agents.codex.models).not.toContain("gpt-6-astra");
    expect(mergeWithBundledFallbacks({
      claude: { version: "2.1.280", defaultModel: "claude-opus-5-5", models: ["claude-opus-5-5"], efforts: {} },
      codex: null,
    })).toEqual({
      agents: {
        claude: { version: "2.1.280", defaultModel: "claude-opus-5-5", models: ["claude-opus-5-5"], efforts: {} },
        codex: BUNDLED_MODEL_CATALOG.agents.codex,
      },
    });
  });
});

describe("last successful discovery", () => {
  const codex61 = {
    version: "0.160.0",
    defaultModel: "gpt-6.1-sol",
    models: ["gpt-6.1-sol", "gpt-6-astra", "gpt-5.6-sol"],
    efforts: { "gpt-6.1-sol": ["low", "high"] },
  };
  const claude55 = {
    version: "2.1.290",
    defaultModel: "claude-opus-5-5",
    models: ["claude-opus-5-5", "claude-fable-5-1"],
    efforts: {},
  };

  it("serves and remembers a fresh discovery", () => {
    const { catalog, lastGood } = resolveModelCatalog({ claude: claude55, codex: codex61 }, {});
    expect(catalog).toEqual({ agents: { claude: claude55, codex: codex61 } });
    expect(lastGood).toEqual({ claude: claude55, codex: codex61 });
  });

  // A codex app-server timeout used to hand every client the compiled
  // gpt-5.6 list, from a host that runs gpt-6.1.
  it("serves the last good list for an agent whose discovery failed", () => {
    const { catalog, lastGood } = resolveModelCatalog({ claude: claude55, codex: null }, { codex: codex61 });
    expect(catalog.agents.codex).toEqual(codex61);
    expect(catalog.agents.claude).toEqual(claude55);
    expect(lastGood).toEqual({ claude: claude55, codex: codex61 });
  });

  it("falls back to the compiled list only when nothing was ever discovered", () => {
    const { catalog, lastGood } = resolveModelCatalog({ claude: null, codex: null }, {});
    expect(catalog).toEqual(BUNDLED_MODEL_CATALOG);
    expect(lastGood).toEqual({});
  });

  it("re-validates the saved file instead of trusting it", () => {
    expect(parseLastGoodCatalog("not json")).toEqual({});
    expect(parseLastGoodCatalog(JSON.stringify({ codex: { models: [] } }))).toEqual({});
    expect(parseLastGoodCatalog(JSON.stringify({
      codex: {
        version: 7,
        defaultModel: "$(rm -rf /)",
        models: ["gpt-6.1-sol", "bad model", "gpt-6.1-sol"],
        efforts: { "gpt-6.1-sol": ["high", "nonsense"], "bad model": ["low"] },
      },
      someFutureAgent: codex61,
    }))).toEqual({
      codex: {
        version: null,
        defaultModel: "gpt-6.1-sol",
        models: ["gpt-6.1-sol"],
        efforts: { "gpt-6.1-sol": ["high"] },
      },
    });
  });

  it("round-trips through the file on disk", async () => {
    const path = join(mkdtempSync(join(tmpdir(), "lfg-model-catalog-")), "model-catalog.json");
    expect(await readLastGoodCatalog(path)).toEqual({});
    await writeLastGoodCatalog(path, { claude: claude55, codex: codex61 });
    expect(await readLastGoodCatalog(path)).toEqual({ claude: claude55, codex: codex61 });
    writeFileSync(path, "{ truncated");
    expect(await readLastGoodCatalog(path)).toEqual({});
    expect(readFileSync(path, "utf8")).toBe("{ truncated");
  });
});
