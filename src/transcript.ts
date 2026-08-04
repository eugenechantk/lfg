// One reader for JSONL transcripts.
//
// Every question about a transcript used to re-open the file, pick its own byte
// window, and reverse-scan: ten call sites, six different window constants
// (256K x3, 128K, 64K, 32K). Two problems followed from that.
//
// 1. **Silent misses.** If the answer fell outside the hand-picked window — one
//    long tool output will do it — the scan returned null and the caller
//    rendered "no model" / "no last message" / no prompt. The natural fix was to
//    bump that one constant, which fixed one call site out of ten. `scanBack`
//    instead *grows* the window until it finds the answer or reaches the head of
//    the file, so a miss means "not in the transcript", not "not in the window".
//
// 2. **Cost.** A growing window is also *cheaper* in the common case, because it
//    can start well below the old fixed 256K: the answer is usually within a few
//    KB of the tail, and the window only grows on the rare miss that used to be
//    a silent bug.
//
// Reading a tail slice mid-file almost always cuts a line in half. Every old
// call site relied on `JSON.parse` throwing on that fragment and `continue`-ing
// past it, which works but is implicit and breaks for any non-JSON scan. Here it
// is explicit: a window that does not start at byte 0 drops its first line.

/** Default first window. Comfortably covers a few turns; grows on a miss. */
export const DEFAULT_START_BYTES = 64 * 1024;
/** Stop doubling past this in one step; still walks to the head of the file. */
export const MAX_STEP_BYTES = 4 * 1024 * 1024;

export type Window = {
  /** Whole lines, blank lines dropped. A leading partial line is removed. */
  lines: string[];
  /** True when this window reaches byte 0 — nothing older exists to read. */
  atHead: boolean;
};

/** Split a slice into whole lines, dropping a leading fragment when mid-file. */
export function windowFromSlice(text: string, startedAtByte: number): Window {
  const lines = text.split("\n");
  if (startedAtByte > 0) lines.shift(); // partial first line
  return { lines: lines.filter(Boolean), atHead: startedAtByte === 0 };
}

async function sizeOf(path: string): Promise<number> {
  try {
    return Bun.file(path).size;
  } catch {
    return 0;
  }
}

/** Read the last `bytes` of `path` as whole lines. */
export async function tail(path: string, bytes: number): Promise<Window> {
  try {
    const file = Bun.file(path);
    const size = file.size;
    const start = Math.max(0, size - bytes);
    const text = await file.slice(start).text();
    return windowFromSlice(text, start);
  } catch {
    return { lines: [], atHead: true };
  }
}

/** Read the first `bytes` of `path` as whole lines. */
export async function head(path: string, bytes: number): Promise<string[]> {
  try {
    const text = await Bun.file(path).slice(0, bytes).text();
    // A trailing fragment is fine to keep: callers scanning forward stop early,
    // and a fragment simply fails to parse.
    return text.split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Scan lines newest-first, growing the window until `pick` returns non-null or
 * the window reaches the head of the file.
 *
 * `pick` receives one raw line and returns the extracted value, or null to keep
 * looking. Returning null for every line in the whole transcript yields null —
 * which now genuinely means "not present", not "not in the window".
 */
export async function scanBack<T>(
  path: string,
  pick: (line: string) => T | null,
  opts: { startBytes?: number } = {},
): Promise<T | null> {
  const size = await sizeOf(path);
  if (size === 0) return null;
  let bytes = Math.max(1, opts.startBytes ?? DEFAULT_START_BYTES);

  // Each round rescans the whole (larger) window rather than only the newly
  // exposed head of it. Tracking "already scanned" by line count is off by one
  // whenever a round drops a different partial first line, and skipping a line
  // is precisely the silent miss this function exists to remove. Growth only
  // happens on a miss, which is rare, so the repeat scan is cheap insurance.
  while (true) {
    const w = await tail(path, bytes);
    for (let i = w.lines.length - 1; i >= 0; i--) {
      const got = pick(w.lines[i]);
      if (got !== null && got !== undefined) return got;
    }
    if (w.atHead) return null;
    bytes = Math.min(bytes * 4, bytes + MAX_STEP_BYTES);
  }
}
