// Which files the remote MCP server (src/mcp-server.ts) may read (read_file) or
// hand out as download links (download_file).
//
// The caller is an assistant on someone else's servers (Grok Bot runs from
// Cursor's backend), so both are limited to **files a session itself
// mentioned** — paths that appear in its transcript (replies, tool calls) — and
// even those must not pass through a hidden folder or look like a secret. lfg's
// own `/api/file` serves all of $HOME to authenticated clients; this is
// deliberately much narrower than that.
//
// `checkPath` + `defaultRoots` remain for one non-read use: limiting the folders
// `start_session` may start a session in.

import { realpathSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, isAbsolute, join, relative, sep } from "node:path";

/** Dot-directories that hold agents' working docs rather than credentials. */
const DOT_DIR_ALLOW = new Set([".claude", ".codex", ".agents", ".github", ".worktrees", ".vscode"]);

/** File names that are, or usually contain, credentials. Case-insensitive. */
const SECRET_NAME = [
  /^\.env(\..*)?$/,
  /\.env$/,
  /^\.(netrc|npmrc|pypirc|git-credentials)$/,
  /\.(pem|key|p12|p8|pfx|keystore|jks|mobileprovision|keychain|keychain-db|kdbx)$/,
  /^id_(rsa|dsa|ecdsa|ed25519)/,
  /\.private\./,
  /service[-_]?account/,
  /^auth\.json$/,
  /\.(sqlite|sqlite3|db)$/,
];

/**
 * Words that mark a secrets file (`Secrets.xcconfig`, `credentials.json`) but also
 * appear in ordinary source (`ForgotPasswordView.swift`), so source files are exempt.
 * Matched as whole words of the name — `company_secretary_form.pdf` is a form, not
 * a secret.
 */
const SECRET_WORDS = new Set([
  "secret", "secrets", "credential", "credentials", "creds", "password", "passwords", "passwd",
  "token", "tokens", "cookie", "cookies",
]);

/** `ForgotPasswordView.swift` → forgot, password, view, swift. */
function nameWords(name: string): string[] {
  return name
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}
const SOURCE_EXT = /\.(swift|m|mm|h|c|cc|cpp|ts|tsx|js|jsx|mjs|py|rb|go|rs|kt|java|cs|php|vue|svelte|css|scss|html|md|mdx)$/;

export type PathCheck = { ok: true; path: string } | { ok: false; reason: string };

export function expandHome(p: string, home = homedir()): string {
  if (p === "~") return home;
  if (p.startsWith("~/")) return join(home, p.slice(2));
  return p;
}

/** Default roots: where projects and agent outputs live. Never $HOME itself. */
export function defaultRoots(home = homedir()): string[] {
  return ["dev", "inbox", "Desktop", "Downloads", "Documents"].map((d) => join(home, d));
}

function realOrNull(p: string): string | null {
  try {
    return realpathSync(p);
  } catch {
    return null;
  }
}

export function looksSecret(name: string): boolean {
  const n = name.toLowerCase();
  if (SECRET_NAME.some((re) => re.test(n))) return true;
  return !SOURCE_EXT.test(n) && nameWords(name).some((w) => SECRET_WORDS.has(w));
}

/** A dot-directory segment that is not one of the agent-doc folders. */
function hiddenDirIn(segments: string[]): string | undefined {
  return segments.find((seg) => seg.startsWith(".") && seg !== "." && seg !== ".." && !DOT_DIR_ALLOW.has(seg));
}

/**
 * May the remote assistant read `input` as one of this session's files?
 * `mentioned` is every path the session's transcript names (from
 * `mentionedPaths`). Both sides are resolved, so `~/x`, `/Users/me/x` and a
 * symlink to it are the same file, and a symlink cannot smuggle in a file the
 * session never named.
 */
