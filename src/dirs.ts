// Working-directory management for new sessions: the scanned repos plus two
// always-available fallbacks — the repos ROOT itself and a configurable INBOX
// (a scratch folder for ad-hoc work) — and a way to create new directories.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { PATHS } from "./config.ts";

const REPOS_ROOT = process.env.LFG_REPOS_ROOT ?? join(homedir(), "repos");
const CONFIG = join(PATHS.data, "dirs.json");

type DirsConfig = { inbox?: string };

function readCfg(): DirsConfig {
  try {
    return JSON.parse(readFileSync(CONFIG, "utf8")) as DirsConfig;
  } catch {
    return {};
  }
}

function writeCfg(c: DirsConfig): void {
  mkdirSync(PATHS.data, { recursive: true });
  writeFileSync(CONFIG, JSON.stringify(c, null, 2));
}

export function rootDir(): string {
  return REPOS_ROOT;
}

/**
 * Normalize a directory path typed by a human (the iOS "Add directory by path…"
 * field, the inbox setting) into something `statSync` can actually resolve.
 *
 * Only `~` expansion and trailing-separator cleanup — deliberately NOT
 * `resolve()`, which would silently anchor a relative path like `dev/inbox` to
 * whatever directory the server happens to be running in. A relative path comes
 * back unchanged so the caller's existence check rejects it.
 *
 * `~` is a SHELL feature: nothing expands it on the way through JSON → fetch →
 * `statSync`, so a perfectly good `~/dev/inbox` used to 400 as "directory not
 * found". That was the whole bug.
 */
export function expandUserPath(input: string): string {
  const p = input.trim();
  if (!p) return p;
  let out = p;
  if (out === "~") out = homedir();
  else if (out.startsWith("~/")) out = join(homedir(), out.slice(2));
  // Drop trailing separators so the stored/echoed path is canonical. Keep a
  // bare "/" intact.
  while (out.length > 1 && out.endsWith("/")) out = out.slice(0, -1);
  return out;
}

/** The inbox/scratch directory (auto-created). Defaults to <root>/_inbox. */
export function inboxDir(): string {
  const dir = readCfg().inbox || join(REPOS_ROOT, "_inbox");
  try {
    mkdirSync(dir, { recursive: true });
  } catch {}
  return dir;
}

export function setInbox(path: string): string {
  const dir = expandUserPath(path) || join(REPOS_ROOT, "_inbox");
  writeCfg({ ...readCfg(), inbox: dir });
  try {
    mkdirSync(dir, { recursive: true });
  } catch {}
  return dir;
}

/** Create a new directory under the repos root. Returns its name + absolute cwd. */
export function createDir(name: string): { name: string; cwd: string } | null {
  const safe = name.replace(/[^a-zA-Z0-9 ._-]/g, "").trim();
  if (!safe) return null;
  const cwd = join(REPOS_ROOT, safe);
  mkdirSync(cwd, { recursive: true });
  return { name: safe, cwd };
}
