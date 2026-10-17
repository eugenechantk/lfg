// Provider retraction, rather than deleting only LFG's receipt. Claude's Up
// recalls ALL queued inputs; its popAll journal records their exact payloads.
// Codex's shared daemon supports deleting one stable submission. Older/local
// TUI queues can be recalled newest-first with Alt+Up.
import { capturePaneAsync, inputBoxFromPane } from "./tmux.ts";
import { withCodexDaemonRequest, type CodexRequest } from "./codex-app-server.ts";

export function recalledClaudeMessages(lines: string[]): string[] {
  return lines.flatMap(line => {
    try {
      const x = JSON.parse(line);
      return x.type === "queue-operation" && x.operation === "popAll" && typeof x.content === "string"
        ? [x.content] : [];
    } catch { return []; }
  });
}

export function clearRecalledDraftKeys(text: string): string[] {
  // Ctrl-U removes one logical line, then its newline on the next press.
  // Escape would interrupt the active tool; never use it to clear this draft.
  return ["C-e", ...Array(text.split(/\r\n|\r|\n/).length * 2 + 2).fill("C-u"), "C-a", "C-k"];
}

type CodexQueuedEntry = { id: string; clientUserMessageId: string; input: Array<{ type: string; text?: string }> };

/** null means no matching native entry; false means ambiguous or consumed. */
export async function retractCodexQueueEntry(
  request: CodexRequest, threadId: string, clientId: string, text: string,
): Promise<boolean | null> {
  const entries: CodexQueuedEntry[] = [];
  const seen = new Set<string>();
  let cursor: string | undefined;
  do {
    const result = await request("thread/queue/list", { threadId, ...(cursor ? { cursor } : {}), limit: 100 });
    if (!Array.isArray(result?.data)) throw new Error("Codex returned an unreadable queue");
    entries.push(...result.data);
    cursor = result.nextCursor || undefined;
    if (cursor && seen.has(cursor)) throw new Error("Codex repeated a queue page");
    if (cursor) seen.add(cursor);
  } while (cursor);
  const exactClient = entries.filter(entry => entry.clientUserMessageId === clientId);
  const candidates = exactClient.length ? exactClient : entries.filter(entry =>
    entry.input.length === 1 && entry.input[0]?.type === "text" && entry.input[0].text === text);
  if (!candidates.length) return null;
  if (candidates.length !== 1) return false;
  const result = await request("thread/queue/delete", { threadId, queuedSubmissionId: candidates[0]!.id });
  return result?.deleted === true;
}

function normalized(text: string): string { return text.replace(/\s+/g, " ").trim(); }

function draft(pane: string | null): string | null {
  if (pane == null) return null;
  const box = inputBoxFromPane(pane);
  return box == null ? null : box.replace(/^\s*[❯›]\s?/, "").trim();
}

export function canRecallClaudeQueue(pane: string | null): boolean {
  const box = draft(pane);
  // On an empty composer without a native queue, Up recalls command history.
  // Require the provider's positive recall cue before sending a key.
  return pane?.includes("Press up to edit queued messages") === true
    && (box === "" || box === "Press up to edit queued messages");
}

async function keys(target: string, keyNames: string[]): Promise<boolean> {
  // Bound argv even for a very large recalled multiline message.
  for (let offset = 0; offset < keyNames.length; offset += 128) {
    const proc = Bun.spawn(["tmux", "send-keys", "-t", target, ...keyNames.slice(offset, offset + 128)],
      { stdout: "ignore", stderr: "ignore" });
    if (await proc.exited !== 0) return false;
  }
  return true;
}

async function clearDraft(target: string, text: string): Promise<boolean> {
  if (!await keys(target, clearRecalledDraftKeys(text))) return false;
  for (let i = 0; i < 15; i++) {
    await Bun.sleep(100);
    if (draft(await capturePaneAsync(target)) === "") return true;
  }
  return false;
}

export type NativeQueueRetraction = {
  agent: string;
  sessionId: string;
  target: string;
  transcriptPath: string | null;
  clientId: string;
  text: string;
  // In send order. Only these payloads may be cleared from a local Codex TUI.
  queuedTexts: string[];
  // Persist ownership BEFORE clearing the recalled composer. On a host restart
  // the durable pump can still deliver all siblings with their original bytes.
  onRecalled: (texts: string[]) => void;
};

async function recallClaude(opts: NativeQueueRetraction): Promise<boolean> {
  if (!opts.transcriptPath) return false;
  const pane = await capturePaneAsync(opts.target);
  // Do not overwrite a person's terminal draft or send Up into a selector.
  if (!canRecallClaudeQueue(pane)) return false;
  const offset = Bun.file(opts.transcriptPath).size;
  if (!await keys(opts.target, ["Up"])) return false;
  let recalled: string[] = [];
  let previousCount = -1;
  for (let i = 0; i < 25; i++) {
    await Bun.sleep(100);
    const delta = await Bun.file(opts.transcriptPath).slice(offset).text();
    recalled = recalledClaudeMessages(delta.split("\n"));
    // popAll writes one receipt per entry. Wait for the complete batch.
    if (recalled.length && recalled.length === previousCount) break;
    previousCount = recalled.length;
  }
  if (!recalled.length) return false;
  opts.onRecalled(recalled);
  const cleared = await clearDraft(opts.target, recalled.join("\n"));
  return cleared && recalled.some(text => text === opts.text);
}

async function recallCodex(opts: NativeQueueRetraction): Promise<boolean> {
  // The daemon API covers durable queues, including long text and attachments.
  // TUI-local queues predate it. Recall only a known complete payload there;
  // an unrecognised entry goes straight back via Tab, with its native metadata.
  if (draft(await capturePaneAsync(opts.target)) !== "") return false;
  const candidates = [...opts.queuedTexts].reverse();
  for (const expected of candidates) {
    if (!await keys(opts.target, ["M-Up"])) return false;
    let box: string | null = null;
    for (let i = 0; i < 15; i++) {
      await Bun.sleep(100);
      box = draft(await capturePaneAsync(opts.target));
      if (box) break;
    }
    if (box == null || box === "") return false;
    if (normalized(box) !== normalized(expected)) {
      await keys(opts.target, ["Tab"]);
      return false;
    }
    opts.onRecalled([expected]);
    if (!await clearDraft(opts.target, expected)) return false;
    if (expected === opts.text) return true;
  }
  return false;
}

export async function retractNativeQueue(opts: NativeQueueRetraction): Promise<boolean> {
  if (opts.agent === "claude") return recallClaude(opts);
  if (opts.agent !== "codex") return false;
  let deleteAttempted = false;
  try {
    const deleted = await withCodexDaemonRequest(request => retractCodexQueueEntry((method, params) => {
      if (method === "thread/queue/delete") deleteAttempted = true;
      return request(method, params);
    }, opts.sessionId, opts.clientId, opts.text));
    if (deleted != null) return deleted;
  } catch {
    // A timed-out deletion may have succeeded. Never replay it through the TUI.
    if (deleteAttempted) return false;
    // An older Codex can lack the daemon or experimental queue methods.
  }
  return recallCodex(opts);
}
