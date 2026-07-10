// Registry of tmux sessions lfg started itself. Owning the session's tmux
// name is what makes the lifecycle deterministic: we created `tmux new-session
// -s <name>`, so we know the exact pane and can resolve its authoritative
// sessionId directly — no pgrep/parent-walk/newest-unclaimed guessing, so none
// of the ghost-panel / wrong-pid problems that plague attached sessions. The
// file survives a server restart so lfg still knows which live sessions it
// owns (for the managed badge, clean kill-session teardown, and following the
// sessionId when /clear rotates it).
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { PATHS } from "./config.ts";

export type ManagedSession = {
  tmuxName: string;
  cwd: string;
  createdAt: number;
  agent?: "claude" | "codex" | "aisdk" | "codex-aisdk" | "opencode";
  parentSessionId?: string;
};

function filePath(): string {
  return `${process.env.LFG_DATA ?? PATHS.data}/managed-sessions.json`;
}

function readAll(): Record<string, ManagedSession> {
  try {
    return JSON.parse(readFileSync(filePath(), "utf8")) as Record<string, ManagedSession>;
  } catch {
    return {};
  }
}

function writeAll(all: Record<string, ManagedSession>): void {
  const file = filePath();
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(all, null, 2));
}

export function normalizeParentSessionId(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 64) return undefined;
  return trimmed;
}

export function listManaged(): ManagedSession[] {
  return Object.values(readAll());
}

export function addManaged(rec: ManagedSession): void {
  const all = readAll();
  all[rec.tmuxName] = rec;
  writeAll(all);
}

export function removeManaged(tmuxName: string): void {
  const all = readAll();
  if (tmuxName in all) {
    delete all[tmuxName];
    writeAll(all);
  }
}

// Is this tmux name one we started? `target` may be a full pane target
// (`name:0.0`) or a bare session name — we compare on the session-name segment.
export function isManagedName(target: string | null): boolean {
  if (!target) return false;
  const name = target.split(":")[0];
  return name in readAll();
}
