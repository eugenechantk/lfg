// Server-side port of the clients' hidden-directory matcher
// (ios/LFGCore/Sources/LFGCore/HiddenDirs.swift). The two must agree: clients
// send their hidden set as `exclude` params on /api/sessions/resumable so
// filtering happens BEFORE pagination — filtering after paging starves the list
// when a churny population (gbrain autopilot) floods the newest-mtime window.
// Clients still filter locally as a backstop, so a divergence here shows up as
// starved pages, not as leaked rows.

/** An entry containing `*` or `?` is a pattern rather than a literal directory. */
export function isHiddenDirPattern(s: string): boolean {
  return s.includes("*") || s.includes("?");
}

/**
 * Trim and collapse repeated/trailing slashes. An entry must be an absolute
 * path or a wildcard pattern; `~` cannot be expanded against this host reliably
 * from a client's point of view, and `/` or bare wildcards would hide
 * everything, so all three are rejected — same rules as the Swift normalize.
 */
export function normalizeHiddenDir(path: string): string | null {
  const trimmed = path.trim();
  if (!trimmed.startsWith("/") && !isHiddenDirPattern(trimmed)) return null;
  if (trimmed.startsWith("~")) return null;
  const leadingSlash = trimmed.startsWith("/");
  const body = trimmed.split("/").filter(Boolean).join("/");
  if (!body) return null;
  const joined = leadingSlash ? "/" + body : body;
  if (![...joined].some((c) => c !== "*" && c !== "?" && c !== "/")) return null;
  return joined;
}

/**
 * Glob match: `*` matches any run of characters (including `/`), `?` exactly
 * one. Iterative with backtracking, mirroring `HiddenDirs.glob`.
 */
export function globMatches(pattern: string, text: string): boolean {
  const p = pattern;
  const t = text;
  let pi = 0;
  let ti = 0;
  let starP = -1;
  let starT = 0;
  while (ti < t.length) {
    if (pi < p.length && p[pi] === "*") {
      starP = pi;
      starT = ti;
      pi += 1;
    } else if (pi < p.length && (p[pi] === "?" || p[pi] === t[ti])) {
      pi += 1;
      ti += 1;
    } else if (starP >= 0) {
      pi = starP + 1;
      starT += 1;
      ti = starT;
    } else {
      return false;
    }
  }
  while (pi < p.length && p[pi] === "*") pi += 1;
  return pi === p.length;
}

/**
 * Whether a session in `cwd` is hidden by `patterns`.
 *
 * No cwd → never hidden (hiding asserts something about a directory). Literal
 * entries match on path-segment boundaries so `.gbrain` cannot swallow
 * `.gbrainstorm`; pattern entries match the cwd or any ancestor, so
 * `*\/gbrain-claude-cli-cwd-*` also covers that directory's children.
 * Case-insensitive throughout — the hosts run case-insensitive filesystems.
 */
export function hidesCwd(cwd: string | null | undefined, patterns: string[]): boolean {
  if (!cwd) return false;
  const dir = normalizeHiddenDir(cwd)?.toLowerCase();
  if (!dir) return false;
  return patterns.some((raw) => {
    const hidden = normalizeHiddenDir(raw)?.toLowerCase();
    if (!hidden) return false;
    if (!isHiddenDirPattern(hidden)) {
      return dir === hidden || dir.startsWith(hidden + "/");
    }
    let candidate = dir;
    for (;;) {
      if (globMatches(hidden, candidate)) return true;
      const slash = candidate.lastIndexOf("/");
      if (slash <= 0) return false;
      candidate = candidate.slice(0, slash);
    }
  });
}

/** Sanitize a client-supplied exclude list down to usable entries. */
export function normalizeExcludes(raw: string[] | undefined | null): string[] {
  if (!raw) return [];
  const out: string[] = [];
  for (const r of raw) {
    const n = normalizeHiddenDir(r);
    if (n != null) out.push(n);
  }
  return out;
}
