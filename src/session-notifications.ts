import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { ApnsPayload, ApnsResult } from "./push/apns";
import { deviceMutesSession } from "./push/store";
import { alertTitle } from "./alert-title";

export const NOTIFICATION_STATUSES = ["working", "completed", "needs-input", "blocked", "reminder"] as const;
export type NotificationStatus = typeof NOTIFICATION_STATUSES[number];
export const notificationLabels: Record<NotificationStatus, string> = {
  working: "Working", completed: "Completed", "needs-input": "Needs input", blocked: "Blocked", reminder: "Reminder",
};
export type SessionNotification = {
  id: string; sessionId: string; requestID: string; status: NotificationStatus;
  title: string; message: string; createdAt: number; turnStartedAt: number | null;
};
// `muted` counts devices that hide the session's directory; present only when nonzero.
type MobileReceipt = { state: "pending" | "accepted" | "partial" | "failed" | "unavailable" | "muted"; attempted: number; accepted: number; failed: number; muted?: number };
type Receipt = { notification: SessionNotification; mobile: MobileReceipt };
type NotificationSession = { sessionId?: string | null; title?: string | null; lastUserAt?: number | null; cwd?: string | null };
type Device = { token: string; env: "sandbox" | "production"; hiddenDirs?: string[] };
type Options = {
  sessions: () => Promise<NotificationSession[]>;
  emit: (sid: string, notification: SessionNotification) => void;
  devices: () => Promise<Device[]>;
  send: (device: Device, payload: ApnsPayload) => Promise<ApnsResult>;
  now?: () => number;
};
class NotificationError extends Error {
  constructor(message: string, readonly status = 400) { super(message); }
}
const cleanText = (value: unknown, name: string, max: number): string => {
  if (typeof value !== "string" || !value.trim() || [...value].length > max)
    throw new NotificationError(`${name} must contain 1 to ${max} characters.`);
  const clean = value.replace(/\s+/g, " ").trim();
  if (/[\u0000-\u001f\u007f\uD800-\uDFFF]/u.test(clean))
    throw new NotificationError(`${name} must contain valid display text.`);
  return clean;
};
const sessionTitle = (title: string | null | undefined): string =>
  [...(title || "Session").replace(/\s+/g, " ").replace(/[\u0000-\u001f\u007f]/g, "").replace(/[\uD800-\uDFFF]/gu, "�").trim()]
    .slice(0, 80).join("") || "Session";

