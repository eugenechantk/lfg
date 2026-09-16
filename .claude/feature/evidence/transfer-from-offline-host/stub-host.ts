// Throwaway stub lfg host for the transfer-from-offline-host live seam.
// Claims ONE session as live, logs every request, answers close with 200.
const SID = process.env.SID!;
const PORT = Number(process.env.PORT ?? 8799);
const REPO = "/Users/eugenechan/dev/personal/lfg";
const started = Date.now();
const log = (m: string) => console.log(`${new Date().toISOString()} ${m}`);
Bun.serve({
  port: PORT, hostname: "127.0.0.1",
  fetch(req) {
    const u = new URL(req.url);
    const p = u.pathname;
    log(`${req.method} ${p}`);
    const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
    if (p === "/api/info") return json({ hostId: "stub-host-0001", hostName: "stub-offline-test" });
    if (p === "/api/sessions" && req.method === "GET" && process.env.CLAIM === "0") return json({ sessions: [] });
    if (p === "/api/sessions" && req.method === "GET") return json({ sessions: [{
      agent: "claude", pid: 99999, sessionId: SID, cwd: REPO, project: "Users-eugenechan-dev-personal-lfg",
      title: "STUB transfer test (CHILDPROBE4)", lastUserText: "CHILDPROBE4 test", busy: false,
      tmuxName: "lfg-stub", tmuxTarget: "lfg-stub:0.0", startedAt: started, lastActivityAt: started,
      transcriptPath: `/Users/eugenechan/.claude/projects/-Users-eugenechan-dev-personal-lfg/${SID}.jsonl`,
    }]});
    if (p === "/api/sessions/resumable") return json({ sessions: [] });
    // Transfer TARGET role: answer the pre-flight. TS_MODE=missing|stale|fresh
    const ts = p.match(/^\/api\/sessions\/([^/]+)\/transcript-status$/);
    if (ts && req.method === "GET") {
      const mode = process.env.TS_MODE ?? "missing";
      if (mode === "missing") return json({ found: false });
      const ago = mode === "stale" ? Number(process.env.STALE_MS ?? 20 * 60_000) : 5_000;
      return json({ found: true, agent: "claude", cwd: REPO, cwdExists: true, bytes: 1234, mtimeMs: Date.now() - ago, lastActivityAt: Date.now() - ago });
    }
    if (req.method === "POST" && /^\/api\/sessions\/[^/]+\/close$/.test(p)) { log(`CLOSE ${p.split("/")[3]}`); return json({ ok: true }); }
    if (p.startsWith("/api/events") || p.startsWith("/api/sessions/")) { return new Response("nope", { status: 404 }); }
    log(`${req.method} ${p} -> 404`);
    return new Response("nope", { status: 404 });
  },
});
log(`stub up on ${PORT} claiming ${SID}`);
