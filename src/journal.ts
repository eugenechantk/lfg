// Event journal — the durable delivery buffer between the (single, global)
// session pump and any number of /api/events readers.
//
// Before this existed, live delivery was fire-and-forget: every SSE connection
// ran its own transcript-tail + pane-poll loops with private delta maps, so
// events emitted while a client was disconnected simply never existed, a
// reconnect replayed at most 40 messages, and busy/prompt transitions between
// connections were unobservable. The journal gives every event a monotonic
// per-host `seq`; a client that remembers its cursor reconnects with
// `since=<seq>` and receives exactly what it missed.
//
// Design pins (see .claude/brainstorm/multihost-first-rearchitecture.md §6.1):
// - bun:sqlite at ~/.lfg/journal.db (per-machine state — NOT in a synced path).
// - `payload` is stored as the exact JSON string the SSE `data:` line carries
//   ({sid, m} / {sid, busy} / …), so the iOS client's existing LiveEventDecoder
//   consumes journal events unchanged.
// - Transcripts remain the source of truth for messages; the journal is a
//   BOUNDED buffer (RETENTION_MS). A cursor that predates retention (or comes
//   from a different journal lifetime) gets `resync` instead of a partial replay.
// - A host journals only sessions it executes (the pump enumerates local
//   sessions), so two hosts can never double-deliver the same event.

import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export type JournalEventType = "msg" | "busy" | "prompt" | "queue";

export type JournalRow = {
  seq: number;
  ts: number;
  sessionId: string;
  type: string;
  payload: string; // JSON, exactly what the SSE data: line carries
};

export const RETENTION_MS = 14 * 24 * 60 * 60 * 1000;

type Listener = (row: JournalRow) => void;

export class Journal {
  private db: Database;
  private listeners = new Set<Listener>();
  private insertStmt;
  private sinceStmt;
  private headStmt;
  private oldestStmt;
  private getOffsetStmt;
  private setOffsetStmt;

  constructor(db: Database) {
    this.db = db;
    db.exec("PRAGMA journal_mode = WAL;");
    db.exec(`
      CREATE TABLE IF NOT EXISTS events (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        sessionId TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
      CREATE TABLE IF NOT EXISTS pump_state (
        sessionId TEXT PRIMARY KEY,
        offset INTEGER NOT NULL
      );
    `);
    this.insertStmt = db.prepare(
      "INSERT INTO events (ts, sessionId, type, payload) VALUES (?, ?, ?, ?) RETURNING seq",
    );
    this.sinceStmt = db.prepare(
      "SELECT seq, ts, sessionId, type, payload FROM events WHERE seq > ? ORDER BY seq LIMIT ?",
    );
    // Head must be the AUTOINCREMENT counter, not MAX(seq): after a retention
    // prune empties the table, MAX collapses to 0 and every caught-up client
    // would be told to resync. sqlite_sequence persists across deletes.
    this.headStmt = db.prepare(
      "SELECT COALESCE((SELECT seq FROM sqlite_sequence WHERE name = 'events'), 0) AS head",
    );
    this.oldestStmt = db.prepare("SELECT MIN(seq) AS oldest FROM events");
    this.getOffsetStmt = db.prepare("SELECT offset FROM pump_state WHERE sessionId = ?");
    this.setOffsetStmt = db.prepare(
      "INSERT INTO pump_state (sessionId, offset) VALUES (?, ?) " +
        "ON CONFLICT(sessionId) DO UPDATE SET offset = excluded.offset",
    );
  }

  static open(path: string): Journal {
    mkdirSync(dirname(path), { recursive: true });
    return new Journal(new Database(path));
  }

  /** Append one event; returns its seq and notifies live subscribers. */
  append(sessionId: string, type: JournalEventType, payload: unknown): number {
    const ts = Date.now();
    const payloadStr = JSON.stringify(payload);
    const row = this.insertStmt.get(ts, sessionId, type, payloadStr) as { seq: number };
    const full: JournalRow = { seq: row.seq, ts, sessionId, type, payload: payloadStr };
    for (const l of this.listeners) {
      try {
        l(full);
      } catch {}
    }
    return row.seq;
  }

  /** Events with seq strictly greater than `seq`, oldest first. */
  since(seq: number, limit = 1000): JournalRow[] {
    return this.sinceStmt.all(seq, limit) as JournalRow[];
  }

  head(): number {
    return (this.headStmt.get() as { head: number }).head;
  }

  /**
   * Whether `since` can be served as an incremental replay. Unserviceable when
   * it predates retention (events pruned past it) or exceeds head (a cursor
   * from a previous journal lifetime — e.g. the db was recreated). Both cases
   * → the client must full-resync and reset its cursor to head.
   */
  canServe(since: number): boolean {
    const head = this.head();
    if (since > head) return false;
    if (since === head) return true;
    const oldest = (this.oldestStmt.get() as { oldest: number | null }).oldest;
    // Empty table: consistent only when the cursor is exactly at head (fresh
    // journal → both 0; fully-pruned idle journal → cursor == persisted counter).
    if (oldest == null) return since === head;
    return since >= oldest - 1;
  }

  /** Drop events older than the retention window. Returns rows deleted. */
  prune(now = Date.now()): number {
    const r = this.db
      .prepare("DELETE FROM events WHERE ts < ?")
      .run(now - RETENTION_MS);
    return r.changes;
  }

  /** Live subscription (in-process). Returns unsubscribe. */
  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  // -- pump offsets (persisted so a server restart never re-journals history) --

  getOffset(sessionId: string): number | null {
    const r = this.getOffsetStmt.get(sessionId) as { offset: number } | null;
    return r ? r.offset : null;
  }

  setOffset(sessionId: string, offset: number): void {
    this.setOffsetStmt.run(sessionId, offset);
  }

  close(): void {
    this.db.close();
  }
}

/**
 * Pure delta tracker for the pump's state-shaped events (busy/prompt/queue).
 * The journal must record CHANGES, not samples — a 1 Hz poll of an unchanged
 * pane must journal nothing. First sight of a session in a pump lifetime
 * always emits (a server restart resets in-memory maps; re-stating current
 * busy/prompt/queue once is a handful of idempotent events, and it is what
 * keeps a client from holding a stale busy=true across a server restart).
 */
export class PumpDeltas {
  private lastBusy = new Map<string, string>();
  private lastPrompt = new Map<string, string>();
  private lastQueue = new Map<string, string>();

  /** Returns true when this busy value should be journaled. */
  busyChanged(sid: string, busy: boolean): boolean {
    const sig = busy ? "1" : "0";
    if (this.lastBusy.get(sid) === sig) return false;
    this.lastBusy.set(sid, sig);
    return true;
  }

  promptChanged(sid: string, prompt: unknown): boolean {
    const sig = prompt ? JSON.stringify(prompt) : "";
    if (this.lastPrompt.get(sid) === sig) return false;
    this.lastPrompt.set(sid, sig);
    return true;
  }

  queueChanged(sid: string, queue: unknown[]): boolean {
    const sig = JSON.stringify(queue);
    if (this.lastQueue.get(sid) === sig) return false;
    this.lastQueue.set(sid, sig);
    return true;
  }

  /** Sessions no longer present locally — drop their maps so a session that
   * comes back (transfer round-trip) re-states its baseline. */
  forget(sid: string): void {
    this.lastBusy.delete(sid);
    this.lastPrompt.delete(sid);
    this.lastQueue.delete(sid);
  }
}
