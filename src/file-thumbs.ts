// Downscaled JPEG renditions of host images for `GET /api/file?path=…&w=N`.
//
// Why: the phone reaches the host through the Cloudflare tunnel, and when that
// path is slow (Surfshark in the loop → ~400 ms RTT → 50–90 KB/s per stream,
// see .claude/diagnosis-media-slow-tunnel-in-vpn-20260917.md) a p90 agent
// screenshot (418 KB PNG) is 5–8 s and a 9 MB one is minutes. A 1200 px JPEG of
// the same screenshot is 5–40× smaller and `sips` makes it in 30–100 ms.
//
// Renditions are cached as files under ~/.lfg/cache/thumbs, keyed by
// realpath+mtime+size+width, so a rewritten file gets a fresh rendition and an
// unchanged one is a stat + sendfile. Concurrent requests for the same key
// share one sips run; total sips concurrency is capped so a transcript with
// forty screenshots doesn't fork forty processes on the single-loop server.
//
// macOS only (sips). Elsewhere, and on any failure, the caller serves the
// original bytes — a rendition is an optimisation, never a dependency.
import { createHash } from "node:crypto";
import { mkdir, rename, stat, unlink } from "node:fs/promises";
import { extname, join } from "node:path";
import { PATHS } from "./config.ts";

/** Widths a client may ask for. Requests are rounded UP to the nearest bucket
 *  so the cache holds at most three renditions per source file. */
export const RENDITION_WIDTHS = [480, 1200, 2400] as const;
export type RenditionWidth = (typeof RENDITION_WIDTHS)[number];

const IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".heic", ".heif", ".tif", ".tiff", ".bmp", ".webp"]);
export const THUMB_CACHE_DIR = join(PATHS.data, "cache", "thumbs");
export const RENDITION_CACHE_CONTROL = "private, max-age=86400";
const JPEG_QUALITY = "80";
const MAX_CONCURRENT_SIPS = 2;

export interface Rendition {
  /** Absolute path of the cached JPEG. */
  path: string;
  /** Strong ETag — the cache key, so a client revalidation is a string compare. */
  etag: string;
  type: "image/jpeg";
}

export interface RenditionOptions {
  /** sips binary; tests substitute a script. */
  sips?: string;
  /** `process.platform` override for tests. */
  platform?: string;
  /** Cache directory override for tests. */
  cacheDir?: string;
}

/** Parse the `w` query param into a bucketed width, or null when absent/invalid. */
export function renditionWidth(raw: string | null | undefined): RenditionWidth | null {
  if (raw == null || raw === "") return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  for (const w of RENDITION_WIDTHS) if (n <= w) return w;
  return RENDITION_WIDTHS[RENDITION_WIDTHS.length - 1];
}

/** Only raster images get renditions; everything else is served verbatim. */
export function isRenditionCandidate(path: string): boolean {
  return IMAGE_EXTS.has(extname(path).toLowerCase());
}

export function renditionKey(real: string, mtimeMs: number, size: number, width: number): string {
  return createHash("sha1").update(`${real}|${Math.floor(mtimeMs)}|${size}|${width}`).digest("hex");
}

const inflight = new Map<string, Promise<Rendition | null>>();
let running = 0;
const waiters: Array<() => void> = [];

async function withSlot<T>(fn: () => Promise<T>): Promise<T> {
  if (running >= MAX_CONCURRENT_SIPS) await new Promise<void>((r) => waiters.push(r));
  running++;
  try {
    return await fn();
  } finally {
    running--;
    waiters.shift()?.();
  }
}

/**
 * Return a cached JPEG rendition of `real` at most `width` px wide, producing
 * it with sips on first request. Null when the platform can't (not darwin),
 * the file isn't a raster image, or sips fails — the caller falls back to the
 * original file.
 */
export async function renditionFor(
  real: string,
  width: RenditionWidth,
  opts: RenditionOptions = {},
): Promise<Rendition | null> {
  if ((opts.platform ?? process.platform) !== "darwin") return null;
  if (!isRenditionCandidate(real)) return null;
  let st;
  try {
    st = await stat(real);
  } catch {
    return null;
  }
  if (!st.isFile()) return null;
  const cacheDir = opts.cacheDir ?? THUMB_CACHE_DIR;
  const key = renditionKey(real, st.mtimeMs, st.size, width);
  const out = join(cacheDir, `${key}.jpg`);
  const hit: Rendition = { path: out, etag: `"${key}"`, type: "image/jpeg" };
  try {
    const cached = await stat(out);
    if (cached.isFile() && cached.size > 0) return hit;
  } catch {
    /* miss */
  }
  const pending = inflight.get(key);
  if (pending) return pending;
  const job = withSlot(() => produce(real, width, out, opts.sips ?? "sips"))
    .then((ok) => (ok ? hit : null))
    .finally(() => inflight.delete(key));
  inflight.set(key, job);
  return job;
}

/** Longest side of the source in px, via `sips -g`. Null when unreadable. */
async function longestSide(real: string, sips: string): Promise<number | null> {
  const proc = Bun.spawn([sips, "-g", "pixelWidth", "-g", "pixelHeight", real], { stdout: "pipe", stderr: "ignore" });
  const text = await new Response(proc.stdout).text();
  if ((await proc.exited) !== 0) return null;
  const w = Number(/pixelWidth:\s*(\d+)/.exec(text)?.[1]);
  const h = Number(/pixelHeight:\s*(\d+)/.exec(text)?.[1]);
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0) return null;
  return Math.max(w, h);
}

async function produce(real: string, width: number, out: string, sips: string): Promise<boolean> {
  const tmp = `${out}.${process.pid}.${Date.now()}.tmp.jpg`;
  try {
    await mkdir(join(out, ".."), { recursive: true });
    // `-Z` fits the longest side into the given size — and it UPSCALES a
    // smaller source, so clamp to the source's own size (still re-encoded:
    // a 400 KB PNG of UI chrome is ~70 KB as JPEG at the same pixels).
    const side = await longestSide(real, sips);
    if (side === null) throw new Error("unreadable image");
    const fit = Math.min(width, side);
    // `--out` is a fresh file so a crash mid-write can't leave a truncated
    // rendition at the cache path.
    const proc = Bun.spawn(
      [sips, "-Z", String(fit), "-s", "format", "jpeg", "-s", "formatOptions", JPEG_QUALITY, real, "--out", tmp],
      { stdout: "ignore", stderr: "ignore" },
    );
    const code = await proc.exited;
    if (code !== 0) throw new Error(`sips exited ${code}`);
    const produced = await stat(tmp);
    if (!produced.isFile() || produced.size === 0) throw new Error("sips wrote nothing");
    await rename(tmp, out);
    return true;
  } catch {
    await unlink(tmp).catch(() => {});
    return false;
  }
}

/** Test hook: number of sips runs in flight (for the concurrency-cap test). */
export function _renditionsInFlight(): number {
  return running;
}
