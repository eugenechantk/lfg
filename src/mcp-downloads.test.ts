import { test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DownloadStore, contentDisposition, handleDownload } from "./mcp-downloads.ts";

let dir: string;
beforeAll(() => {
  dir = realpathSync(mkdtempSync(join(tmpdir(), "mcp-dl-")));
  writeFileSync(join(dir, "form.pdf"), "%PDF-1.4 hello");
  writeFileSync(join(dir, "secret-elsewhere.txt"), "nope");
});
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const get = (token: string, q = "", method = "GET") => handleDownload(new Request(`http://x/dl/${token}/form.pdf${q}`, { method }), store!);
let store: DownloadStore;

test("a link serves the file with download headers; HEAD has no body", async () => {
  store = new DownloadStore(null);
  const { token } = store.create(join(dir, "form.pdf"), "s", 60_000);
  expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  const res = get(token)!;
  expect(res.status).toBe(200);
  expect(await res.text()).toBe("%PDF-1.4 hello");
  expect(res.headers.get("content-type")).toContain("application/pdf");
  expect(res.headers.get("content-length")).toBe("14");
  expect(res.headers.get("content-disposition")).toStartWith("attachment;");
  expect(res.headers.get("cache-control")).toBe("private, no-store");
  expect(res.headers.get("content-security-policy")).toBe("sandbox");
  expect(get(token, "?view=1")!.headers.get("content-disposition")).toStartWith("inline;");
  const head = get(token, "", "HEAD")!;
  expect(head.status).toBe(200);
  expect(await head.text()).toBe("");
  expect(get(token, "", "POST")!.status).toBe(405);
});

test("unknown tokens, other paths, expired links and replaced files are refused", () => {
  let t = 1000;
  store = new DownloadStore(null, () => t);
  const { token } = store.create(join(dir, "form.pdf"), "s", 60_000);
  expect(get("A".repeat(43))!.status).toBe(404);
  expect(handleDownload(new Request("http://x/mcp"), store)).toBeNull();
  expect(handleDownload(new Request(`http://x/dl/${token}/../../etc/passwd`), store)).toBeNull();
  // Swap the file for a symlink to something else: the link is dead, not redirected.
  const victim = join(dir, "swap.pdf");
  writeFileSync(victim, "x");
  const swapped = store.create(victim, "s", 60_000).token;
  unlinkSync(victim);
  symlinkSync(join(dir, "secret-elsewhere.txt"), victim);
  expect(get(swapped)!.status).toBe(410);
  t += 60_001;
  expect(get(token)!.status).toBe(404);
});

test("links survive a restart, and the store file holds hashes, not tokens", () => {
  const file = join(dir, "store.json");
  const a = new DownloadStore(file);
  const { token } = a.create(join(dir, "form.pdf"), "s", 60_000);
  const raw = readFileSync(file, "utf8");
  expect(raw).not.toContain(token);
  expect((statSync(file).mode & 0o777).toString(8)).toBe("600");
  const b = new DownloadStore(file);
  expect(b.get(token)?.name).toBe("form.pdf");
});

test("content-disposition keeps non-ASCII names exactly and an ASCII fallback", () => {
  // Each non-ASCII character and each quote becomes "_" in the fallback.
  expect(contentDisposition('公司 "表格".pdf', false)).toBe(
    `attachment; filename="__ ____.pdf"; filename*=UTF-8''${encodeURIComponent('公司 "表格".pdf')}`,
  );
});
