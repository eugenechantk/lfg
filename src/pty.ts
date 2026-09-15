// PTY bridge on Bun's native terminal support (`Bun.spawn({ terminal })`).
//
// This replaced a hand-rolled bun:ffi openpty bridge. That bridge set the
// master fd non-blocking with fcntl(F_SETFL, O_NONBLOCK) and resized with
// ioctl(TIOCSWINSZ) — both variadic C functions. Bun FFI passes variadic
// arguments in registers, but Apple arm64 expects them on the stack, so both
// calls were silent no-ops on Apple Silicon: the drain loop's read() blocked the
// single event loop the whole server runs on (keystrokes never arrived, HTTP
// stalled) and resize did nothing. Bun owns the pty now: output arrives through
// the event loop, and the child is a session leader on the pty's slave end, so
// `tmux attach` gets the controlling terminal it needs.

export interface PtyOptions {
  cols?: number;
  rows?: number;
  cwd?: string;
  env?: Record<string, string | undefined>;
}

export class PtyBridge {
  private proc: Bun.Subprocess | null = null;
  private terminal: Bun.Terminal | null = null;
  private dataCb: ((chunk: Uint8Array) => void) | null = null;
  private exitCb: (() => void) | null = null;
  // Output that arrived before onData was registered (the child can print
  // before the caller wires the socket up).
  private pending: Uint8Array[] = [];
  private closed = false;
  private exited = false;

  constructor(argv: string[], opts: PtyOptions = {}) {
    this.proc = Bun.spawn(argv, {
      cwd: opts.cwd,
      env: { TERM: "xterm-256color", ...process.env, ...opts.env },
      terminal: {
        cols: opts.cols ?? 80,
        rows: opts.rows ?? 24,
        data: (_term, chunk) => {
          if (this.closed) return;
          // Copy: Bun may reuse the chunk's backing buffer.
          const copy = new Uint8Array(chunk);
          if (this.dataCb) this.dataCb(copy);
          else this.pending.push(copy);
        },
      },
    });
    this.terminal = this.proc.terminal ?? null;
    if (!this.terminal) {
      this.proc.kill();
      throw new Error("Bun did not allocate a terminal for the child");
    }
    this.proc.exited.then(() => {
      this.exited = true;
      if (this.closed) return;
      this.close();
      this.exitCb?.();
    });
  }

  onData(cb: (chunk: Uint8Array) => void): void {
    this.dataCb = cb;
    const backlog = this.pending;
    this.pending = [];
    for (const chunk of backlog) cb(chunk);
  }

  onExit(cb: () => void): void {
    this.exitCb = cb;
    // The child may already be gone (e.g. `sh -c "exit 0"`).
    if (this.exited && this.closed) cb();
  }

  write(data: Uint8Array | string): void {
    if (this.closed || !this.terminal) return;
    this.terminal.write(data);
  }

  resize(cols: number, rows: number): void {
    if (this.closed || !this.terminal) return;
    // Resizing the pty raises SIGWINCH in the foreground process, so an attached
    // TUI repaints at the new geometry on its own.
    this.terminal.resize(cols, rows);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.pending = [];
    // Tear down only our attach client. The tmux *session* is detached, not
    // killed, so the shell survives for the next connect.
    try { this.proc?.kill(); } catch {}
    try { this.terminal?.close(); } catch {}
    this.terminal = null;
    this.proc = null;
  }
}

// Sanitize a caller-supplied terminal id into a tmux session name fragment:
// tmux session names can't contain `.` or `:` and we don't want shell-hostile
// chars. Keep it short and predictable.
export function termSessionName(id: string): string {
  const safe = (id || "main").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 32) || "main";
  return `lfg-term-${safe}`;
}
