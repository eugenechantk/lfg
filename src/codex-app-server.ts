import { codexBin } from "./tmux.ts";

const UUID_EXACT = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function readProtocolLine(
  reader: { read: () => Promise<{ done: boolean; value?: Uint8Array }> },
  state: { buffer: string },
  predicate: (value: unknown) => boolean,
  deadline: number,
): Promise<unknown> {
  const decoder = new TextDecoder();
  while (Date.now() < deadline) {
    let newline = state.buffer.indexOf("\n");
    while (newline >= 0) {
      const line = state.buffer.slice(0, newline);
      state.buffer = state.buffer.slice(newline + 1);
      try {
        const parsed = JSON.parse(line);
        if (predicate(parsed)) return parsed;
      } catch {}
      newline = state.buffer.indexOf("\n");
    }
    const remaining = Math.max(1, deadline - Date.now());
    const chunk = await Promise.race([
      reader.read(),
      Bun.sleep(remaining).then(() => null),
    ]);
    if (chunk == null) throw new Error("Codex app-server request timed out");
    if (chunk.done || !chunk.value) throw new Error("Codex app-server exited before replying");
    state.buffer += decoder.decode(chunk.value, { stream: true });
  }
  throw new Error("Codex app-server request timed out");
}

export function parseThreadForkResponse(value: unknown, sourceId: string): string {
  const response = value as {
    error?: { message?: unknown };
    result?: { thread?: { id?: unknown; forkedFromId?: unknown } };
  };
  if (response?.error) {
    throw new Error(
      typeof response.error.message === "string"
        ? response.error.message
        : "Codex app-server could not fork the thread",
    );
  }
  const id = response?.result?.thread?.id;
  if (typeof id !== "string" || !UUID_EXACT.test(id)) {
    throw new Error("Codex app-server fork did not return a thread ID");
  }
  if (id === sourceId) throw new Error("Codex app-server fork did not return a distinct thread ID");
  const forkedFrom = response.result?.thread?.forkedFromId;
  if (typeof forkedFrom === "string" && forkedFrom !== sourceId) {
    throw new Error("Codex app-server fork returned an unexpected source thread");
  }
  return id;
}

/**
 * Fork a Codex thread through a short-lived app-server process.
 *
 * Unlike `codex fork <id>`, `thread/fork` reads the source and creates a new
 * thread without attempting to acquire its writer lock. This is the safe path
 * when ChatGPT Desktop still owns the source. The app-server is stopped before
 * returning so the caller can immediately attach an LFG-owned TUI to the fork.
 */
export async function forkCodexThreadViaAppServer(opts: {
  threadId: string;
  cwd?: string | null;
  model?: string;
  timeoutMs?: number;
}): Promise<string> {
  const proc = Bun.spawn([codexBin(), "app-server", "--stdio"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "ignore",
  });
  try {
    if (!proc.stdin || typeof proc.stdin === "number"
        || !proc.stdout || typeof proc.stdout === "number") {
      throw new Error("Codex app-server stdio is unavailable");
    }
    const reader = proc.stdout.getReader();
    const state = { buffer: "" };
    const deadline = Date.now() + (opts.timeoutMs ?? 30_000);
    proc.stdin.write(JSON.stringify({
      id: 1,
      method: "initialize",
      params: { clientInfo: { name: "lfg", version: "1" }, capabilities: {} },
    }) + "\n");
    await readProtocolLine(reader, state, value => (value as { id?: unknown })?.id === 1, deadline);
    proc.stdin.write(JSON.stringify({ method: "initialized", params: {} }) + "\n");
    proc.stdin.write(JSON.stringify({
      id: 2,
      method: "thread/fork",
      params: {
        threadId: opts.threadId,
        excludeTurns: true,
        ...(opts.cwd ? { cwd: opts.cwd } : {}),
        ...(opts.model ? { model: opts.model } : {}),
      },
    }) + "\n");
    const response = await readProtocolLine(
      reader,
      state,
      value => (value as { id?: unknown })?.id === 2,
      deadline,
    );
    return parseThreadForkResponse(response, opts.threadId);
  } finally {
    try { proc.kill(); } catch {}
    let exited = false;
    await Promise.race([
      proc.exited.then(() => { exited = true; }).catch(() => { exited = true; }),
      Bun.sleep(1_000),
    ]);
    // The forked thread has its own writer lock. Do not hand it to the TUI until
    // the short-lived app-server is definitely gone, or the resume races that
    // lock and exits even though the fork itself succeeded.
    if (!exited) {
      try { proc.kill("SIGKILL"); } catch {}
      await Promise.race([proc.exited.catch(() => undefined), Bun.sleep(2_000)]);
    }
  }
}
