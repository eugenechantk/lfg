/** Isolated client acceptance fixture using the production ranking and pager. */
import { appendFileSync, mkdirSync } from "node:fs";
import { rankSessions, RankedSearchPager } from "../../src/ranked-session-search";
import type { IndexEntry } from "../../src/session-index";

const port = 18967;
const evidence = new URL("../evidence/directory-first-search/", import.meta.url).pathname;
mkdirSync(evidence, { recursive: true });
const now = Date.now();
const old = now - 10 * 7 * 86400_000;
const entries: IndexEntry[] = [
  { sessionId: "directory-old", title: "Ochre", cwd: "/work/ochre", mtime: old },
  { sessionId: "directory-new", title: "Recent directory work", cwd: "/work/ochre", mtime: now - 60_000 },
  { sessionId: "title-old", title: "Ochre", cwd: "/work/other", mtime: old },
  { sessionId: "title-new", title: "Recent ochre discussion", cwd: "/work/other", mtime: now - 30_000 },
  { sessionId: "prose-new", title: "Assistant prose match", cwd: "/work/other", mtime: now },
].map(row => ({ ...row, agent: "claude", path: `/fixture/${row.sessionId}.jsonl`, project: row.cwd.split("/").at(-1)!, lastUserText: "Fixture conversation", userText: "" }));
const hits = [{ sessionId: "prose-new", role: "assistant" as const, text: "The ochre proposal", rank: -10, ts: null }];
const live = [
  { sessionId: "live-title", title: "Ochre live title", cwd: "/work/other", lastActivityAt: now },
  { sessionId: "live-directory", title: "Live directory work", cwd: "/work/ochre", lastActivityAt: now - 60_000 },
].map((row, i) => ({ ...row, agent: "codex", pid: 100 + i, project: row.cwd.split("/").at(-1), busy: false, model: "gpt-6.1-sol", tmuxName: null, status: "idle", lastUserText: "Fixture live session" }));
const pager = new RankedSearchPager();
const server = Bun.serve({ port, hostname: "127.0.0.1", idleTimeout: 0, fetch(req) {
  const url = new URL(req.url);
  const route = url.pathname;
  appendFileSync(`${evidence}requests.jsonl`, JSON.stringify({ at: Date.now(), method: req.method, path: `${route}${url.search}` }) + "\n");
  if (route === "/api/events") return new Response(new ReadableStream({ start(controller) {
    controller.enqueue(new TextEncoder().encode(": fixture heartbeat\n\n"));
  }}), { headers: { "Content-Type": "text/event-stream" } });
  if (route === "/api/info") return Response.json({ hostId: "session-ui-pro", hostName: "Search fixture" });
  if (route === "/api/ping") return Response.json({ ok: true, ts: Date.now(), seq: 0 });
  if (route === "/api/sessions") return Response.json({ sessions: live });
  if (route === "/api/sessions/search") {
    const q = url.searchParams.get("q") ?? "";
    const limit = Math.min(100, Number(url.searchParams.get("limit") ?? 60));
    const cursor = url.searchParams.get("cursor");
    const page = cursor ? pager.next(cursor, q, "[]", limit)
      : pager.first(q, "[]", rankSessions(entries, hits, q), limit);
    return Response.json(page ?? { error: "Expired cursor" }, { status: page ? 200 : 410 });
  }
  if (route === "/api/sessions/resumable") return Response.json({ sessions: rankSessions(entries, hits, "ochre").sort((a,b) => b.lastActivityAt - a.lastActivityAt), total: entries.length });
  if (route === "/api/scheduled-tasks") return Response.json({ tasks: [] });
  return Response.json({ ok: true, dirs: [], repos: [], users: [], requests: [], claude: [], codex: [], messages: [], queue: [] });
}});
console.log(JSON.stringify({ port: server.port, expectedClosed: rankSessions(entries, hits, "ochre").map(row => row.sessionId) }));
