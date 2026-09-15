// Scrolling a terminal socket's tmux history from a touch client.
//
// The shell behind /api/term runs inside tmux, so the transcript lives in
// tmux's scrollback, not in the client's emulator (tmux only ever redraws the
// visible screen). A client sends {"t":"scroll","lines":n} and we drive tmux
// copy-mode for that one session: n > 0 moves back in history, n < 0 forward.
// Copy-mode is entered with -e, so scrolling back to the bottom leaves it on
// its own.
//
// Copy-mode swallows keystrokes, so the first input after a scroll cancels it
// before writing. Commands and input share one queue to keep keystroke order.

export type TmuxRunner = (args: string[]) => Promise<number>;

export const runTmux: TmuxRunner = async (args) => {
  const proc = Bun.spawn(["tmux", ...args], { stdout: "ignore", stderr: "ignore" });
  return proc.exited;
};

const MAX_LINES = 1000;

export class TermScroll {
  private chain: Promise<void> = Promise.resolve();
  private pending = 0;
  // May be stale-true after `-e` auto-exits at the bottom; the cancel that
  // clears it is harmless when the pane is no longer in a mode.
  private inMode = false;

  constructor(private readonly target: string, private readonly run: TmuxRunner = runTmux) {}

  scroll(lines: number): Promise<void> {
    const n = Math.max(-MAX_LINES, Math.min(MAX_LINES, Math.trunc(lines)));
    if (n === 0) return this.idle();
    return this.enqueue(async () => {
      if (n < 0 && !this.inMode) return; // already at the live screen
      if (n > 0 && !this.inMode) {
        await this.run(["copy-mode", "-e", "-t", this.target]);
        this.inMode = true;
      }
      await this.run(["send-keys", "-t", this.target, "-X", "-N", String(Math.abs(n)), n > 0 ? "scroll-up" : "scroll-down"]);
    });
  }

  /** Write input now if nothing is queued and tmux is live; otherwise after the queue. */
  input(write: () => void): void {
    if (this.pending === 0 && !this.inMode) {
      write();
      return;
    }
    void this.enqueue(async () => {
      if (this.inMode) {
        this.inMode = false;
        await this.run(["send-keys", "-t", this.target, "-X", "cancel"]);
      }
      write();
    });
  }

  idle(): Promise<void> {
    return this.chain;
  }

  private enqueue(step: () => Promise<void>): Promise<void> {
    this.pending++;
    this.chain = this.chain
      .then(step)
      .catch(() => {})
      .finally(() => { this.pending--; });
    return this.chain;
  }
}
