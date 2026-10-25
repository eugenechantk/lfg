// Claude's retry meter is UI-only: it need not produce a JSONL error until
// retries finish. Keep LFG's observations separate from provider-owned JSONL.
import { readFileSync, writeFileSync, renameSync, statSync } from "node:fs";
import { busyChromeRegions, isRuleLine, stripAnsi } from "./tmux.ts";
import type { SessionMsg } from "./sessions.ts";

type Notice = { text: string; errorCode: "rate_limit" };
type Stored = { active: string | null; messages: SessionMsg[] };
const sidecar = (path: string) => `${path}.lfg-notices.json`;
function hasComposer(pane: string): boolean {
  const lines = stripAnsi(pane).trimEnd().split("\n");
  let i = lines.length - 1;
  while (i >= 0 && !isRuleLine(lines[i])) i--;
  if (i < 0) return false;
  while (i >= 0 && isRuleLine(lines[i])) i--; // one border can wrap to several rows
  const bottom = i;
  while (i >= 0 && !isRuleLine(lines[i])) i--;
  return i >= 0 && lines.slice(i + 1, bottom + 1).some(line => line.trim());
}

export function claudePaneNotice(pane: string | null): Notice | null {
  if (!pane) return null;
  const plain = stripAnsi(pane);
  // A partial render or unbordered terminal cannot establish chrome ownership.
  if (!hasComposer(plain)) return null;
  const meter = busyChromeRegions(plain).meter;
  const match = meter.match(/^[✻✽✶✳✢✹✦✧·*]\s+((?:Weekly|Session|Usage|Rate) limit reached\s*·\s*Retrying in\s+[^\n]+(?:\n[ \t]+[^\n]+)*?\s*·\s*attempt\s+\d+\/\d+)/im);
  if (match) {
    // A live meter is the final activity above the composer. A code fence or
    // more prose after it proves this was quoted output, not the current meter.
    const after = meter.slice(match.index! + match[0].length).split("\n");
    if (after.some(line => line.trim() && !/^Update available!/i.test(line.trim()))) return null;
  }
  return match ? { text: match[1].replace(/\s+/g, " ").trim(), errorCode: "rate_limit" } : null;
}

function read(path: string): Stored {
  try {
    const data = JSON.parse(readFileSync(sidecar(path), "utf8")) as Stored;
    if (Array.isArray(data.messages)) return data;
  } catch {}
  return { active: null, messages: [] };
}

function save(path: string, data: Stored): void {
  const dest = sidecar(path);
  const temp = `${dest}.${process.pid}.tmp`;
  writeFileSync(temp, JSON.stringify(data), { mode: 0o600 });
  renameSync(temp, dest);
}

/** One event per waiting incident, not one per countdown or retry attempt. */
export function observeClaudePaneNotice(
  path: string, pane: string | null, now = Date.now(),
): { active: SessionMsg | null; added: SessionMsg | null } {
  // Failed capture is unknown, never evidence of recovery.
  if (pane == null) {
    const data = read(path);
    return { active: data.active ? data.messages.at(-1) ?? null : null, added: null };
  }
  const notice = claudePaneNotice(pane);
  const data = read(path);
  // Mid-render captures cannot prove the meter went away. Retain the incident
  // until a complete composer establishes a real recovery edge.
  if (!hasComposer(pane)) return { active: data.active ? data.messages.at(-1) ?? null : null, added: null };
  if (!notice) {
    if (data.active != null) { data.active = null; save(path, data); }
    return { active: null, added: null };
  }
  const key = `${notice.text.split(" · ")[0]}:${notice.text.match(/\(([^)]+)\)/)?.[1] ?? ""}`;
  const previous = data.messages.at(-1);
  if (data.active === key && previous) return { active: { ...previous, text: notice.text }, added: null };
  const m: SessionMsg = {
    id: `claude-notice:${statSync(path).size}:${now}`,
    role: "assistant", kind: "text", text: notice.text, ts: now,
    apiError: true, errorCode: notice.errorCode, apiErrorStatus: 429,
  };
  data.active = key;
  data.messages.push(m);
  save(path, data);
  return { active: m, added: m };
}

/** Merge chronologically without reordering the provider's own records. */
export function mergeClaudeNotices(path: string, messages: SessionMsg[]): SessionMsg[] {
  const notices = read(path).messages.filter(n => !messages.some(m =>
    m.id === n.id || (m.apiError && m.errorCode === n.errorCode
      && Math.abs((m.ts ?? 0) - (n.ts ?? 0)) < 10_000),
  ));
  if (!notices.length) return messages;
  const result: SessionMsg[] = [];
  let i = 0;
  for (const m of messages) {
    while (i < notices.length && m.ts != null && (notices[i].ts ?? 0) <= m.ts) result.push(notices[i++]);
    result.push(m);
  }
  result.push(...notices.slice(i));
  return result;
}
