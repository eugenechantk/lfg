// Reasoning effort of a live session: the vocabulary, how to read the current
// level off each CLI, and when a change is safe. Pure — the pane driving lives
// in codex-model-switch.ts and the Claude relaunch in tmux.ts.

// Every level either CLI has shipped. Claude's `--effort` accepts a subset;
// Codex offers a per-model subset (see model-catalog.ts). Anything else is
// refused before it can reach a command line or a key sequence.
export const EFFORT_LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"] as const;
export const CLAUDE_EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"] as const;

export function isEffortLevel(value: unknown): value is string {
  return typeof value === "string" && (EFFORT_LEVELS as readonly string[]).includes(value);
}

export function validateEffortForAgent(agent: "claude" | "codex", effort: string): string | null {
  if (!isEffortLevel(effort)) return `unknown effort "${effort}"`;
  if (agent === "claude" && !(CLAUDE_EFFORT_LEVELS as readonly string[]).includes(effort))
    return `Claude Code does not accept effort "${effort}"`;
  return null;
}

/** The value of a `--flag X` / `--flag=X` launch argument, or null. */
export function launchFlag(cmd: string, flag: "--effort" | "--model"): string | null {
  return cmd.match(new RegExp(`(?:^|\\s)${flag}(?:=|\\s+)(\\S+)`))?.[1] ?? null;
}

/**
 * The setting a Claude process is running with. The transcript stamps every
 * assistant turn with the live model and effort, so it reflects an in-TUI
 * `/model` or `/effort` — but a relaunch (how lfg switches both) writes nothing
 * until the next turn. So the transcript wins only when it was written by THIS
 * process; before that the launch flag is the truth, and an older transcript
 * value is the last resort (a bare `claude` with no flag inherits its default).
 */
export function liveLaunchSetting(opts: {
  flag: string | null;
  transcript: string | null;
  transcriptAt: number | null;
  processStartedAt: number | null;
}): string | null {
  const { flag, transcript, transcriptAt, processStartedAt } = opts;
  if (transcript && (processStartedAt == null || (transcriptAt != null && transcriptAt >= processStartedAt)))
    return transcript;
  return flag ?? transcript;
}

/** Effort from Codex's status footer ("GPT-6-Sol high fast · ~/dir"). Like the
 * model, only the current footer is authoritative after a native picker change. */
export function codexEffortFromPane(pane: string | null): string | null {
  const footer = pane?.split("\n").filter(line => line.trim()).at(-1)?.trim() ?? "";
  const level = footer.match(/^gpt-[\w.-]+\s+([a-z]+)\b[^·]*·\s/i)?.[1]?.toLowerCase();
  return level && isEffortLevel(level) ? level : null;
}

/**
 * Map a row of Codex's reasoning picker to an effort level. Rows read
 * "Extra high (current)   Extra high reasoning depth…": the name ends at the
 * first run of 2+ spaces. "More reasoning…" opens the Max/Ultra submenu.
 */
export function codexReasoningOption(label: string): string | null {
  const name = label.split(/\s{2,}/)[0]!.replace(/\((?:current|default)\)/gi, "").trim().toLowerCase();
  if (/^more reasoning/.test(name)) return "more";
  if (name === "extra high") return "xhigh";
  return isEffortLevel(name) ? name : null;
}

export function effortSwitchBlocker(agent: "claude" | "codex", state: {
  busy: boolean;
  queued: boolean;
  prompting: boolean;
}): string | null {
  const name = agent === "claude" ? "Claude" : "Codex";
  if (state.busy) return `Wait for ${name} to finish its current turn before changing effort.`;
  if (state.queued) return "Wait for queued messages to finish before changing effort.";
  if (state.prompting) return `Answer ${name}'s current prompt before changing effort.`;
  return null;
}
