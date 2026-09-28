import { answerPrompt, capturePane, codexComposerIndex, inputBoxFromPane, parsePrompt } from "./tmux.ts";
import { codexModelFromPane } from "./codex-model-state.ts";
import { codexEffortFromPane, codexReasoningOption } from "./session-effort.ts";
import { beginPaneDrive, endPaneDrive, paneDriveInProgress } from "./pane-drive.ts";

// Codex's /model takes no inline argument. Pasting `/model <id>` submits an
// ordinary user turn. Drive its native picker without restarting the thread.
export function modelPickerIndex(pane: string, model: string): number | null {
  const prompt = parsePrompt(pane);
  if (!prompt || !/^Select Model(?: and Effort)?$/i.test(prompt.question)) return null;
  return prompt.options.find(option =>
    option.label.split(/\s/)[0]?.toLowerCase() === model.toLowerCase()
  )?.index ?? null;
}

/** The model row marked "(current)", falling back to the cursor row. */
export function currentModelPickerIndex(pane: string): number | null {
  const prompt = parsePrompt(pane);
  if (!prompt || !/^Select Model(?: and Effort)?$/i.test(prompt.question)) return null;
  return (prompt.options.find(option => /\(current\)/i.test(option.label))
    ?? prompt.options.find(option => option.selected))?.index ?? null;
}

type ReasoningScreen = {
  advanced: boolean;
  options: Array<{ index: number; label: string; selected: boolean }>;
  // The hint line offers `s session` — it follows the highlighted row, and
  // "More reasoning…" (a submenu, not a level) reads `enter select` instead.
  sessionKey: boolean;
};

const REASONING_TITLE = /^\s*(?:Select Reasoning Level|Advanced Reasoning)\b/i;
const REASONING_ROW = /^\s*(›)?\s*(\d+)\.\s+(\S.*?)\s*$/;

/**
 * Codex's reasoning screens, read directly rather than through parsePrompt:
 * that parser ignores single-row selectors on purpose (a lone "1." is more
 * often transcript than prompt), and "Advanced Reasoning" for a model whose
 * only extra level is Max has exactly one row.
 */
export function reasoningScreen(pane: string): ReasoningScreen | null {
  const lines = pane.split("\n");
  let title = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (REASONING_TITLE.test(lines[i]!)) {
      title = i;
      break;
    }
  }
  if (title < 0) return null;
  const options: ReasoningScreen["options"] = [];
  let sessionKey = false;
  for (const line of lines.slice(title + 1)) {
    const row = line.match(REASONING_ROW);
    if (row) options.push({ index: Number(row[2]), label: row[3]!, selected: !!row[1] });
    else if (/\besc back\b/.test(line)) {
      sessionKey = /\bs session\b/.test(line);
      break;
    }
  }
  if (!options.some(option => option.selected)) return null;
  return { advanced: /Advanced Reasoning/i.test(lines[title]!), options, sessionKey };
}

/** The reasoning-picker row for `effort`, or the "More reasoning…" row that
 * leads to it, or null when this screen offers neither. */
export function reasoningPickerIndex(pane: string, effort: string): { index: number; submenu: boolean } | null {
  const screen = reasoningScreen(pane);
  if (!screen) return null;
  const exact = screen.options.find(option => codexReasoningOption(option.label) === effort);
  if (exact) return { index: exact.index, submenu: false };
  const more = screen.options.find(option => codexReasoningOption(option.label) === "more");
  return more ? { index: more.index, submenu: true } : null;
}

const isModelPicker = (pane: string) => /^Select Model(?: and Effort)?$/i.test(parsePrompt(pane)?.question ?? "");
const composerVisible = (pane: string) => codexComposerIndex(pane.split("\n")) != null;

type PickerDriver = {
  key: (...keys: string[]) => boolean;
  waitFor: (predicate: (pane: string) => boolean, attempts?: number) => Promise<string | null>;
};

