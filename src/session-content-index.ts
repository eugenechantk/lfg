import { Database } from "bun:sqlite";
import { watch, mkdirSync, type FSWatcher } from "node:fs";
import { dirname, join } from "node:path";

export type ContentCandidate = {
  sessionId: string;
  path: string;
  mtime: number;
};

export type ProseMessage = {
  role: "user" | "assistant";
  text: string;
  ts: number | null;
};

export type ContentHit = ProseMessage & {
  sessionId: string;
  rank: number;
};

type IndexedFile = { path: string; mtime: number; size: number; offset: number };
type Normalizer = (line: string, state: unknown) => ProseMessage[];

/** Only complete JSONL rows advance the checkpoint. A partial append is retried. */
export async function* completeLines(
  path: string,
  start: number,
  end: number,
): AsyncGenerator<{ text: string; byte: number; nextByte: number }> {
  const file = Bun.file(path);
  const decoder = new TextDecoder();
  const maxRowBytes = 8 * 1024 * 1024;
  let parts: Uint8Array[] = [];
  let pendingBytes = 0;
  let oversized = false;
  let byte = start;
  let consumed = 0;
  const append = (part: Uint8Array) => {
    pendingBytes += part.byteLength;
    if (oversized || pendingBytes > maxRowBytes) {
      oversized = true;
      parts = [];
    } else if (part.byteLength) {
      parts.push(part.slice());
    }
  };
  const lineText = () => {
    if (oversized) return "";
    const joined = new Uint8Array(pendingBytes);
    let offset = 0;
    for (const part of parts) { joined.set(part, offset); offset += part.byteLength; }
    return decoder.decode(joined);
  };
  for await (const chunk of file.slice(start, end).stream()) {
    consumed += chunk.byteLength;
    let from = 0;
    let nl = chunk.indexOf(10, from);
    while (nl >= 0) {
      append(chunk.subarray(from, nl));
      const nextByte = byte + pendingBytes + 1;
      yield { text: lineText(), byte, nextByte };
      byte = nextByte;
      parts = [];
      pendingBytes = 0;
      oversized = false;
      from = nl + 1;
      nl = chunk.indexOf(10, from);
    }
    append(chunk.subarray(from));
    // Bun can leave a bounded slice stream open when its end precedes EOF.
    if (consumed >= end - start) break;
  }
  if (pendingBytes && !oversized) {
    const text = lineText();
    try {
      JSON.parse(text);
      yield { text, byte, nextByte: byte + pendingBytes };
    } catch {
      // An active writer has not finished this row yet.
    }
  }
}

/** Rebuildable per-host FTS5 store. It never writes to the synced transcript tree. */
export class SessionContentIndex {
  private readonly db: Database;
  private readonly files;
  private readonly upsertFile;
  private readonly insertMeta;
  private readonly insertText;
  private readonly deleteText;
  private readonly deleteMeta;
  private readonly deleteFile;