/** Bounded receipts, serialized within the host. Retries never replay uncertain sends. */
export class SessionNotifications {
  readonly ready: Promise<this>;
  private receipts: Receipt[] = [];
  private chain: Promise<unknown> = Promise.resolve();
  constructor(private file: string, private options: Options) {
    this.ready = readFile(file, "utf8").then(raw => {
      const state = JSON.parse(raw);
      if (state.version !== 1 || !Array.isArray(state.receipts)) throw Error("Invalid notification receipts");
      this.receipts = state.receipts;
      return this;
    }).catch(error => { if (error.code === "ENOENT") return this; throw error; });
  }
  latest(sid: string): SessionNotification | undefined {
    return this.receipts.findLast(r => r.notification.sessionId === sid)?.notification;
  }
  latestCompletion(sid: string): SessionNotification | undefined {
    return this.receipts.findLast(r => r.notification.sessionId === sid && r.notification.status === "completed")?.notification;
  }
  completedTurn(sid: string, session: NotificationSession): boolean {
    return this.receipts.some(r => r.notification.sessionId === sid && r.notification.status === "completed" && sameNotificationTurn(r.notification, session));
  }
  private async save() {
    await mkdir(dirname(this.file), { recursive: true });
    const tmp = this.file + ".tmp";
    await writeFile(tmp, JSON.stringify({ version: 1, receipts: this.receipts }), { mode: 0o600 });
    await rename(tmp, this.file);
  }
  async send(sid: string, input: unknown): Promise<Receipt & { duplicate: boolean; reclassified?: string }> {
    const run = this.chain.catch(() => {}).then(async () => {
      await this.ready;
      if (!input || typeof input !== "object" || Array.isArray(input)) throw new NotificationError("Expected a JSON object.");
      const value = input as Record<string, unknown>;
      const requestID = cleanText(value.requestID, "requestID", 160);
      const message = cleanText(value.message, "message", 500);
      if (!NOTIFICATION_STATUSES.includes(value.status as NotificationStatus)) throw new NotificationError("Choose completed, blocked, reminder, or working.");
      // "Needs input" means a question is OPEN in the session, and the push
      // watcher announces that itself the moment the prompt appears, with the
      // question. An agent that sends needs-input has written its question into a
      // reply and is ending its turn: all 7 such alerts on record (2026-11-02 to
      // 11-05) were followed by the turn ending about a minute later with no
      // prompt. So the alert goes out as what it is — a completed turn — and
      // "needs input" only ever means a question is waiting.
      const requested = value.status as NotificationStatus;
      const status: NotificationStatus = requested === "needs-input" ? "completed" : requested;
      const reclassified = requested !== status ? { reclassified: `${requested} → ${status}: lfg alerts open questions itself` } : {};
      const title = value.title === undefined ? undefined : cleanText(value.title, "title", 80);
      const previous = this.receipts.find(r => r.notification.sessionId === sid && r.notification.requestID === requestID);
      if (previous) {
        if (previous.notification.message !== message || previous.notification.status !== status || (title !== undefined && previous.notification.title !== title))
          throw new NotificationError("requestID already belongs to a different notification.", 409);
        return { ...previous, duplicate: true, ...reclassified };
      }
      const session = (await this.options.sessions()).find(s => s.sessionId === sid);
      if (!session) throw new NotificationError("Session is not running on this host.", 404);
      const notification: SessionNotification = {
        id: crypto.randomUUID(), sessionId: sid, requestID, status, message,
        title: title ?? sessionTitle(session.title),
        createdAt: (this.options.now ?? Date.now)(), turnStartedAt: session.lastUserAt ?? null,
      };
      const receipt: Receipt = { notification, mobile: { state: "pending", attempted: 0, accepted: 0, failed: 0 } };
      this.receipts.push(receipt);
      // Keep idempotency receipts for at least 14 days, with a generous hard cap.
      this.receipts = this.receipts.filter(r => r.notification.createdAt >= notification.createdAt - 14 * 86400_000).slice(-10_000);
      await this.save();
      this.options.emit(sid, notification);
      const devices = await this.options.devices();
      const payload: ApnsPayload = {
        // The emoji lives on the alert only; the stored receipt keeps the
        // agent's title, which idempotent retries compare against.
        title: alertTitle(status, notification.title), body: `${notificationLabels[status]}: ${message}`, sid,
        kind: status === "completed" ? "finished" : status === "blocked" ? "needs-input" : "status",
        notificationId: notification.id, session: { id: sid, title: sessionTitle(session.title), cwd: session.cwd ?? null },
      };
      for (const device of devices) {
        if (deviceMutesSession(device, session.cwd)) { receipt.mobile.muted = (receipt.mobile.muted ?? 0) + 1; continue; }
        receipt.mobile.attempted++;
        try {
          const result = await this.options.send(device, payload);
          if (result.ok) receipt.mobile.accepted++; else receipt.mobile.failed++;
        } catch { receipt.mobile.failed++; }
      }
      const { attempted, accepted, failed } = receipt.mobile;
      receipt.mobile.state = !attempted ? (receipt.mobile.muted ? "muted" : "unavailable") : !failed ? "accepted" : accepted ? "partial" : "failed";
      await this.save();
      return { ...receipt, duplicate: false, ...reclassified };
    });
    this.chain = run;
    return run;
  }
}

export function sameNotificationTurn(notification: SessionNotification, session: NotificationSession): boolean {
  // Session enumeration can lag the transcript. A completed alert covers user
  // work already submitted when it was sent, never a later user turn.
  return session.lastUserAt == null || notification.createdAt >= session.lastUserAt;
}

export function sessionNotificationRoutes(service: SessionNotifications) {
  return async (req: Request): Promise<Response | undefined> => {
    const url = new URL(req.url), match = url.pathname.match(/^\/api\/sessions\/([^/]+)\/notify$/);
    if (!match) return;
    try {
      if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405 });
      const origin = req.headers.get("origin");
      if (origin && origin !== url.origin) throw new NotificationError("Cross-origin request refused", 403);
      if (Number(req.headers.get("content-length")) > 5000) throw new NotificationError("Request too large", 413);
      const raw = await req.text();
      if (raw.length > 5000) throw new NotificationError("Request too large", 413);
      let input: unknown;
      try { input = JSON.parse(raw); } catch { throw new NotificationError("Expected a JSON object."); }
      return Response.json(await service.send(decodeURIComponent(match[1]!), input), { headers: { "Cache-Control": "no-store" } });
    } catch (error) {
      return Response.json({ error: error instanceof NotificationError ? error.message : "Notification could not be sent. Retry only with the same requestID." }, { status: error instanceof NotificationError ? error.status : 503 });
    }
  };
}
