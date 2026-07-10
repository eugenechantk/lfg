import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export type SendqStatus = "pending" | "sending" | "delivered" | "queued" | "failed";

export type SendqRow = {
  id: string;
  sessionId: string;
  clientId: string;
  text: string;
  status: SendqStatus;
  error: string | null;
  attempts: number;
  redeliveries: number;
  createdAt: number;
  updatedAt: number;
};

export type SendqRowInput = Omit<SendqRow, "error" | "redeliveries"> & {
  error?: string | null;
  redeliveries?: number | null;
};

export class SendqStore {
  private db: Database;
  private upsertStmt;
  private byClientIdStmt;
  private byIdStmt;
  private recoverStmt;
  private deleteStmt;
  private terminalStmt;

  constructor(db: Database) {
    this.db = db;
    db.exec("PRAGMA journal_mode = WAL;");
    db.exec(`
      CREATE TABLE IF NOT EXISTS sendq (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        clientId TEXT NOT NULL,
        text TEXT NOT NULL,
        status TEXT NOT NULL,
        error TEXT,
        attempts INTEGER NOT NULL,
        redeliveries INTEGER NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_sendq_session_client ON sendq(sessionId, clientId);
      CREATE INDEX IF NOT EXISTS idx_sendq_recover ON sendq(status, createdAt);
    `);
    this.upsertStmt = db.prepare(`
      INSERT INTO sendq (
        id, sessionId, clientId, text, status, error, attempts, redeliveries, createdAt, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        sessionId = excluded.sessionId,
        clientId = excluded.clientId,
        text = excluded.text,
        status = excluded.status,
        error = excluded.error,
        attempts = excluded.attempts,
        redeliveries = excluded.redeliveries,
        createdAt = excluded.createdAt,
        updatedAt = excluded.updatedAt
    `);
    this.byClientIdStmt = db.prepare(`
      SELECT id, sessionId, clientId, text, status, error, attempts, redeliveries, createdAt, updatedAt
      FROM sendq
      WHERE sessionId = ? AND clientId = ?
      ORDER BY createdAt ASC
      LIMIT 1
    `);
    this.byIdStmt = db.prepare(`
      SELECT id, sessionId, clientId, text, status, error, attempts, redeliveries, createdAt, updatedAt
      FROM sendq
      WHERE id = ?
    `);
    this.recoverStmt = db.prepare(`
      SELECT id, sessionId, clientId, text, status, error, attempts, redeliveries, createdAt, updatedAt
      FROM sendq
      WHERE status IN ('pending', 'sending', 'queued')
      ORDER BY createdAt ASC, id ASC
    `);
    this.deleteStmt = db.prepare("DELETE FROM sendq WHERE id = ?");
    this.terminalStmt = db.prepare(`
      SELECT id
      FROM sendq
      WHERE sessionId = ? AND status IN ('delivered', 'failed')
      ORDER BY updatedAt ASC, id ASC
    `);
  }

  static open(path: string): SendqStore {
    mkdirSync(dirname(path), { recursive: true });
    return new SendqStore(new Database(path));
  }

  upsert(row: SendqRowInput): void {
    this.upsertStmt.run(
      row.id,
      row.sessionId,
      row.clientId,
      row.text,
      row.status,
      row.error ?? null,
      row.attempts,
      row.redeliveries ?? 0,
      row.createdAt,
      row.updatedAt,
    );
  }

  findByClientId(sessionId: string, clientId: string): SendqRow | null {
    return (this.byClientIdStmt.get(sessionId, clientId) as SendqRow | null) ?? null;
  }

  findById(id: string): SendqRow | null {
    return (this.byIdStmt.get(id) as SendqRow | null) ?? null;
  }

  recoverable(): SendqRow[] {
    return this.recoverStmt.all() as SendqRow[];
  }

  delete(id: string): void {
    this.deleteStmt.run(id);
  }

  deleteMany(ids: string[]): void {
    for (const id of ids) this.delete(id);
  }

  pruneTerminal(sessionId: string, keep: number): string[] {
    const rows = this.terminalStmt.all(sessionId) as Array<{ id: string }>;
    const drop = rows.slice(0, Math.max(0, rows.length - keep)).map((r) => r.id);
    this.deleteMany(drop);
    return drop;
  }

  close(): void {
    this.db.close();
  }
}
