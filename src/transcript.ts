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
/** Stop growing past this in one step; still walks to the head of the file. */
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
 * Scan lines newest-first until `pick` returns non-null or the reader reaches
 * the head of the file.
 *
 * `pick` receives one raw line and returns the extracted value, or null to keep
 * looking. Returning null for every line in the whole transcript yields null —
 * which now genuinely means "not present", not "not in the window".
 *
 * `maxScanBytes` opts out of that guarantee on purpose, for callers whose answer
 * is decorative rather than load-bearing. A `pick` that `JSON.parse`s every line
 * costs the whole file when the answer isn't there — on a 511 MB Codex rollout
 * that is half a gigabyte of JSON parsed to fill a 140-character card preview,
 * and it was a large part of what put `lfg serve` over its RSS ceiling. Give it a
 * budget and it stops early, reporting "not found" the same way. Never set it on
 * a scan whose null answer changes session state.
 */
export async function scanBack<T>(
  path: string,
  pick: (line: string) => T | null,
  opts: { startBytes?: number; maxScanBytes?: number } = {},
): Promise<T | null> {
  const size = await sizeOf(path);
  if (size === 0) return null;
  const file = Bun.file(path);
  return scanBackWithReader(
    size,
    pick,
    async (start, end) => new Uint8Array(await file.slice(start, end).arrayBuffer()),
    opts,
  );
}

type ByteRangeReader = (start: number, end: number) => Promise<Uint8Array>;

/**
 * Backward JSONL scanner over an injected byte-range reader.
 *
 * Ranges are adjacent and never overlap. The old implementation widened the
 * tail and rescanned all previously-seen bytes after every miss; a lookup near
 * the head of a 535 MB rollout therefore read and allocated tens of gigabytes.
 * This walks the same file once, in steps capped at `maxStepBytes`.
 *
 * The leading partial record from each range is retained as BYTES and joined to
 * the next older range. Keeping it undecoded matters: a byte boundary may split
 * a UTF-8 scalar, and decoding each half independently would corrupt the JSON.
 */
export async function scanBackWithReader<T>(
  size: number,
  pick: (line: string) => T | null,
  read: ByteRangeReader,
  opts: { startBytes?: number; maxStepBytes?: number; maxScanBytes?: number } = {},
): Promise<T | null> {
  if (size <= 0) return null;
  const maxStep = Math.max(1, opts.maxStepBytes ?? MAX_STEP_BYTES);
  // The budget is a floor on where the walk may stop, not a hard read cap: the
  // range holding the budget boundary is read whole so no record is torn.
  const floor =
    opts.maxScanBytes === undefined ? 0 : Math.max(0, size - Math.max(1, opts.maxScanBytes));
  let step = Math.min(maxStep, Math.max(1, opts.startBytes ?? DEFAULT_START_BYTES));
  let end = size;
  let newerFragment = new Uint8Array(0);
  const decoder = new TextDecoder();

  const inspect = (bytes: Uint8Array): T | null => {
    if (bytes.length === 0) return null;
    const got = pick(decoder.decode(bytes));
    return got === undefined ? null : got;
  };

  while (end > 0) {
    const start = Math.max(0, end - step);
    const older = await read(start, end);
    const combined = new Uint8Array(older.length + newerFragment.length);
    combined.set(older);
    combined.set(newerFragment, older.length);

    // A mid-file range begins inside an arbitrary record. Save that fragment,
    // including its newline, to complete with the next older range. Everything
    // after it is a complete record and can be inspected newest-first now.
    let completeStart = 0;
    if (start > 0) {
      const newline = combined.indexOf(0x0a);
      if (newline < 0) {
        newerFragment = combined;
        end = start;
        if (end <= floor) return null;
        step = Math.min(maxStep, step * 4);
        continue;
      }
      newerFragment = combined.slice(0, newline + 1);
      completeStart = newline + 1;
    } else {
      newerFragment = new Uint8Array(0);
    }

    let lineEnd = combined.length;
    for (let i = combined.length - 1; i >= completeStart; i--) {
      if (combined[i] !== 0x0a) continue;
      const got = inspect(combined.subarray(i + 1, lineEnd));
      if (got !== null && got !== undefined) return got;
      lineEnd = i;
    }
    const got = inspect(combined.subarray(completeStart, lineEnd));
    if (got !== null && got !== undefined) return got;

    end = start;
    if (end <= floor) return null;
    step = Math.min(maxStep, step * 4);
  }
  return null;
}
