// Tiny controllable mock of the lfg host, just enough for SessionStore.refresh().
// GET /api/sessions -> 200 {sessions:[]} normally, or 503 when `fail` is on.
// POST /__fail / /__ok toggle the failure flag so we can simulate a transient
// blip vs a sustained outage while the real iOS poll runs.
import { serve } from "bun";

let fail = false;

serve({
  port: 8791,
  fetch(req) {
    const url = new URL(req.url);
    if (url.pathname === "/__fail") { fail = true; return new Response("fail on\n"); }
    if (url.pathname === "/__ok")   { fail = false; return new Response("fail off\n"); }
    if (url.pathname === "/api/sessions") {
      if (fail) return new Response("mock outage", { status: 503 });
      return Response.json({ sessions: [] });
    }
    // Everything else the client may poll (users/dirs/usage/repos) -> empty-ish OK
    // so a healthy poll fully succeeds.
    if (url.pathname === "/api/users")  return Response.json({ users: [] });
    if (url.pathname === "/api/repos")  return Response.json({ repos: [] });
    if (url.pathname === "/api/dirs")   return Response.json({ dirs: [], root: "/mock", inbox: "" });
    if (url.pathname === "/api/claude/usage") return Response.json({});
    return new Response("ok");
  },
});
console.log("mock lfg host on :8791");
