// Cross-platform process introspection shim.
//
// lfg's session discovery needs four things about a live pid: its full command
// line (to find `claude`/`codex` procs), its cwd, its start time, and its
// parent pid. On Linux these come from /proc and `pgrep -af`. macOS has no
// /proc and its BSD `pgrep` lacks `-a`, so the Darwin branch shells out to
// `ps`/`lsof` instead. Every function returns the SAME shape/units as the Linux
// path (ms-epoch start time, absolute cwd, numeric ppid) so all downstream
// heuristics in sessions.ts/tmux.ts are untouched.
//
// All functions are best-effort: a dead/missing pid yields null, never a throw.
import { readlink } from "node:fs/promises";
import { statSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const IS_DARWIN = process.platform === "darwin";

function spawnText(cmd: string[]): string | null {
  try {
    const r = Bun.spawnSync(cmd);
    if (r.exitCode !== 0 && !r.stdout) return null;
    return new TextDecoder().decode(r.stdout);
  } catch {
    return null;
  }
}

// macOS perf shim. listSessions() enriches dozens of procs and each Darwin
// helper here shells out to `ps`/`lsof` synchronously — and Bun.spawnSync
// blocks the single event loop, so hundreds of per-pid spawns freeze ALL HTTP
// (including sends) for seconds. Two caches collapse that storm:
//   - ppidMap(): ONE `ps -axo pid=,ppid=` snapshot (TTL) instead of one
//     `ps -o ppid=` per pid (the parent-chain walk did up to 12 per session).
//   - pidValueCache: cwd and start-time are immutable for a process's lifetime,
//     so memoize them per pid (a long TTL guards against pid reuse).
// Linux paths read /proc directly (no subprocess) and are left untouched.
const PPID_TTL_MS = 1000;
let ppidSnap: { at: number; map: Map<number, number> } | null = null;
function ppidMap(): Map<number, number> {
  const now = Date.now();
  if (ppidSnap && now - ppidSnap.at < PPID_TTL_MS) return ppidSnap.map;
  const map = new Map<number, number>();
  const out = spawnText(["ps", "-axo", "pid=,ppid="]);
  if (out) {
    for (const line of out.split("\n")) {
      const m = line.match(/^\s*(\d+)\s+(\d+)/);
      if (m) map.set(Number(m[1]), Number(m[2]));
    }
  }
  ppidSnap = { at: now, map };
  return map;
}

const PID_VALUE_TTL_MS = 30_000;
const cwdCache = new Map<number, { at: number; val: string | null }>();
const startCache = new Map<number, { at: number; val: number | null }>();
function cachedPid<T>(
  store: Map<number, { at: number; val: T }>,
  pid: number,
  compute: () => T,
): T {
  const now = Date.now();
  const hit = store.get(pid);
  if (hit && now - hit.at < PID_VALUE_TTL_MS) return hit.val;
  const val = compute();
  store.set(pid, { at: now, val });
  return val;
}

// Processes whose command line contains `nameFilter`, with the FULL command
// line. Mirrors the include logic the old listClaudeProcs/listCodexProcs used:
// keep only procs whose argv[0] basename === nameFilter (so editors/greps that
// merely *mention* the name are excluded). Callers apply their own extra
// filters (e.g. dropping `app-server`) on top, exactly as before.
export function listProcs(nameFilter: string): { pid: number; cmd: string }[] {
  if (IS_DARWIN) {
    // `ps -axo pid=,command=` → "<pid> <full argv>" per line. No `=`-less
    // headers because of the trailing `=` on each column.
    const out = spawnText(["ps", "-axo", "pid=,command="]);
    if (!out) return [];
    const procs: { pid: number; cmd: string }[] = [];
    for (const line of out.split("\n")) {
      const m = line.match(/^\s*(\d+)\s+(.*)$/);
      if (!m) continue;
      const pid = Number(m[1]);
      const cmd = m[2].trim();
      if (!cmd.includes(nameFilter)) continue;
      const first = cmd.split(/\s+/)[0] ?? "";
      // Same gate as the Linux path: argv[0] must actually BE the tool.
      if (basename(first) !== nameFilter) continue;
      procs.push({ pid, cmd });
    }
    return procs;
  }
  // Linux: byte-for-byte the original `pgrep -af` path.
  const out = spawnText(["pgrep", "-af", nameFilter]);
  if (!out) return [];
  const procs: { pid: number; cmd: string }[] = [];
  for (const line of out.split("\n")) {
    const m = line.match(/^(\d+)\s+(.*)$/);
    if (!m) continue;
    const pid = Number(m[1]);
    const cmd = m[2].trim();
    const first = cmd.split(/\s+/)[0] ?? "";
    if (basename(first) !== nameFilter) continue;
    procs.push({ pid, cmd });
  }
  return procs;
}

// Absolute cwd of a pid, or null.
export async function cwdOf(pid: number): Promise<string | null> {
  if (IS_DARWIN) {
    // cwd is fixed for a process's lifetime → cache per pid (lsof is the single
    // most expensive call in the enrichment storm, ~30–80ms each).
    return cachedPid(cwdCache, pid, () => {
      // `lsof -a -p <pid> -d cwd -Fn` emits field lines; the `n`-prefixed one is
      // the cwd path. (There's also a `p<pid>` and `fcwd` line.)
      const out = spawnText(["lsof", "-a", "-p", String(pid), "-d", "cwd", "-Fn"]);
      if (!out) return null;
      for (const line of out.split("\n")) {
        if (line.startsWith("n")) return line.slice(1).trim() || null;
      }
      return null;
    });
  }
  try {
    return await readlink(`/proc/${pid}/cwd`);
  } catch {
    return null;
  }
}

// Process start time as ms-epoch. On Linux this was statSync('/proc/<pid>')
// .ctimeMs (the inode ctime of the proc dir == process start). On Darwin we
// parse `ps -o lstart=` (a human date string) into ms. Both give a value that
// orders processes by age the same way, which is all the heuristics need.
export function startTimeMsOf(pid: number): number | null {
  if (IS_DARWIN) {
    // Start time is immutable per pid → cache (avoids a `ps` spawn per pass).
    return cachedPid(startCache, pid, () => {
      const out = spawnText(["ps", "-o", "lstart=", "-p", String(pid)]);
      if (!out) return null;
      const s = out.trim();
      if (!s) return null;
      const t = Date.parse(s);
      return Number.isFinite(t) ? t : null;
    });
  }
  try {
    return statSync(`/proc/${pid}`).ctimeMs;
  } catch {
    return null;
  }
}

// Decide whether a live pid's start time matches the `procStart` value claude
// stamped into its pidfile — the guard that rejects a recycled pid's leftover
// json. Returns true when they agree (or when we can't tell, to avoid dropping
// a valid session).
//
// The two platforms encode "process start" differently, AND claude itself uses
// a different encoding than the OS introspection:
//   - Linux: claude stores /proc/<pid>/stat field 22 (starttime, clock ticks),
//     which equals what we read back — so a literal string compare is correct.
//   - Darwin: claude stores `lstart` but in UTC ("Sat Jun 27 17:16:08 2026"),
//     while `ps -o lstart=` prints LOCAL time ("Sun Jun 28 01:16:08 2026"). A
//     literal compare always fails, so we parse both to ms-epoch and allow a
//     small skew. Date.parse on the UTC string is interpreted as local, so we
//     compare both interpretations and accept if either lands within tolerance.
export function procStartMatches(pid: number, procStart: string): boolean {
  if (IS_DARWIN) {
    // Reuse the cached start time instead of spawning a fresh `ps -o lstart=`
    // per pid on every list pass — startTimeMsOf() already memoizes exactly this
    // (Date.parse of the pid's lstart). readPidSession() calls this for every
    // claude proc each scan, so the redundant spawn was a top contributor to the
    // synchronous spawn storm that overflows Bun.spawnSync's stack.
    const liveMs = startTimeMsOf(pid);
    if (liveMs == null) return true; // can't read it — don't reject
    const storedMs = Date.parse(procStart);
    if (!Number.isFinite(liveMs) || !Number.isFinite(storedMs)) return true;
    // Same wall-clock instant: live(local) === stored(UTC). Date.parse treats
    // the tz-less stored string as LOCAL, so it reads storedMs as the same local
    // clock reading shifted by the local offset. Accept when the two match
    // modulo the local UTC offset (any whole-hour shift) within a 2s skew.
    const offsetMs = new Date().getTimezoneOffset() * 60_000; // local→UTC, ms
    const candidates = [storedMs, storedMs - offsetMs, storedMs + offsetMs];
    return candidates.some((c) => Math.abs(c - liveMs) < 2_000);
  }
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    // comm (field 2) may hold spaces/parens, so index off the last ')'.
    const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    const token = fields[19];
    if (!token) return true;
    return token === procStart;
  } catch {
    return true;
  }
}

