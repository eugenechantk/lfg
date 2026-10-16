// A stand-in "Air" host for the desktop DF5 probe: one live session, nothing else.
// Never a real lfg serve (that would push real APNs and write leases).
const now = Date.now();
const session = {
  agent: "codex",
  pid: 4242,
  cwd: "/Users/eugenechan/dev/personal/lfg",
  project: "lfg",
  title: "Weekly dependency audit",
  sessionId: "stub-air-audit",
  busy: false,
  lastActivityAt: now - 2 * 86_400_000,
  tmuxName: "lfg-stub-audit",
  model: null,
  status: null,
  task: { id: "stub-task", name: "Weekly dependency audit" },
};
Bun.serve({
  port: 8797,
  hostname: "127.0.0.1",
  fetch(req) {
    const path = new URL(req.url).pathname;
    console.log(new Date().toISOString(), req.method, path);
    if (path === "/api/info") return Response.json({ hostId: "stub-air", hostName: "Air" });
    if (path === "/api/sessions") return Response.json({ sessions: [session] });
    if (path === "/api/session-states") return Response.json({ needsInputSessionIds: [] });
    if (path === "/api/sessions/resumable") return Response.json({ sessions: [], nextBefore: null, total: 0 });
    return new Response("not found", { status: 404 });
  },
});
console.log("stub air on 8797");
