// Throwaway stub lfg host for reproducing client offline/recovery bugs.
// Serves just enough of the API for the iOS client to cache a good snapshot,
// go offline when killed, and record any /send that arrives on recovery.
// See memory [[lfg-stub-host-offline-repro]] — never a second `lfg serve`.
//
//   bun .claude/evidence/20260811-offline-queue/stub-host.ts [port]
//
// Every request is logged to stdout AND appended to ./stub-host.log so a
// backgrounded run is never a silent hang.

const PORT = Number(process.argv[2] ?? 8799)
const LOG = new URL("./stub-host.log", import.meta.url).pathname
const SID = "11111111-2222-3333-4444-555555555555"
const BOOT = Date.now()

function log(line: string) {
  const stamped = `${new Date().toISOString()} ${line}`
  console.log(stamped)
  // APPEND only. An earlier version also called Bun.write(), which truncates —
  // the two racing writers produced a log that silently lost most requests.
  try {
    require("fs").appendFileSync(LOG, stamped + "\n")
  } catch {}
}

const session = {
  sessionId: SID,
  title: "Stub session",
  agent: "claude",
  model: "opus",
  project: "stub",
  cwd: "/Users/eugenechan/dev/personal/lfg",
  status: "ok",
  lastUserText: "hello from the stub",
  startedAt: BOOT,
  lastActivityAt: BOOT,
  tmuxTarget: "stub:0.0",
  tmuxName: "stub",
  managed: true,
  busy: false,
}

const messages = [
  { id: "m1", role: "user", kind: "text", text: "hello from the stub", ts: BOOT },
  { id: "m2", role: "assistant", kind: "text", text: "Stub host reporting for duty.", ts: BOOT + 1000 },
]

// Everything POSTed to /send lands here so the repro can assert delivery.
const received: Array<{ at: number; text: string; clientId?: string }> = []

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  })
}

Bun.serve({
  port: PORT,
  idleTimeout: 0,
  async fetch(req) {
    const u = new URL(req.url)
    const p = u.pathname
    log(`${req.method} ${p}${u.search}`)

    if (p === "/api/info") return json({ hostId: "stub", hostName: "stub-host" })
    if (p === "/api/ping") return json({ ok: true, t: Date.now() })
    if (p === "/api/sessions") return json({ sessions: [session] })
    if (p === "/api/sessions/resumable") return json({ sessions: [] })
    if (p === "/api/repos") return json({ repos: [] })
    if (p === "/api/dirs") return json({ root: "/Users/eugenechan/dev", dirs: [] })
    if (p === "/api/users") return json({ users: [] })

    if (p === `/api/sessions/${SID}/messages`) {
      return json({ id: SID, messages, total: messages.length })
    }
    if (p === `/api/sessions/${SID}/queue`) return json({ id: SID, queue: [] })

    if (p === `/api/sessions/${SID}/send` && req.method === "POST") {
      const body = (await req.json().catch(() => ({}))) as any
      received.push({ at: Date.now(), text: body?.text ?? "", clientId: body?.clientId })
      log(`>>> SEND RECEIVED clientId=${body?.clientId} text=${JSON.stringify(body?.text)}`)
      messages.push({ id: `u${received.length}`, role: "user", kind: "text", text: body?.text ?? "", ts: Date.now() })
      session.lastActivityAt = Date.now()
      return json({ ok: true, clientId: body?.clientId })
    }

    // Test-only introspection: what has the client delivered?
    if (p === "/__received") return json({ received })

    // Long-poll SSE. Heartbeat only — the client just needs bytes to call the
    // host live. No journal events, so nothing to replay.
    if (p === "/api/events") {
      const stream = new ReadableStream({
        start(c) {
          const enc = new TextEncoder()
          c.enqueue(enc.encode(": connected\n\n"))
          const iv = setInterval(() => {
            try {
              c.enqueue(enc.encode("event: heartbeat\ndata: {}\n\n"))
            } catch {
              clearInterval(iv)
            }
          }, 5000)
          req.signal?.addEventListener("abort", () => clearInterval(iv))
        },
      })
      return new Response(stream, {
        headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
      })
    }

    if (p.startsWith("/api/push/")) return json({ ok: true })

    return json({ error: "not found", path: p }, 404)
  },
})

log(`stub host listening on :${PORT} sid=${SID}`)
