// Panes lfg is typing into on the user's behalf — Codex's /model picker, walked
// for a model or effort change. The selectors on screen meanwhile are lfg's own
// keystrokes in flight, not a question for the user, so every surface that
// turns a pane into a prompt (journal pump, push watcher, status summary) skips
// them. Measured before this existed: an effort change journaled a "Select Model
// and Effort" prompt, retracted 3 s later — a needs-input flash, and a push
// whenever the watcher's tick landed inside the drive.
//
// The grace window covers a capture taken mid-drive but read after it ended.
const GRACE_MS = 3_000;

// target → null while driving, else when the drive ended.
const drives = new Map<string, number | null>();

export function beginPaneDrive(target: string): void {
  drives.set(target, null);
}

export function endPaneDrive(target: string, now = Date.now()): void {
  drives.set(target, now);
}

/** A drive is running on this pane right now (one at a time per pane). */
export function paneDriveInProgress(target: string): boolean {
  return drives.has(target) && drives.get(target) == null;
}

/** Whether a selector scraped from this pane must not surface as a prompt. */
export function panePromptSuppressed(target: string | null | undefined, now = Date.now()): boolean {
  if (!target || !drives.has(target)) return false;
  const endedAt = drives.get(target);
  if (endedAt == null || now - endedAt < GRACE_MS) return true;
  drives.delete(target);
  return false;
}
