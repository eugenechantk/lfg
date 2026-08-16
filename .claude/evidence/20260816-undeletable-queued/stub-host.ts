// Throwaway stub lfg host for reproducing "a queued message I cannot delete".
// See memory [[lfg-stub-host-offline-repro]] — never a second `lfg serve`.
//
//   bun .claude/evidence/20260816-undeletable-queued/stub-host.ts [port]
//
// Shape of the repro, mirroring cy-011521-59885:
//   - the client sends a message; the stub accepts it and returns a queue id
//   - /queue reports that item as `delivered`, but the transcript NEVER gains
//     the matching user turn — so `correlatePending` keeps the optimistic
//     bubble forever (`awaitTranscript`) with a serverQueueID attached
//   - DELETE on that id answers with whatever `deleteStatus` is set to, so the
//     same running app can be driven through the 409 and 404 cases
//
// Control endpoints (curl from the test driver):
//   POST /__delete_status/409   -> DELETE answers 409 (message still committed)
//   POST /__delete_status/404   -> DELETE answers 404 (host never heard of it)
//   POST /__delete_status/200   -> DELETE answers 200 and drops the queue row
//   GET  /__state               -> { deleteStatus, queue, deletes }
//
// Every request is logged to stdout AND appended to ./stub-host.log so a
// backgrounded run is never a silent hang.

const PORT = Number(process.argv[2] ?? 8802)
const LOG = new URL("./stub-host.log", import.meta.url).pathname
const SID = "11111111-2222-3333-4444-555555555555"
const BOOT = Date.now()

function log(line: string) {
  const stamped = `${new Date().toISOString()} ${line}`
  console.log(stamped)
  try {
    require("fs").appendFileSync(LOG, stamped + "\n")
  } catch {}
}

const session = {
  sessionId: SID,
  title: "Undeletable queued repro",
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

// The transcript deliberately never gains the sent turn — that is what keeps
// the optimistic bubble on screen and makes Remove the only way out.
const messages = [
  { id: "m1", role: "user", kind: "text", text: "hello from the stub", ts: BOOT },
  { id: "m2", role: "assistant", kind: "text", text: "Stub host reporting for duty.", ts: BOOT + 1000 },
]

type QueueRow = { id: string; text: string; status: string; attempts: number; createdAt: number; updatedAt: number }
let queue: QueueRow[] = []
let deleteStatus = 409
const deletes: Array<{ at: number; id: string; answered: number }> = []

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
    if (p === `/api/sessions/${SID}/queue` && req.method === "GET") {
      return json({ id: SID, queue })
    }

    if (p === `/api/sessions/${SID}/send` && req.method === "POST") {
      const body = (await req.json().catch(() => ({}))) as any
      const row: QueueRow = {
        id: `deadbeef0000000${queue.length + 1}`,
        text: body?.text ?? "",
        // `delivered` + a transcript that never shows the turn is exactly the
        // state the real host left cy-011521-59885 in.
        status: "delivered",
        attempts: 1,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      }
      queue.push(row)
      log(`>>> SEND RECEIVED clientId=${body?.clientId} qid=${row.id} text=${JSON.stringify(row.text)}`)
      session.lastActivityAt = Date.now()
      return json({ ok: true, clientId: body?.clientId, queued: { id: row.id, status: row.status } })
    }

    {
      const m = p.match(new RegExp(`^/api/sessions/${SID}/queue/([0-9a-f]+)$`))
      if (m && req.method === "DELETE") {
        deletes.push({ at: Date.now(), id: m[1], answered: deleteStatus })
        log(`>>> DELETE queue/${m[1]} -> ${deleteStatus}`)
        if (deleteStatus === 200) {
          queue = queue.filter((r) => r.id !== m[1])
          return json({ ok: true })
        }
        if (deleteStatus === 404) return json({ error: "queued message not found" }, 404)
        return json({ error: "message is in-flight or already queued with the agent" }, 409)
      }
    }

    if (p.startsWith("/__delete_status/") && req.method === "POST") {
      deleteStatus = Number(p.split("/").pop())
      log(`>>> deleteStatus := ${deleteStatus}`)
      return json({ ok: true, deleteStatus })
    }
    if (p === "/__state") return json({ deleteStatus, queue, deletes })

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

log(`stub host listening on :${PORT} sid=${SID} deleteStatus=${deleteStatus}`)
