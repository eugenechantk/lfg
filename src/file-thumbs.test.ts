import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, stat, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { deflateSync } from "node:zlib";
import {
  isRenditionCandidate,
  renditionFor,
  renditionKey,
  renditionWidth,
  _renditionsInFlight,
} from "./file-thumbs.ts";

// ---- a tiny PNG encoder so the fixture needs no binary checked in ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length);
  const dv = new DataView(out.buffer);
  dv.setUint32(0, data.length);
  out.set(new TextEncoder().encode(type), 4);
  out.set(data, 8);
  dv.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}
function solidPNG(width: number, height: number, rgb: [number, number, number]): Uint8Array {
  const raw = new Uint8Array((1 + width * 3) * height);
  for (let y = 0; y < height; y++) {
    const row = y * (1 + width * 3);
    raw[row] = 0; // filter: none
    for (let x = 0; x < width; x++) raw.set(rgb, row + 1 + x * 3);
  }
  const ihdr = new Uint8Array(13);
  const dv = new DataView(ihdr.buffer);
  dv.setUint32(0, width);
  dv.setUint32(4, height);
  ihdr.set([8, 2, 0, 0, 0], 8); // 8-bit RGB
  const parts = [
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", new Uint8Array(deflateSync(raw))), // zlib stream, not raw DEFLATE
    chunk("IEND", new Uint8Array(0)),
  ];
  const total = parts.reduce((n, p) => n + p.length, 0);
  const png = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    png.set(p, off);
    off += p.length;
  }
  return png;
}

async function pixelWidth(path: string): Promise<number> {
  const proc = Bun.spawn(["sips", "-g", "pixelWidth", path], { stdout: "pipe" });
  const text = await new Response(proc.stdout).text();
  await proc.exited;
  return Number(/pixelWidth:\s*(\d+)/.exec(text)?.[1]);
}

const darwin = process.platform === "darwin";
let dir: string;
let png: string;
let cacheDir: string;