  constructor(path: string) {
    mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path);
    const schema = this.db.query("PRAGMA user_version").get() as { user_version: number };
    if (schema.user_version !== 1) {
      // This database is wholly derived from transcripts. A parser/schema
      // change intentionally rebuilds it rather than serving stale matches.
      this.db.exec("DROP TABLE IF EXISTS prose; DROP TABLE IF EXISTS message_meta; DROP TABLE IF EXISTS files;");
    }
    this.db.exec(`
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS files (
        session_id TEXT PRIMARY KEY, path TEXT NOT NULL, mtime REAL NOT NULL,
        size INTEGER NOT NULL, offset INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS message_meta (
        id INTEGER PRIMARY KEY, session_id TEXT NOT NULL, role TEXT NOT NULL,
        source_byte INTEGER NOT NULL, ts REAL
      );
      CREATE INDEX IF NOT EXISTS message_session ON message_meta(session_id);
      CREATE VIRTUAL TABLE IF NOT EXISTS prose USING fts5(text, tokenize='unicode61');
      PRAGMA user_version=1;
    `);
    this.files = this.db.prepare("SELECT path, mtime, size, offset FROM files WHERE session_id=?");
    this.upsertFile = this.db.prepare("INSERT INTO files VALUES (?,?,?,?,?) ON CONFLICT(session_id) DO UPDATE SET path=excluded.path,mtime=excluded.mtime,size=excluded.size,offset=excluded.offset");
    this.insertMeta = this.db.prepare("INSERT INTO message_meta(session_id,role,source_byte,ts) VALUES (?,?,?,?) RETURNING id");
    this.insertText = this.db.prepare("INSERT INTO prose(rowid,text) VALUES (?,?)");
    this.deleteText = this.db.prepare("DELETE FROM prose WHERE rowid IN (SELECT id FROM message_meta WHERE session_id=?)");
    this.deleteMeta = this.db.prepare("DELETE FROM message_meta WHERE session_id=?");
    this.deleteFile = this.db.prepare("DELETE FROM files WHERE session_id=?");
  }

  close(): void { this.db.close(); }

  private clearSession(sessionId: string): void {
    this.deleteText.run(sessionId);
    this.deleteMeta.run(sessionId);
    this.deleteFile.run(sessionId);
  }

  /** Append changed files and repair rewrites/deletions. Idempotent across restarts. */
  async reconcile(
    candidates: ContentCandidate[],
    normalize: Normalizer,
    newState: () => unknown,
    forcedPaths: ReadonlySet<string> = new Set(),
  ): Promise<{ changed: number; removed: number }> {
    const ids = new Set(candidates.map((candidate) => candidate.sessionId));
    let changed = 0;
    for (const candidate of candidates) {
      const previous = this.files.get(candidate.sessionId) as IndexedFile | null;
      const file = Bun.file(candidate.path);
      if (!(await file.exists())) continue;
      const size = file.size;
      const forced = [...forcedPaths].some((path) =>
        candidate.path === path || candidate.path.startsWith(`${path}/`));
      if (previous?.path === candidate.path && previous.mtime === candidate.mtime &&
          previous.size === size && previous.offset === size && !forced) continue;
      const append = previous?.path === candidate.path && size >= previous.size &&
        previous.offset <= size && candidate.mtime >= previous.mtime;
      // A changed file of equal size is a rewrite. An append starts at the
      // checkpoint, which may precede a partial final row.
      const start = append && size > previous.size ? previous.offset : 0;
      const state = newState();
      if (start > 0) {
        const head = await file.slice(0, Math.min(size, 64 * 1024)).text();
        const first = head.split("\n", 1)[0];
        if (first) normalize(first, state);
      }
      let offset = start;
      if (start === 0) this.db.transaction(() => this.clearSession(candidate.sessionId))();
      let batch: Array<{ message: ProseMessage; byte: number }> = [];
      const flush = () => {
        if (!batch.length && offset === start) return;
        this.db.transaction(() => {
          for (const { message, byte } of batch) {
            const row = this.insertMeta.get(candidate.sessionId, message.role, byte, message.ts) as { id: number };
            this.insertText.run(row.id, message.text);
          }
          this.upsertFile.run(candidate.sessionId, candidate.path, candidate.mtime, size, offset);
        })();
        batch = [];
      };
      for await (const line of completeLines(candidate.path, start, size)) {
        for (const message of normalize(line.text, state)) {
          if ((message.role === "user" || message.role === "assistant") && message.text.trim())
            batch.push({ message, byte: line.byte });
        }
        offset = line.nextByte;
        if (batch.length >= 256) {
          flush();
          await Bun.sleep(0);
        }
      }
      flush();
      // A file with no prose still needs a checkpoint.
      if (offset === start) this.upsertFile.run(candidate.sessionId, candidate.path, candidate.mtime, size, offset);
      changed++;
    }
    const all = this.db.query("SELECT session_id FROM files").all() as Array<{ session_id: string }>;
    let removed = 0;
    for (const row of all) if (!ids.has(row.session_id)) {
      this.db.transaction(() => this.clearSession(row.session_id))();
      removed++;
    }
    return { changed, removed };
  }

  /** FTS returns matching messages; callers combine them into ranked sessions. */
  *hits(terms: string[]): IterableIterator<ContentHit> {
    const searchable = terms.filter((term) => /[\p{L}\p{N}]/u.test(term));
    if (!searchable.length) return;
    const expression = searchable.map((term) => `"${term.replaceAll('"', '""')}"*`).join(" OR ");
    const rows = this.db.prepare(`
      SELECT m.session_id AS sessionId, m.role, m.ts, p.text,
             bm25(prose) AS rank
      FROM prose AS p JOIN message_meta AS m ON m.id=p.rowid
      WHERE prose MATCH ? ORDER BY rank
    `).iterate(expression) as IterableIterator<ContentHit>;
    yield* rows;
  }

  stats(): { files: number; messages: number } {
    const files = this.db.query("SELECT count(*) AS n FROM files").get() as { n: number };
    const messages = this.db.query("SELECT count(*) AS n FROM message_meta").get() as { n: number };
    return { files: files.n, messages: messages.n };
  }
}

/** Watchers are latency hints. A periodic full reconcile guarantees repair. */
export function watchTranscriptRoots(
  roots: string[],
  reconcile: (changedPaths: ReadonlySet<string>) => Promise<void>,
  intervalMs = 60_000,
): () => void {
  const watchers: FSWatcher[] = [];
  const watched = new Set<string>();
  let pending: ReturnType<typeof setTimeout> | null = null;
  let active = false;
  let again = false;
  let stopped = false;
  const changedPaths = new Set<string>();
  const run = async () => {
    if (stopped) return;
    if (active) { again = true; return; }
    active = true;
    const paths = new Set(changedPaths);
    changedPaths.clear();
    try { await reconcile(paths); }
    catch { /* A later watcher event or periodic pass retries. */ }
    finally {
      active = false;
      if (again && !stopped) { again = false; schedule(); }
    }
  };
  const schedule = (path?: string) => {
    if (stopped) return;
    if (path) changedPaths.add(path);
    if (pending) clearTimeout(pending);
    pending = setTimeout(() => { pending = null; void run(); }, 350);
    pending.unref?.();
  };
  const attach = (root: string) => {
    if (watched.has(root)) return;
    try {
      const watcher = watch(root, { recursive: true }, (_event, filename) => {
        schedule(filename ? join(root, filename.toString()) : undefined);
      });
      watcher.on("error", () => {
        watched.delete(root);
        watcher.close();
        schedule();
      });
      watchers.push(watcher);
      watched.add(root);
    } catch { /* Missing roots are picked up by the periodic reconciliation. */ }
  };
  roots.forEach(attach);
  const periodic = setInterval(() => {
    roots.forEach(attach);
    void run();
  }, intervalMs);
  periodic.unref?.();
  void run();
  return () => {
    stopped = true;
    if (pending) clearTimeout(pending);
    clearInterval(periodic);
    for (const watcher of watchers) watcher.close();
  };
}
