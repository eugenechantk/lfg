/**
 * Per-file memo for the parts of a codex rollout that never change.
 *
 * `codexThreads()` runs on every live-list refresh, every closed-list page,
 * search and subagent lookups. It used to re-read the top of every rollout
 * each time: 128 KB for the `session_meta` header line, then up to 1 MB for
 * the first user message. With about 1,000 rollouts that was close to 1 GB of
 * reads per call, and the closed list took 17–23 s on the Pro (2026-10-16).
 *
 * Rollouts are append-only, so:
 * - the header line is final once it is a complete line;
 * - the first user message is final once the file has filled the read window,
 *   because the window's bytes can no longer change. Before that it is re-read
 *   only when the file's size changed.
 * A different birth time, or a file that shrank, is a different file.
 */

export type RolloutStat = { birthtimeMs: number; size: number };

type Entry<H> = {
  birthtimeMs: number;
  size: number;
  head: H | null;
  headFinal: boolean;
  firstUserText: string | null;
  firstUserSize: number;
  firstUserFinal: boolean;
};

export function createRolloutMemo<H>(opts: {
  /** Parse the header line. `final` false means the line may still be mid-write. */
  readHead: (path: string) => Promise<{ head: H | null; final: boolean }>;
  readFirstUserText: (path: string) => Promise<string | null>;
  /** How many bytes `readFirstUserText` looks at. */
  windowBytes: number;
}) {
  const entries = new Map<string, Entry<H>>();
  return {
    async get(path: string, stat: RolloutStat): Promise<{ head: H | null; firstUserText: string | null }> {
      let e = entries.get(path);
      if (!e || e.birthtimeMs !== stat.birthtimeMs || stat.size < e.size) {
        e = {
          birthtimeMs: stat.birthtimeMs,
          size: stat.size,
          head: null,
          headFinal: false,
          firstUserText: null,
          firstUserSize: -1,
          firstUserFinal: false,
        };
      }
      e.size = stat.size;
      entries.set(path, e);
      if (!e.headFinal) {
        const r = await opts.readHead(path);
        e.head = r.head;
        e.headFinal = r.final;
      }
      if (!e.head) return { head: null, firstUserText: null };
      if (!e.firstUserFinal && e.firstUserSize !== stat.size) {
        e.firstUserText = await opts.readFirstUserText(path);
        e.firstUserSize = stat.size;
        e.firstUserFinal = stat.size >= opts.windowBytes;
      }
      return { head: e.head, firstUserText: e.firstUserText };
    },
    /** Forget files that are gone. */
    prune(present: ReadonlySet<string>): void {
      for (const path of entries.keys()) if (!present.has(path)) entries.delete(path);
    },
    get size(): number {
      return entries.size;
    },
  };
}
