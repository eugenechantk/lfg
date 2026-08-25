// Runs one auto agent: build a prompt from the agent's instruction + the
// dismiss-feedback block, pipe it to a real headless Claude session with
// read-only tools, and parse at most ONE finding out of the result. Most runs
// should return null — silence is the default, not a padded report.

import { PATHS } from "../config.ts";
import {
  type AutoAgent,
  type Finding,
  type Severity,
  addFinding,
  clearRunning,
  hasOpenSimilar,
  listFindings,
  markRunning,
} from "./store.ts";

const SYSTEM = `You are an autonomous watch agent. Carry out the instruction below.

You have read-only tools (Read, Grep, Glob, WebSearch, WebFetch) — use them to
gather your own context. Decide whether there is ONE finding worth surfacing as
a notification right now. Be strict: most runs should surface nothing. Only
surface something concrete, high-leverage, and actionable — never filler.

Respond with ONLY a JSON object as the final thing you output. No prose around
it, no markdown fence. One of:

{"finding": null}

or

{"finding": {"title": "<one line>", "severity": "high" | "med" | "low", "reasoning": ["<short bullet>", "..."], "suggest": "<one-line concrete fix>"}}

Rules: title is one line. At most 4 short reasoning bullets. No essay.`;

function normSeverity(s: unknown): Severity {
  const v = String(s ?? "").toLowerCase();
  if (v.startsWith("h")) return "high";
  if (v.startsWith("l")) return "low";
  return "med";
}

function parseFinding(text: string): { finding: unknown } | null {
  const tryParse = (s: string): any => {
    try {
      return JSON.parse(s);
    } catch {
      return null;
    }
  };
  let j: any = tryParse(text.trim());
  if (!j) {
    const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fence) j = tryParse(fence[1].trim());
  }
  if (!j) {
    // last balanced-ish object in the text
    const m = text.match(/\{[\s\S]*\}/);
    if (m) j = tryParse(m[0]);
  }
  if (!j || typeof j !== "object") return null;
  if (!("finding" in j)) {
    if ("title" in j) return { finding: j };
    return null;
  }
  return j;
}

const READONLY_TOOLS = ["Read", "Grep", "Glob", "WebSearch", "WebFetch"];

async function runClaude(
  prompt: string,
  cwd: string,
  onLog: (s: string) => void,
  extraTools: string[] = [],
): Promise<string> {
  const allowedTools = [...READONLY_TOOLS, ...extraTools];
  onLog(`[auto] claude run (${prompt.length} chars) in ${cwd} [tools: ${allowedTools.join(",")}]`);
  // Headless `claude -p` on the agent's cwd. A run that produces no output is
  // returned as "" — parseFinding treats it as silence (null finding), which is
  // the default outcome for a watch agent, not an error.
  const proc = Bun.spawn({
    cmd: ["claude", "-p", "--allowedTools", allowedTools.join(",")],
    cwd,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env },
  });
  proc.stdin.write(prompt);
  await proc.stdin.end();
  const [out, errText, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  if (exitCode !== 0) {
    throw new Error(
      `claude -p exited ${exitCode}: ${(errText || out).slice(0, 400)}`,
    );
  }
  return out.trim();
}

export async function runAutoAgent(
  agent: AutoAgent,
  onLog: (s: string) => void = () => {},
): Promise<Finding | null> {
  // Mark in-flight synchronously (before the first await) so a manual /run is
  // already "running" by the time the POST returns; always clear when done.
  markRunning(agent.id);
  try {
    return await runAutoAgentInner(agent, onLog);
  } finally {
    clearRunning(agent.id);
  }
}

async function runAutoAgentInner(
  agent: AutoAgent,
  onLog: (s: string) => void = () => {},
): Promise<Finding | null> {
  const mine = (await listFindings()).filter((f) => f.agentId === agent.id);
  const dismissed = mine.filter((f) => f.status === "dismissed").slice(0, 20);
  const open = mine.filter((f) => f.status === "open").slice(0, 20);

  let feedback = "";
  if (dismissed.length) {
    feedback +=
      "\n\n## The human DISMISSED these — do NOT resurface them:\n" +
      dismissed.map((f) => `- ${f.title}`).join("\n");
  }
  if (open.length) {
    feedback +=
      "\n\n## Already open (don't repeat):\n" +
      open.map((f) => `- ${f.title}`).join("\n");
  }

  const prompt = `${SYSTEM}\n\n## Instruction\n${agent.prompt}${feedback}`;
  // The agent's base repo (chosen from the repo list in the UI) is where it runs
  // and from which it inherits .claude/settings.json. If it's unset, fall back to
  // the repo root but say so loudly — a missing base means the agent is watching
  // the wrong tree, which is exactly the silent-misconfig we want surfaced.
  const cwd = agent.cwd ?? PATHS.root;
  if (!agent.cwd) {
    onLog(`[auto] WARNING: agent "${agent.id}" has no base repo (cwd) — defaulting to ${PATHS.root}; set one in the editor`);
  }
  const result = await runClaude(prompt, cwd, onLog, agent.tools ?? []);

  const parsed = parseFinding(result);
  if (!parsed) {
    onLog("[auto] no parseable finding — treating as silence");
    return null;
  }
  if (parsed.finding == null) {
    onLog("[auto] agent surfaced nothing");
    return null;
  }
  const f = parsed.finding as Record<string, unknown>;
  const title = String(f.title ?? "").trim();
  if (!title) {
    onLog("[auto] finding had no title — skipping");
    return null;
  }
  if (await hasOpenSimilar(agent.id, title)) {
    onLog(`[auto] duplicate of an existing finding — skipping: ${title}`);
    return null;
  }
  const finding = await addFinding({
    agentId: agent.id,
    title,
    severity: normSeverity(f.severity),
    reasoning: Array.isArray(f.reasoning)
      ? f.reasoning.map((r) => String(r)).slice(0, 6)
      : [],
    suggest: f.suggest ? String(f.suggest) : undefined,
  });
  onLog(`[auto] new finding: ${title}`);
  return finding;
}
