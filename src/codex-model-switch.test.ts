import { describe, expect, it } from "bun:test";
import { modelPickerIndex } from "./codex-model-switch.ts";
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
