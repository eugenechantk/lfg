export function claudeModelSwitchBlocker(state: {
  busy: boolean;
  queued: boolean;
  prompting: boolean;
}): string | null {
  if (state.busy) return "Wait for Claude to finish its current turn before switching models.";
  if (state.queued) return "Wait for queued messages to finish before switching models.";
  if (state.prompting) return "Answer Claude's current prompt before switching models.";
  return null;
}
