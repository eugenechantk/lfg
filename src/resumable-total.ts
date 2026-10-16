/**
 * B12: how many closed sessions `GET /api/sessions/resumable` pages through, so
 * the desktop can say "Recent 2,914" instead of the size of the page it loaded.
 *
 * A session is closed when nothing holds a fresh lease on it (`anyFreshAt`), and
 * leases sit beside each transcript, so an exact count is one small file read per
 * transcript — about 3,000 on the Pro. That is too much for every list request on
 * the single event loop, so the count runs in the background at most once per TTL
 * per hidden-folder set and requests read the cached number. Before the first
 * count lands the answer is null, which clients treat like an older host that
 * omits the field.
 */

export type ClosedCandidate = { id: string; path: string };

/** Count the candidates that no host holds a fresh lease on. */
export async function countClosed(
  candidates: ClosedCandidate[],
  isFresh: (id: string, path: string) => Promise<unknown>,
): Promise<number> {
  let closed = 0;
  for (const c of candidates) {
    if (!(await isFresh(c.id, c.path))) closed++;
  }
  return closed;
}

type Entry = { total: number | null; at: number; running: Promise<void> | null };

/**
 * A per-key cache of background counts. `get` returns the last count for the
 * key (null before the first lands) and starts a recount when the last one is
 * older than the TTL. One count per key runs at a time; a failed count keeps the
 * previous number and is retried after the TTL.
 */
export function createTotalCache(
  compute: (key: string) => Promise<number>,
  opts: { ttlMs?: number; now?: () => number } = {},
) {
  const ttl = opts.ttlMs ?? 60_000;
  const now = opts.now ?? Date.now;
  const entries = new Map<string, Entry>();
  return {
    get(key: string): number | null {
      let entry = entries.get(key);
      if (!entry) {
        entry = { total: null, at: -Infinity, running: null };
        entries.set(key, entry);
      }
      if (!entry.running && now() - entry.at >= ttl) {
        const e = entry;
        e.running = compute(key)
          .then((total) => {
            e.total = total;
            e.at = now();
          })
          .catch(() => {
            e.at = now();
          })
          .finally(() => {
            e.running = null;
          });
      }
      return entry.total;
    },
    /** Wait for the key's in-flight count (tests). */
    async settle(key: string): Promise<void> {
      await entries.get(key)?.running;
    },
  };
}
