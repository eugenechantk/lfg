// Throwaway stub lfg host for the desktop fork-modal live check.
// One idle claude session; POST /api/sessions/fork waits DELAY_MS, then
// answers per the `mode` file beside this script (ok | fail), read per request.
const DIR = import.meta.dir;
const PORT = Number(process.env.PORT ?? 8797);
const DELAY_MS = Number(process.env.DELAY_MS ?? 8000);
const CWD = "/Users/eugenechan/dev/personal/lfg";
const now = Date.now();
const log = (m: string) => console.log(`${new Date().toISOString()} ${m}`);
Bun.serve({
  port: PORT, hostname: "127.0.0.1", idleTimeout: 120,
  async fetch(req) {
    const p = new URL(req.url).pathname;
    log(`${req.method} ${p}`);
    const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
    if (p === "/api/info") return json({ hostId: "stub-fork-0001", hostName: "fork-stub" });
    if (p === "/api/sessions" && req.method === "GET") return json({ sessions: [{
      agent: "claude", pid: 99998, sessionId: "forkprobe-source-0001", cwd: CWD,
      project: "Users-eugenechan-dev-personal-lfg", title: "FORKPROBE source conversation",
      lastUserText: "forkprobe", busy: false, tmuxName: null, tmuxTarget: null,
      startedAt: now, lastActivityAt: now, control: "direct",
    }]});
    if (p === "/api/sessions/resumable") return json({ sessions: [] });
    if (p === "/api/sessions/fork" && req.method === "POST") {
      const body = await req.json().catch(() => null);
      const mode = (await Bun.file(`${DIR}/mode`).text()).trim();
      log(`FORK start body=${JSON.stringify(body)} mode=${mode} delay=${DELAY_MS}`);
      await Bun.sleep(DELAY_MS);
      log(`FORK reply mode=${mode}`);
      if (mode === "fail") return json({ ok: false, error: "FORKPROBE stub refused the fork" }, 502);
      return json({ ok: true, tmuxName: "lfg-forkprobe", cwd: CWD, sessionId: "forkprobe-branch-0002",
                    forkedFrom: body?.sessionId, agent: "claude" });
    }
    return new Response("nope", { status: 404 });
  },
});
log(`fork stub up on ${PORT}`);
