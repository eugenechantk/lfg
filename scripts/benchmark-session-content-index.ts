/** Read-only corpus sample. The SQLite database lives in a disposable temp dir. */
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionContentIndex } from "../src/session-content-index";
import { collectResumableCandidates, createCodexNormalizationState, searchProse } from "../src/sessions";

const limit = Math.max(1, Math.min(20_000, Number(process.argv.find((arg) => arg.startsWith("--limit="))?.split("=")[1] ?? 100)));
const root = mkdtempSync(join(tmpdir(), "lfg-content-benchmark-"));
const path = join(root, "content.sqlite");
try {
  const all = await collectResumableCandidates();
  const sample = Array.from({ length: Math.min(limit, all.length) }, (_, i) =>
    all[Math.floor((i + 0.5) * all.length / Math.min(limit, all.length))]);
  const sourceBytes = sample.reduce((total, item) => {
    try { return total + statSync(item.path).size; } catch { return total; }
  }, 0);
  const index = new SessionContentIndex(path);
  const started = performance.now();
  const changed = await index.reconcile(sample.map((item) => ({
    sessionId: item.id, path: item.path, mtime: item.mtime,
  })), searchProse, createCodexNormalizationState);
  const buildMs = Math.round(performance.now() - started);
  const queries = ["noto", "keyboard", "ultramarine"].map((q) => {
    const started = performance.now();
    const hits = Array.from(index.hits([q]));
    return { q, messages: hits.length, ms: Math.round(performance.now() - started) };
  });
  const stats = index.stats();
  index.close();
  const dbBytes = statSync(path).size;
  console.log(JSON.stringify({ corpusSessions: all.length, sampledSessions: sample.length,
    sourceBytes, dbBytes, buildMs, changed, stats, queries }, null, 2));
} finally {
  rmSync(root, { recursive: true, force: true });
}