async function withCodexModelPicker(
  target: string,
  action: string,
  drive: (picker: string, driver: PickerDriver) => Promise<{ ok: boolean; error?: string }>,
): Promise<{ ok: boolean; error?: string }> {
  // One picker drive per pane at a time, model or effort: both walk the same menu.
  if (paneDriveInProgress(target)) return { ok: false, error: "A model or effort change is already in progress." };
  const initial = capturePane(target);
  const draft = initial == null ? null : inputBoxFromPane(initial)?.trim();
  if (initial == null || parsePrompt(initial) || draft == null || (draft !== "" && draft !== "Ask Codex to do anything")) {
    return { ok: false, error: `Finish the open Codex prompt or clear its draft before ${action}.` };
  }
  beginPaneDrive(target);
  const key = (...keys: string[]) => Bun.spawnSync(["tmux", "send-keys", "-t", target, ...keys]).exitCode === 0;
  const waitFor = async (predicate: (pane: string) => boolean, attempts = 30): Promise<string | null> => {
    for (let i = 0; i < attempts; i++) {
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
    const picker = await waitFor(isModelPicker);
    if (!picker) return { ok: false, error: "Codex did not open its model picker." };
    return await drive(picker, { key, waitFor });
  } finally {
    endPaneDrive(target);
  }
}

/** Back out of every nested picker screen without committing anything. A lone
 * Escape can sit in the TUI's input buffer, so re-check and re-send. */
async function leavePicker({ key, waitFor }: PickerDriver): Promise<void> {
  for (let i = 0; i < 4; i++) {
    key("Escape");
    if (await waitFor(composerVisible, 5)) return;
  }
}

export async function switchCodexModel(target: string, model: string): Promise<{ ok: boolean; error?: string }> {
  return withCodexModelPicker(target, "switching models", async (picker, { key, waitFor }) => {
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
  });
}

// Effort lives on the second screen of the same picker: re-pick the current
// model, then the level. Committed with `s` so it applies to this session only
// — Enter would save it as the default for every new Codex session. Arrow keys
// only: a digit commits immediately, i.e. as Enter.
export async function switchCodexEffort(target: string, effort: string): Promise<{ ok: boolean; error?: string }> {
  if (codexEffortFromPane(capturePane(target)) === effort) return { ok: true };
  return withCodexModelPicker(target, "changing effort", async (picker, driver) => {
    const { key, waitFor } = driver;
    const fail = async (error: string) => {
      await leavePicker(driver);
      return { ok: false, error };
    };
    // Move the reasoning screen's cursor to `index`; the screen once it is there.
    const highlight = async (index: number): Promise<ReasoningScreen | null> => {
      const screen = reasoningScreen(capturePane(target) ?? "");
      if (!screen) return null;
      const order = screen.options.map(option => option.index);
      const from = order.indexOf(screen.options.find(option => option.selected)!.index);
      const to = order.indexOf(index);
      if (to < 0) return null;
      for (let i = 0; i < Math.abs(to - from); i++) {
        key(to > from ? "Down" : "Up");
        await Bun.sleep(60);
      }
      const pane = await waitFor(p => reasoningScreen(p)?.options.find(option => option.selected)?.index === index);
      return pane ? reasoningScreen(pane) : null;
    };

    const current = currentModelPickerIndex(picker);
    if (current == null) return fail("Codex's model picker did not mark the current model.");
    const picked = await answerPrompt(target, current);
    if (!picked.ok) return fail(picked.error ?? "Could not select the current model.");
    const levels = await waitFor(p => reasoningScreen(p) != null || composerVisible(p));
    if (!levels) return fail("Codex did not open its reasoning picker.");
    // No reasoning screen: re-picking the current model was a no-op commit.
    if (!reasoningScreen(levels)) return { ok: false, error: "This Codex model has no effort levels." };

    let row = reasoningPickerIndex(levels, effort);
    if (row?.submenu) {
      if (!await highlight(row.index)) return fail("Codex did not highlight More reasoning….");
      key("Enter");
      const advanced = await waitFor(p => reasoningScreen(p)?.advanced === true);
      if (!advanced) return fail("Codex did not open its advanced reasoning levels.");
      row = reasoningPickerIndex(advanced, effort);
    }
    if (!row || row.submenu) return fail(`This Codex model does not offer ${effort} effort.`);
    const screen = await highlight(row.index);
    if (!screen) return fail("Codex did not highlight the effort level.");
    if (!screen.sessionKey) return fail("This Codex CLI cannot change effort for one session only. Update Codex.");
    key("s");
    // Max/Ultra play a banner animation in the footer for a few seconds.
    const confirmed = await waitFor(p => composerVisible(p) && codexEffortFromPane(p) === effort, 80);
    return confirmed ? { ok: true } : { ok: false, error: "Codex has not confirmed the new effort. Check its terminal." };
  });
}