beforeAll(async () => {
  dir = await mkdtemp(join(tmpdir(), "lfg-thumbs-"));
  cacheDir = join(dir, "cache");
  png = join(dir, "shot.png");
  await writeFile(png, solidPNG(1600, 900, [200, 40, 40]));
});
afterAll(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("renditionWidth — bucketed so the cache stays bounded", () => {
  test("rounds up to the nearest bucket", () => {
    expect(renditionWidth("100")).toBe(480);
    expect(renditionWidth("480")).toBe(480);
    expect(renditionWidth("481")).toBe(1200);
    expect(renditionWidth("1200")).toBe(1200);
    expect(renditionWidth("1201")).toBe(2400);
    expect(renditionWidth("99999")).toBe(2400);
  });
  test("absent or invalid → null (serve the original)", () => {
    expect(renditionWidth(null)).toBeNull();
    expect(renditionWidth("")).toBeNull();
    expect(renditionWidth("abc")).toBeNull();
    expect(renditionWidth("0")).toBeNull();
    expect(renditionWidth("-5")).toBeNull();
  });
});

describe("isRenditionCandidate", () => {
  test("raster images only", () => {
    expect(isRenditionCandidate("/a/b.PNG")).toBe(true);
    expect(isRenditionCandidate("/a/b.jpeg")).toBe(true);
    expect(isRenditionCandidate("/a/b.heic")).toBe(true);
    expect(isRenditionCandidate("/a/b.mov")).toBe(false);
    expect(isRenditionCandidate("/a/b.pdf")).toBe(false);
    expect(isRenditionCandidate("/a/b.svg")).toBe(false);
    expect(isRenditionCandidate("/a/b")).toBe(false);
  });
});

describe("renditionKey", () => {
  test("changes with path, mtime, size and width", () => {
    const base = renditionKey("/a.png", 1000, 10, 1200);
    expect(renditionKey("/a.png", 1000, 10, 1200)).toBe(base);
    expect(renditionKey("/b.png", 1000, 10, 1200)).not.toBe(base);
    expect(renditionKey("/a.png", 2000, 10, 1200)).not.toBe(base);
    expect(renditionKey("/a.png", 1000, 11, 1200)).not.toBe(base);
    expect(renditionKey("/a.png", 1000, 10, 480)).not.toBe(base);
  });
});

describe("renditionFor", () => {
  test("non-darwin → null", async () => {
    expect(await renditionFor(png, 1200, { platform: "linux", cacheDir })).toBeNull();
  });

  test("non-image → null", async () => {
    const mov = join(dir, "clip.mov");
    await writeFile(mov, "not really a movie");
    expect(await renditionFor(mov, 1200, { cacheDir })).toBeNull();
  });

  test("missing file → null", async () => {
    expect(await renditionFor(join(dir, "nope.png"), 1200, { cacheDir })).toBeNull();
  });

  test.if(darwin)("produces a JPEG no wider than the bucket, then serves it from cache", async () => {
    const first = await renditionFor(png, 1200, { cacheDir });
    expect(first).not.toBeNull();
    expect(first!.type).toBe("image/jpeg");
    expect(first!.etag).toMatch(/^"[0-9a-f]{40}"$/);
    const bytes = await readFile(first!.path);
    expect(Array.from(bytes.subarray(0, 3))).toEqual([0xff, 0xd8, 0xff]); // JPEG SOI
    expect(await pixelWidth(first!.path)).toBe(1200);
    expect((await stat(first!.path)).size).toBeLessThan((await stat(png)).size);

    const before = (await stat(first!.path)).mtimeMs;
    const second = await renditionFor(png, 1200, { cacheDir, sips: "/usr/bin/false" }); // would fail if re-run
    expect(second).toEqual(first);
    expect((await stat(first!.path)).mtimeMs).toBe(before);
  });

  test.if(darwin)("never upscales a source smaller than the bucket (sips -Z would)", async () => {
    const small = join(dir, "small.png");
    await writeFile(small, solidPNG(300, 200, [0, 120, 0]));
    const r = await renditionFor(small, 1200, { cacheDir });
    expect(r).not.toBeNull();
    expect(await pixelWidth(r!.path)).toBe(300);
  });

  test.if(darwin)("a rewritten source (new mtime) gets a new rendition and ETag", async () => {
    const first = await renditionFor(png, 480, { cacheDir });
    const later = new Date(Date.now() + 5000);
    await utimes(png, later, later);
    const second = await renditionFor(png, 480, { cacheDir });
    expect(second!.etag).not.toBe(first!.etag);
    expect(second!.path).not.toBe(first!.path);
    expect(await pixelWidth(second!.path)).toBe(480);
  });

  test.if(darwin)("sips failure → null and no partial file left behind", async () => {
    const other = join(dir, "other.png");
    await writeFile(other, solidPNG(64, 64, [0, 0, 255]));
    expect(await renditionFor(other, 1200, { cacheDir, sips: "/usr/bin/false" })).toBeNull();
    let leftovers = 0;
    for await (const _ of new Bun.Glob("*.tmp.jpg").scan({ cwd: cacheDir })) leftovers++;
    expect(leftovers).toBe(0);
  });

  test.if(darwin)("concurrent requests for one key share a single sips run; total runs are capped", async () => {
    // A stand-in sips that records each invocation and takes a moment, so the
    // in-flight map and the concurrency cap are both observable.
    const counter = join(dir, "runs.log");
    const fake = join(dir, "fake-sips.sh");
    // Only the conversion (-Z) counts as a run; the size probe (-g) is cheap.
    await writeFile(
      fake,
      `#!/bin/sh\ncase "$1" in -Z) echo run >> "${counter}"; sleep 0.3;; esac\nexec /usr/bin/sips "$@"\n`,
      { mode: 0o755 },
    );
    const files = await Promise.all(
      [1, 2, 3, 4].map(async (i) => {
        const p = join(dir, `many-${i}.png`);
        await writeFile(p, solidPNG(300, 200, [i * 40, 0, 0]));
        return p;
      }),
    );
    const results = await Promise.all([
      ...files.map((p) => renditionFor(p, 480, { cacheDir, sips: fake })),
      renditionFor(files[0], 480, { cacheDir, sips: fake }), // duplicate key → shared
      renditionFor(files[0], 480, { cacheDir, sips: fake }),
    ]);
    expect(results.every((r) => r !== null)).toBe(true);
    const runs = (await readFile(counter, "utf8")).trim().split("\n").length;
    expect(runs).toBe(4); // one per distinct key, none for the duplicates
    expect(_renditionsInFlight()).toBe(0);
  });
});
