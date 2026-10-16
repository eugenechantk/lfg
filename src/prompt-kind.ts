// What kind of selector a session is waiting on, and what the S2 needs-input
// panel (canvas board `s2-question`) shows for it: a question's options, a
// permission's command, a plan's text. Plus when the agent started waiting.
//
// Kinds come from the pane, because only the TUI knows a permission dialog from
// a plan approval. Details come from the best source: the transcript's pending
// tool call for a permission (exact command, no wrapping), the plan file Claude
// wrote (`~/.claude/plans/*.md`, named in the dialog's footer) for a plan, and
// the pane as the fallback for both.

import type { PanePrompt } from "./tmux.ts";

export type PromptKind = "question" | "permission" | "plan" | "trust" | "signIn";
export type PromptPermission = { tool: string; command: string; detail?: string };
export type PromptPlan = { text: string; file?: string };
export type PromptDetails = { kind: PromptKind; permission?: PromptPermission; plan?: PromptPlan };

const RULE_RE = /^[─━]{5,}$/;
const DASHED_RE = /^╌{5,}$/;
const OPTION_ONE_RE = /^\s*(❯|›)?\s*1\.\s+\S/;
const PLAN_FILE_RE = /((?:~|\/[^\s]*)\/\.claude\/plans\/[^\s]+\.md)/;
const PERMISSION_QUESTION_RE = /^Do you want to (proceed|make this edit|create|overwrite|allow|run)\b/i;

// "Bash command" → "Bash", "Edit file" → "Edit". The dialog header names the tool.
function toolFromHeader(header: string): string {
  const h = header.trim();
  if (/^Bash\b/i.test(h)) return "Bash";
  if (/^(Edit|Update)\b/i.test(h)) return "Edit";
  if (/^(Write|Create)\b/i.test(h)) return "Write";
  if (/^Fetch\b/i.test(h)) return "WebFetch";
  return h.split(/\s+/)[0] ?? h;
}

function undent(lines: string[]): string {
  const indents = lines.filter((l) => l.trim()).map((l) => l.match(/^\s*/)![0].length);
  const cut = indents.length ? Math.min(...indents) : 0;
  return lines.map((l) => l.slice(cut).trimEnd()).join("\n").trim();
}

export function classifyPanePrompt(pane: string, prompt: PanePrompt): PromptDetails {
  const lines = pane.replace(/\s+$/, "").split("\n");
  let optLine = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (OPTION_ONE_RE.test(lines[i])) { optLine = i; break; }
  }
  if (optLine < 0) return { kind: "question" };

  // Plan approval: "Here is Claude's plan:" then a dashed rule, the plan, and a
  // solid rule before "Would you like to proceed?".
  const planHeader = lines.slice(0, optLine).findLastIndex((l) => /Here is Claude's plan:/.test(l));
  if (planHeader >= 0 || /Would you like to proceed\?/.test(prompt.question) && /plan/i.test(prompt.question)) {
    const body: string[] = [];
    if (planHeader >= 0) {
      let i = planHeader + 1;
      if (i < lines.length && DASHED_RE.test(lines[i].trim())) i++;
      for (; i < optLine; i++) {
        if (RULE_RE.test(lines[i].trim())) break;
        body.push(lines[i]);
      }
    }
    const file = lines.slice(optLine).join("\n").match(PLAN_FILE_RE)?.[1];
    return { kind: "plan", plan: { text: undent(body), ...(file ? { file } : {}) } };
  }

  // Permission: a tool header under the box's top rule, then what it will do,
  // then "Do you want to proceed?" (or "…make this edit to X?").
  const qLine = lines.slice(0, optLine).findLastIndex((l) => PERMISSION_QUESTION_RE.test(l.trim()));
  if (qLine >= 0 || prompt.options.some((o) => /^Yes, and (always allow|don't ask again)/i.test(o.label))) {
    const question = qLine >= 0 ? lines[qLine].trim() : prompt.question;
    let top = -1;
    for (let i = (qLine >= 0 ? qLine : optLine) - 1; i >= 0; i--) {
      if (RULE_RE.test(lines[i].trim())) { top = i; break; }
    }
    const block = top >= 0 ? lines.slice(top + 1, qLine >= 0 ? qLine : optLine) : [];
    const headerAt = block.findIndex((l) => l.trim());
    const tool = headerAt >= 0 ? toolFromHeader(block[headerAt]) : "Tool";
    if (tool === "Bash" && headerAt >= 0) {
      const body = block.slice(headerAt + 1).filter((l) => l.trim());
      // The last line is the call's description when there is more than one.
      const command = undent(body.length > 1 ? body.slice(0, -1) : body);
      const detail = body.length > 1 ? body[body.length - 1].trim() : undefined;
      return { kind: "permission", permission: { tool, command, ...(detail ? { detail } : {}) } };
    }
    return { kind: "permission", permission: { tool, command: "", detail: question } };
  }
  return { kind: "question" };
}

/** The permission card from the transcript's pending tool call: exact, unwrapped. */
export function permissionFromToolUse(name: string, input: Record<string, unknown> | null | undefined): PromptPermission {
  const str = (k: string) => (typeof input?.[k] === "string" ? (input[k] as string) : undefined);
  switch (name) {
    case "Bash": {
      const description = str("description");
      return { tool: name, command: str("command") ?? "", ...(description ? { detail: description } : {}) };
    }
    case "Edit": case "MultiEdit": case "Write": case "NotebookEdit":
      return { tool: name, command: str("file_path") ?? str("notebook_path") ?? "" };
    case "WebFetch":
      return { tool: name, command: str("url") ?? "" };
    case "WebSearch":
      return { tool: name, command: str("query") ?? "" };
    default:
      return { tool: name, command: "" };
  }
}

/**
 * Stamps `askedAt` (B3): when this session's current prompt was first seen.
 * Identity is the question and option labels — not the scraped `context`,
 * which grows while the prompt is up. A prompt that already carries `askedAt`
 * (a sign-in request's creation time) keeps it. A server restart re-stamps:
 * close enough for "Needs input · 2m".
 */
export class PromptClock {
  private seen = new Map<string, { identity: string; at: number }>();

  stamp<T>(sid: string, prompt: T, now: number): T {
    if (!prompt || typeof prompt !== "object") {
      this.seen.delete(sid);
      return prompt;
    }
    const p = prompt as { question?: unknown; options?: unknown; askedAt?: unknown };
    const labels = Array.isArray(p.options) ? p.options.map((o) => (o as { label?: unknown })?.label ?? "") : [];
    const identity = JSON.stringify([p.question ?? "", labels]);
    const prev = this.seen.get(sid);
    const at = typeof p.askedAt === "number" ? p.askedAt : prev && prev.identity === identity ? prev.at : now;
    this.seen.set(sid, { identity, at });
    return { ...prompt, askedAt: at };
  }

  forget(sid: string): void {
    this.seen.delete(sid);
  }
}
