import { describe, expect, it } from "bun:test";
import { currentModelPickerIndex, modelPickerIndex, reasoningPickerIndex, reasoningScreen } from "./codex-model-switch.ts";
import { codexModelFromPane } from "./codex-model-state.ts";

describe("Codex native model picker", () => {
  const pane = `Select Model and Effort
› 1. GPT-6-Astra (current)  Frontier model.
  2. GPT-6-Sol             Workhorse model.
  3. GPT-6-Luna            Fast model.
  4. GPT-5.6-Sol           Older coding model.
  enter select · esc back`;
  it("matches exact model labels without relying on menu position", () => {
    expect(modelPickerIndex(pane, "gpt-5.6-sol")).toBe(4);
    expect(modelPickerIndex(pane, "gpt-6-astra")).toBe(1);
    expect(modelPickerIndex(pane, "gpt-5.3-codex-spark")).toBeNull();
    expect(modelPickerIndex(pane, "gpt-6")).toBeNull();
  });
  it("never answers an unrelated selector", () => {
    expect(modelPickerIndex(pane.replace("Select Model and Effort", "Approve this action?"), "gpt-5.6-sol")).toBeNull();
  });
  it("uses only the current footer for immediate model state", () => {
    expect(codexModelFromPane("model: gpt-5.6-sol\n› Ask Codex to do anything\n  GPT-6-Astra medium fast · ~/project · 80% left\n\n")).toBe("gpt-6-astra");
    expect(codexModelFromPane("GPT-5.6-Sol low · ~/project\nSelect Model and Effort\nenter select · esc back")).toBeNull();
    expect(codexModelFromPane(null)).toBeNull();
  });
});

// Captured from codex-cli 0.156.0 (2026-09-27), trimmed to the picker.
describe("Codex native reasoning picker", () => {
  const models = `  Select Model and Effort
  1. GPT-6-Astra (default)  Frontier intelligence for the most demanding work.
› 2. GPT-6-Sol (current)    Workhorse model for coding and everyday work.
  3. GPT-6-Luna             Fast and affordable model for easier tasks.
  enter select · esc back`;
  const levels = `  Select Reasoning Level for GPT-6-Sol
  1. Low                   Fast responses with lighter reasoning
  2. Medium (default)      Balances speed and reasoning depth for everyday tasks
  3. High                  Greater reasoning depth for complex problems
› 4. Extra high (current)  Extra high reasoning depth for complex problems
  5. More reasoning…       Max and Ultra consume usage limits faster
  enter default · s session · esc back`;
  const advanced = `• Model changed to gpt-6-sol xhigh for this session only
  Advanced Reasoning
  ⚠ Consumes usage limits faster
› 1. Max    For difficult problems when quality matters more than speed · higher usage
  2. Ultra  For demanding work using multiple agents · highest usage
  enter default · s session · esc back`;

  it("re-picks the model marked current, not the cursor or the default", () => {
    expect(currentModelPickerIndex(models)).toBe(2);
    expect(currentModelPickerIndex(models.replace("› 2.", "  2.").replace("  3. GPT-6-Luna", "› 3. GPT-6-Luna"))).toBe(2);
    expect(currentModelPickerIndex(levels)).toBeNull();
  });
  it("finds first-screen levels directly, including Extra high", () => {
    expect(reasoningPickerIndex(levels, "low")).toEqual({ index: 1, submenu: false });
    expect(reasoningPickerIndex(levels, "xhigh")).toEqual({ index: 4, submenu: false });
  });
  it("routes Max and Ultra through More reasoning…", () => {
    expect(reasoningPickerIndex(levels, "max")).toEqual({ index: 5, submenu: true });
    expect(reasoningPickerIndex(advanced, "ultra")).toEqual({ index: 2, submenu: false });
    expect(reasoningPickerIndex(advanced, "max")).toEqual({ index: 1, submenu: false });
  });
  it("reads a one-row Advanced screen (GPT-6-Luna offers Max only)", () => {
    const luna = `  Advanced Reasoning
  ⚠ Consumes usage limits faster
› 1. Max  For difficult problems when quality matters more than speed · higher usage
  enter default · s session · esc back`;
    expect(reasoningPickerIndex(luna, "max")).toEqual({ index: 1, submenu: false });
    expect(reasoningPickerIndex(luna, "ultra")).toBeNull();
  });
  it("only offers the session key while a level, not the submenu, is highlighted", () => {
    expect(reasoningScreen(levels)?.sessionKey).toBe(true);
    const onMore = levels
      .replace("› 4. Extra high (current)", "  4. Extra high (current)")
      .replace("  5. More reasoning…", "› 5. More reasoning…")
      .replace("enter default · s session · esc back", "enter select · esc back");
    expect(reasoningScreen(onMore)?.sessionKey).toBe(false);
    expect(reasoningScreen(onMore)?.options.find(option => option.selected)?.index).toBe(5);
  });
  it("reports levels a model does not offer, and ignores other selectors", () => {
    expect(reasoningPickerIndex(advanced, "low")).toBeNull();
    expect(reasoningPickerIndex(levels.replace(/  5\. More reasoning.*\n/, ""), "ultra")).toBeNull();
    expect(reasoningPickerIndex(models, "high")).toBeNull();
  });
});
