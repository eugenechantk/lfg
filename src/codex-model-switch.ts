import { answerPrompt, capturePane, inputBoxFromPane, parsePrompt } from "./tmux.ts";
import { codexModelFromPane } from "./codex-model-state.ts";

// Codex's /model takes no inline argument. Pasting `/model <id>` submits an
// ordinary user turn. Drive its native picker without restarting the thread.
export function modelPickerIndex(pane: string, model: string): number | null {
  const prompt = parsePrompt(pane);
  if (!prompt || !/^Select Model(?: and Effort)?$/i.test(prompt.question)) return null;
  return prompt.options.find(option =>
    option.label.split(/\s/)[0]?.toLowerCase() === model.toLowerCase()
  )?.index ?? null;
}

const switching = new Set<string>();

export async function switchCodexModel(target: string, model: string): Promise<{ ok: boolean; error?: string }> {
  if (switching.has(target)) return { ok: false, error: "A model switch is already in progress." };
  const initial = capturePane(target);
  const draft = initial == null ? null : inputBoxFromPane(initial)?.trim();
  if (initial == null || parsePrompt(initial) || draft == null || (draft !== "" && draft !== "Ask Codex to do anything")) {
    return { ok: false, error: "Finish the open Codex prompt or clear its draft before switching models." };
  }
  switching.add(target);
  const key = (...keys: string[]) => Bun.spawnSync(["tmux", "send-keys", "-t", target, ...keys]).exitCode === 0;
  const waitFor = async (predicate: (pane: string) => boolean): Promise<string | null> => {
    for (let i = 0; i < 30; i++) {
      await Bun.sleep(100);
      const pane = capturePane(target);
      if (pane != null && predicate(pane)) return pane;
    }
    return null;
  };
  try {
    if (!key("-l", "/model")) return { ok: false, error: "Could not open Codex's model picker." };
    // Let Codex finish its input burst before Enter; otherwise Enter can become
    // part of the paste burst and leave the command stranded in the composer.
    await Bun.sleep(250);
    key("Enter");
    const picker = await waitFor(p => /^Select Model(?: and Effort)?$/i.test(parsePrompt(p)?.question ?? ""));
    if (!picker) return { ok: false, error: "Codex did not open its model picker." };
    const index = modelPickerIndex(picker, model);
    if (index == null) {
      key("Escape");
      return { ok: false, error: `This Codex CLI does not offer ${model}.` };
    }
    const selected = await answerPrompt(target, index);
    if (!selected.ok) return selected;
    const next = await waitFor(p => /Select Reasoning Level/i.test(parsePrompt(p)?.question ?? "") || !parsePrompt(p));
    if (!next) return { ok: false, error: "Codex did not finish selecting the model." };
    if (/Select Reasoning Level/i.test(parsePrompt(next)?.question ?? "")) {
      // Keep the picker-selected effort. Current Codex provides a session-only
      // shortcut so this action need not change the user's global default.
      key(/\bs session\b/.test(next) ? "s" : "Enter");
    }
    const confirmed = await waitFor(p => {
      if (parsePrompt(p)) return false;
      return codexModelFromPane(p) === model.toLowerCase();
    });
    return confirmed ? { ok: true } : { ok: false, error: "Codex has not confirmed the selected model. Check its terminal." };
  } finally {
    switching.delete(target);
  }
}
