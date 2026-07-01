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

// Non-blocking counterpart to spawnText. Used by the prime* helpers so the two
// heavy per-scan spawns (the ps snapshot and the batched lsof) run off the event
// loop — a cold scan under a concurrent request pile-up otherwise blocks all HTTP
// for the child's lifetime. Same null-on-failure contract.
async function spawnTextAsync(cmd: string[]): Promise<string | null> {
  try {
    const proc = Bun.spawn(cmd, { stdout: "pipe", stderr: "ignore" });
    const text = await new Response(proc.stdout).text();
    const code = await proc.exited;
    if (code !== 0 && !text) return null;
    return text;
  } catch {
    return null;
  }
}

// macOS perf shim. listSessions() enriches dozens of procs and each Darwin
// helper here shells out to `ps`/`lsof` synchronously — and Bun.spawnSync
// blocks the single event loop AND, at a deep reentrant stack, throws a
// `RangeError: Maximum call stack size exceeded` that even escapes the try/catch
// in spawnText (and occasionally segfaults). The cure is to spawn FEWER, LARGER
// commands: one `ps` snapshot of every proc, one batched `lsof` for the cwds of
// all candidate pids. The per-pid accessors below then read from these instead
// of spawning once each — collapsing a ~26-spawn-per-scan storm to ~2.
// Linux paths read /proc directly (no subprocess) and are left untouched.

// ONE `ps -axo pid=,ppid=,lstart=,command=` snapshot of every process: pid →
// {ppid, startMs, cmd}. lstart is the last-but-one column (fixed token shape
// "Dow Mon DD HH:MM:SS YYYY"); command is the free-form remainder. Replaces the
// old per-pid `ps -o ppid=` / `ps -o lstart=` spawns and the separate ppidMap.
const PROC_SNAP_TTL_MS = 600;
interface ProcRow {
  ppid: number;
  startMs: number | null;
  cmd: string;
}
let procSnap: { at: number; rows: Map<number, ProcRow> } | null = null;
const LSTART = /^\s*(\d+)\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(.*)$/;
function parsePsRows(out: string | null): Map<number, ProcRow> {
  const rows = new Map<number, ProcRow>();
  if (out) {
    for (const line of out.split("\n")) {
      const m = line.match(LSTART);
      if (!m) continue;
      const startMs = Date.parse(m[3]);
      rows.set(Number(m[1]), {
        ppid: Number(m[2]),
        startMs: Number.isFinite(startMs) ? startMs : null,
        cmd: m[4].trim(),
      });
    }
  }
  return rows;
}

// Synchronous read of the ps snapshot. On the session-scan path it's a pure
// cache read — primeProcSnapshot() (async, non-blocking) refreshes the cache up
// front. The sync spawn here is only a cold-cache fallback for the rare non-scan
// caller that reads a pid's ppid/start/comm outside a primed scan.
function psSnapshot(): Map<number, ProcRow> {
  const now = Date.now();
  if (procSnap && now - procSnap.at < PROC_SNAP_TTL_MS) return procSnap.rows;
  const rows = parsePsRows(spawnText(["ps", "-axo", "pid=,ppid=,lstart=,command="]));
  procSnap = { at: now, rows };
  return rows;
}

// Refresh the ps snapshot with a NON-BLOCKING spawn. Call this (awaited) at the
// top of a session scan before anything reads psSnapshot(), so the one ps that
// feeds ppidOf/startTimeMsOf/commOf/listProcs runs off the event loop instead of
// freezing all HTTP for its duration. psSnapshot() then just reads the cache.
export async function primeProcSnapshot(): Promise<void> {
  if (!IS_DARWIN) return;
  const now = Date.now();
  if (procSnap && now - procSnap.at < PROC_SNAP_TTL_MS) return;
  const rows = parsePsRows(
    await spawnTextAsync(["ps", "-axo", "pid=,ppid=,lstart=,command="]),
  );
  procSnap = { at: Date.now(), rows };
}

// Batch-prime the cwd cache for many pids with ONE `lsof -a -p p1,p2,… -d cwd
// -Fn` (output is a `p<pid>` block per pid, each with an `n<path>` line) instead
// of one lsof per pid. Called once at the top of a session scan; cwdOf() then
// finds every pid already cached and never spawns. Best-effort — any pid lsof
// omits just stays uncached and falls back to its own lazy spawn.
export async function primeCwds(pids: number[]): Promise<void> {
  if (!IS_DARWIN || pids.length === 0) return;
  const now = Date.now();
  const missing = pids.filter((pid) => {
    const hit = cwdCache.get(pid);
    return !(hit && now - hit.at < PID_VALUE_TTL_MS);
  });
  if (missing.length === 0) return;
  const out = await spawnTextAsync(["lsof", "-a", "-p", missing.join(","), "-d", "cwd", "-Fn"]);
  if (!out) return;
  let cur: number | null = null;
  for (const line of out.split("\n")) {
    if (line.startsWith("p")) {
      cur = Number(line.slice(1)) || null;
    } else if (line.startsWith("n") && cur != null) {
      cwdCache.set(cur, { at: now, val: line.slice(1).trim() || null });
    }
  }
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
    // Read the shared ps snapshot (one spawn, TTL-cached) rather than spawning a
    // dedicated `ps -axo pid=,command=` here — so listClaudeProcs + listCodexProcs
    // in one scan share a single ps, not two.
    const procs: { pid: number; cmd: string }[] = [];
    for (const [pid, row] of psSnapshot()) {
      const cmd = row.cmd;
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
    // Prefer the shared ps snapshot (already holds lstart for every live pid).
    // Fall back to a per-pid `ps -o lstart=` only for a pid the snapshot missed
    // (e.g. a proc that started after the snapshot's TTL window began).
    const snap = psSnapshot().get(pid);
    if (snap) return snap.startMs;
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
    // Shared ps-snapshot lookup — no per-pid spawn.
    const ppid = psSnapshot().get(pid)?.ppid;
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
    // argv[0] from the shared ps snapshot, basename-normalized to match Linux
    // comm semantics — no per-pid spawn.
    const cmd = psSnapshot().get(pid)?.cmd;
    if (!cmd) return null;
    const first = cmd.split(/\s+/)[0] ?? "";
    return first ? basename(first) : null;
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
