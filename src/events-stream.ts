/**
 * The body of `GET /api/events?since=<cursor>`: a cursor-resumable SSE stream
 * of journal rows, with a heartbeat carrying the journal head.
 *
 * A cursor the journal cannot serve (pruned past, or from an older journal)
 * gets one `resync` frame naming the head; the client resets its cursor to
 * that head and reloads over REST. The stream then carries on from the head.
 * It used to stop there: the resync branch never subscribed, so the
 * connection sent heartbeats and nothing else. The client reads heartbeats as
 * "caught up" and keeps the connection, so every busy, prompt and message
 * after it was lost until the connection happened to drop — a fresh install
 * or a phone that had not opened the app for two weeks saw a session view
 * that never updated (2026-10-16).
 */

export type StreamJournal = {
  head(): number;
  canServe(since: number): boolean;
  since(seq: number, limit?: number): { seq: number; type: string; payload: string }[];
  subscribe(fn: (row: { seq: number; type: string; payload: string }) => void): () => void;
};

export function journalEventStream(
  journal: StreamJournal,
  cursor: number,
  opts: { heartbeatMs?: number } = {},
): ReadableStream<string> {
  const heartbeatMs = opts.heartbeatMs ?? 10_000;
  let unsub: (() => void) | null = null;
  let hb: ReturnType<typeof setInterval> | null = null;
  let closed = false;
  return new ReadableStream<string>({
    start(controller) {
      const send = (s: string) => {
        if (closed) return;
        try {
          controller.enqueue(s);
        } catch {
          closed = true;
          if (unsub) unsub();
          if (hb) clearInterval(hb);
        }
      };
      const sendRow = (r: { seq: number; type: string; payload: string }) =>
        send(`id: ${r.seq}\nevent: ${r.type}\ndata: ${r.payload}\n\n`);

      if (!journal.canServe(cursor)) {
        // Head and subscribe in the same tick: nothing can be appended between
        // them, so every row after the head the client adopts is delivered.
        const head = journal.head();
        send(`event: resync\ndata: ${JSON.stringify({ head })}\n\n`);
        let lastSent = head;
        unsub = journal.subscribe((row) => {
          if (row.seq > lastSent) {
            lastSent = row.seq;
            sendRow(row);
          }
        });
      } else {
        // Subscribe FIRST (buffering), then replay, then flush the buffer —
        // an event appended mid-replay is neither lost nor duplicated.
        let lastSent = cursor;
        let replaying = true;
        const buffered: { seq: number; type: string; payload: string }[] = [];
        unsub = journal.subscribe((row) => {
          if (replaying) buffered.push(row);
          else if (row.seq > lastSent) {
            lastSent = row.seq;
            sendRow(row);
          }
        });
        let at = cursor;
        for (;;) {
          const rows = journal.since(at, 1000);
          if (rows.length === 0) break;
          for (const r of rows) {
            sendRow(r);
            lastSent = r.seq;
          }
          at = lastSent;
        }
        for (const r of buffered) {
          if (r.seq > lastSent) {
            lastSent = r.seq;
            sendRow(r);
          }
        }
        replaying = false;
      }
      // Heartbeat carrying head seq: keepalive + a cheap gap detector
      // (client compares against its cursor without waiting for events).
      //
      // The FIRST one is sent immediately, not 10s in. A client whose
      // cursor is already at head — the normal case when no sessions are
      // running — gets no replay rows, so without this the response body
      // stays empty for up to 10s and the client cannot tell an
      // established stream from a black-holed dial. `HostLink` only leaves
      // `.connecting` on the first element received, so that silence was
      // the app showing "Offline" for ~10s after reopening against a
      // perfectly healthy idle host.
      send(`: hb ${journal.head()}\n\n`);
      hb = setInterval(() => send(`: hb ${journal.head()}\n\n`), heartbeatMs);
    },
    cancel() {
      closed = true;
      if (unsub) unsub();
      if (hb) clearInterval(hb);
    },
  });
}