// Parent pid of a pid, or null.
export function ppidOf(pid: number): number | null {
  if (IS_DARWIN) {
    // Batched snapshot lookup — see ppidMap(). Replaces a per-pid `ps` spawn.
    const ppid = ppidMap().get(pid);
    return ppid != null && Number.isFinite(ppid) ? ppid : null;
  }
  try {
    // /proc/<pid>/stat: "pid (comm) state ppid ..." — split after the last ')'.
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const after = stat.slice(stat.lastIndexOf(")") + 2);
    const fields = after.split(" ");
    const ppid = Number(fields[1]);
    return Number.isFinite(ppid) ? ppid : null;
  } catch {
    return null;
  }
}

// comm (executable name) of a pid, or null. Linux reads /proc/<pid>/stat field
// 2 (the parenthesized comm, basename only). Darwin uses `ps -o comm=` (which
// yields the full path) and basename-normalizes it to match Linux semantics.
export function commOf(pid: number): string | null {
  if (IS_DARWIN) {
    const out = spawnText(["ps", "-o", "comm=", "-p", String(pid)]);
    if (!out) return null;
    const s = out.trim();
    return s ? basename(s) : null;
  }
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
    const l = stat.indexOf("(");
    const r = stat.lastIndexOf(")");
    if (l < 0 || r < 0 || r <= l) return null;
    return stat.slice(l + 1, r);
  } catch {
    return null;
  }
}
