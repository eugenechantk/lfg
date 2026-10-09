// Runs scripts/pdf-extract.swift (PDFKit) for the MCP server's read_file: page
// text, filled form-field values, and JPEG renders of the pages.
//
// The Swift source is compiled once into ~/.lfg/cache/pdf-extract and rebuilt
// when the source is newer than the binary. Compiling takes a few seconds, so
// scripts/lfg-mcp.ts warms it at startup rather than on a remote caller's clock.

import { mkdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export type PdfField = { page: number; name: string; type: string; value: string };
export type PdfPage = { page: number; text: string; image?: string };
export type PdfExtract = { pageCount: number; pages: PdfPage[]; fields: PdfField[] };
export type PdfExtractor = (pdf: string, outDir: string, firstPage: number, maxPages: number, maxPx: number) => Promise<PdfExtract>;

const SOURCE = join(import.meta.dir, "..", "scripts", "pdf-extract.swift");

function mtime(p: string): number {
  try {
    return statSync(p).mtimeMs;
  } catch {
    return 0;
  }
}

let building: Promise<string> | null = null;

/** Path to a compiled helper that is at least as new as its source. */
export function ensurePdfHelper(bin = join(homedir(), ".lfg", "cache", "pdf-extract")): Promise<string> {
  if (mtime(bin) >= mtime(SOURCE) && mtime(bin) > 0) return Promise.resolve(bin);
  building ??= (async () => {
    mkdirSync(join(bin, ".."), { recursive: true });
    const r = await Bun.$`swiftc -O ${SOURCE} -o ${bin}`.quiet().nothrow();
    if (r.exitCode !== 0) throw new Error(`could not build the PDF reader: ${r.stderr.toString().slice(0, 300)}`);
    return bin;
  })().finally(() => {
    building = null;
  });
  return building;
}

export const extractPdf: PdfExtractor = async (pdf, outDir, firstPage, maxPages, maxPx) => {
  const bin = await ensurePdfHelper();
  const r = await Bun.$`${bin} ${pdf} ${outDir} ${firstPage} ${maxPages} ${maxPx}`.quiet().nothrow();
  let out: (PdfExtract & { error?: undefined }) | { error: string };
  try {
    out = JSON.parse(r.stdout.toString());
  } catch {
    throw new Error(`the PDF reader failed (exit ${r.exitCode})`);
  }
  if ("error" in out && out.error) throw new Error(out.error);
  return out as PdfExtract;
};