export function checkSessionFile(input: string, mentioned: Iterable<string>, home = homedir()): PathCheck {
  const expanded = expandHome(input.trim(), home);
  if (!isAbsolute(expanded)) return { ok: false, reason: "path must be absolute (or start with ~/)" };
  const real = realOrNull(expanded);
  if (!real) return { ok: false, reason: "no such file" };
  let isFile = false;
  try {
    isFile = statSync(real).isFile();
  } catch {}
  if (!isFile) return { ok: false, reason: "not a file" };
  const named = new Set<string>();
  for (const m of mentioned) {
    const r = realOrNull(expandHome(m, home));
    if (r) named.add(r);
  }
  if (!named.has(real)) return { ok: false, reason: "this session never mentioned that file; only files in the session can be read (see list_session_files)" };
  // A hidden folder directly in $HOME (~/.claude, ~/.codex, ~/.ssh) is tool config
  // and credentials, never project docs — the allowlist only applies deeper down.
  const fromHome = relative(home, real).split(sep);
  if (fromHome[0] !== ".." && fromHome[0]?.startsWith(".")) return { ok: false, reason: `inside a hidden folder (~/${fromHome[0]}) this connector does not read` };
  const segs = real.split(sep).filter(Boolean).slice(0, -1);
  const hidden = hiddenDirIn(segs);
  if (hidden) return { ok: false, reason: `inside a hidden folder (${hidden}) this connector does not read` };
  if (looksSecret(basename(real))) return { ok: false, reason: "looks like a secrets or credentials file" };
  return { ok: true, path: real };
}

/**
 * Resolve `input` and decide whether it may be read or listed. `roots` are
 * resolved too, so a symlinked root (or a symlink inside one) is judged by
 * where it really points.
 */
export function checkPath(input: string, roots: string[], home = homedir()): PathCheck {
  const expanded = expandHome(input.trim(), home);
  if (!isAbsolute(expanded)) return { ok: false, reason: "path must be absolute (or start with ~/)" };
  const real = realOrNull(expanded);
  if (!real) return { ok: false, reason: "no such file or directory" };
  const realRoots = roots.map(realOrNull).filter((r): r is string => !!r);
  const root = realRoots.find((r) => real === r || real.startsWith(r + sep));
  if (!root) return { ok: false, reason: "outside the folders this connector may read (~/dev, ~/inbox, Desktop, Downloads, Documents, or the session's folder)" };
  const segs = relative(root, real).split(sep).filter(Boolean);
  let isDir = false;
  try {
    isDir = statSync(real).isDirectory();
  } catch {}
  const dirSegs = isDir ? segs : segs.slice(0, -1);
  const blockedDir = hiddenDirIn(dirSegs);
  if (blockedDir) return { ok: false, reason: `inside a hidden folder (${blockedDir}) this connector does not read` };
  if (!isDir && looksSecret(basename(real))) return { ok: false, reason: "looks like a secrets or credentials file" };
  return { ok: true, path: real };
}

const IMAGE_TYPES: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
};

export function imageMimeType(path: string): string | null {
  const ext = path.toLowerCase().split(".").pop() ?? "";
  return IMAGE_TYPES[ext] ?? null;
}

/** Text if the first 8 KB has no NUL byte and decodes as UTF-8. */
export function isProbablyText(bytes: Uint8Array): boolean {
  const head = bytes.subarray(0, 8192);
  if (head.includes(0)) return false;
  try {
    new TextDecoder("utf-8", { fatal: true }).decode(head.length < bytes.length ? head.subarray(0, lastCharBoundary(head)) : head);
    return true;
  } catch {
    return false;
  }
}

/** Don't fail UTF-8 validation on a multi-byte character cut by the 8 KB window. */
function lastCharBoundary(b: Uint8Array): number {
  let i = b.length;
  for (let k = 0; k < 4 && i > 0; k++) {
    const byte = b[i - 1]!;
    if ((byte & 0xc0) !== 0x80) return (byte & 0x80) === 0 ? i : i - 1;
    i--;
  }
  return b.length;
}

/** Where sessions put files besides the home folder: scratch and temp dirs. */
const TEMP_PREFIXES = ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"];

/**
 * File paths mentioned in free text (agent replies, tool calls): under the home
 * folder (absolute or `~/`) or in a temp folder. Other absolute-looking strings
 * are skipped, so URL paths like `/api/sessions` never count.
 */
export function mentionedPaths(text: string, home = homedir()): string[] {
  const out: string[] = [];
  const esc = (p: string) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const prefixes = [`${esc(home)}/`, "~/", ...TEMP_PREFIXES.map(esc)].join("|");
  const re = new RegExp(`(?:^|[\\s\`'"(\\[<{:=])((?:${prefixes})[^\\s\`'"<>)\\]}\\\\,]+)`, "g");
  for (const m of text.matchAll(re)) {
    const p = m[1]!.replace(/[.:;!?]+$/, "");
    if (p.length > 3) out.push(p);
  }
  return out;
}
