// Expiring download links for the MCP server's download_file tool.
//
// A link is a capability: https://<files host>/dl/<token>/<name>. Whoever holds
// it can download that one file until it expires — no login, so Grok Bot (or
// Eugene's phone) can fetch it directly. The token is 32 random bytes; only its
// SHA-256 is stored, so the store file on disk holds no live links. Links survive
// a server restart (the store is a small JSON file) and die at expiry.
//
// At download time the file must still be a regular file at the same resolved
// path, so swapping it for a symlink after the link was made gets nothing.

import { createHash, randomBytes } from "node:crypto";
import { readFileSync, realpathSync, renameSync, statSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

export type DownloadEntry = { path: string; name: string; sessionId: string; createdAt: number; expiresAt: number };

const hash = (token: string) => createHash("sha256").update(token).digest("hex");

export class DownloadStore {
  private entries = new Map<string, DownloadEntry>();

  constructor(
    private readonly file: string | null,
    private readonly now: () => number = () => Date.now(),
  ) {
    if (!file) return;
    try {
      const raw = JSON.parse(readFileSync(file, "utf8")) as Record<string, DownloadEntry>;
      for (const [k, v] of Object.entries(raw)) if (v.expiresAt > this.now()) this.entries.set(k, v);
    } catch {}
  }

  private save(): void {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify(Object.fromEntries(this.entries)), { mode: 0o600 });
    renameSync(tmp, this.file);
  }

  private prune(): void {
    const t = this.now();
    for (const [k, v] of this.entries) if (v.expiresAt <= t) this.entries.delete(k);
  }

  /** A new link token for `path` (already resolved and policy-checked by the caller). */
  create(path: string, sessionId: string, ttlMs: number): { token: string; entry: DownloadEntry } {
    this.prune();
    const token = randomBytes(32).toString("base64url");
    const entry = { path, name: basename(path), sessionId, createdAt: this.now(), expiresAt: this.now() + ttlMs };
    this.entries.set(hash(token), entry);
    this.save();
    return { token, entry };
  }

  get(token: string): DownloadEntry | null {
    const e = this.entries.get(hash(token));
    if (!e) return null;
    if (e.expiresAt <= this.now()) {
      this.entries.delete(hash(token));
      this.save();
      return null;
    }
    return e;
  }
}

/** `Content-Disposition` with a plain ASCII fallback and the exact UTF-8 name. */
export function contentDisposition(name: string, inline: boolean): string {
  const ascii = name.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  return `${inline ? "inline" : "attachment"}; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`;
}

const DL_PATH = /^\/dl\/([A-Za-z0-9_-]{43})(?:\/[^/]*)?$/;

/**
 * Serve `GET|HEAD /dl/<token>/<name>`. Returns null for any other path so the
 * caller can 404 it. `?view=1` shows the file in the browser instead of saving it.
 */
export function handleDownload(req: Request, store: DownloadStore, log: (line: string) => void = () => {}): Response | null {
  const url = new URL(req.url);
  const m = url.pathname.match(DL_PATH);
  if (!m) return null;
  const who = req.headers.get("cf-connecting-ip") ?? "local";
  const tag = m[1]!.slice(0, 6);
  if (req.method !== "GET" && req.method !== "HEAD") return new Response("method not allowed", { status: 405, headers: { allow: "GET, HEAD" } });
  const entry = store.get(m[1]!);
  if (!entry) {
    log(`download ${tag}… from ${who} → 404 (unknown or expired)`);
    return new Response("This link has expired or does not exist.\n", { status: 404 });
  }
  let real: string | null = null;
  let size = 0;
  try {
    real = realpathSync(entry.path);
    const st = statSync(real);
    if (!st.isFile()) real = null;
    size = st.size;
  } catch {}
  if (real !== entry.path) {
    log(`download ${tag}… ${entry.name} from ${who} → 410 (file moved or replaced)`);
    return new Response("The file behind this link is gone.\n", { status: 410 });
  }
  log(`download ${tag}… ${entry.name} (${size} B) from ${who} ${req.method}`);
  const file = Bun.file(entry.path);
  return new Response(req.method === "HEAD" ? null : file, {
    headers: {
      "content-type": file.type || "application/octet-stream",
      "content-length": String(size),
      "content-disposition": contentDisposition(entry.name, url.searchParams.get("view") === "1"),
      "cache-control": "private, no-store",
      "referrer-policy": "no-referrer",
      "x-robots-tag": "noindex, nofollow",
      "x-content-type-options": "nosniff",
      // An HTML or SVG file opened with ?view=1 must not run scripts.
      "content-security-policy": "sandbox",
    },
  });
}
