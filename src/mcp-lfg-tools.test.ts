import { test, expect, beforeEach, afterAll } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { lfgTools, formatSessionList, sessionState, type LfgSession } from "./mcp-lfg-tools.ts";
import type { McpTool, ToolResult } from "./mcp-server.ts";

// ---- a fake lfg ------------------------------------------------------------------

type Call = { method: string; path: string; body: any };
type Route = (call: Call) => { status?: number; json?: unknown } | undefined;

const home = realpathSync(mkdtempSync(join(tmpdir(), "mcp-tools-")));
afterAll(() => rmSync(home, { recursive: true, force: true }));
for (const d of ["dev/app/.git", "dev/app/.claude", "dev/inbox", "inbox", "Downloads"]) mkdirSync(join(home, d), { recursive: true });
writeFileSync(join(home, "dev/app/report.md"), "# Report\nall good\n");
writeFileSync(join(home, "dev/app/big.txt"), "x".repeat(3000));
writeFileSync(join(home, "dev/app/.env"), "KEY=1\n");
writeFileSync(join(home, "dev/app/.git/config"), "[core]\n");
writeFileSync(join(home, "dev/app/.claude/plan.md"), "plan\n");
writeFileSync(join(home, "dev/app/shot.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 1, 2]));
writeFileSync(join(home, "dev/app/blob.bin"), Buffer.from([1, 0, 2, 0, 3]));

const A = "aaaaaaaa-1111-2222-3333-444444444444";
const B = "bbbbbbbb-1111-2222-3333-444444444444";
const NOW = 1_800_000_000_000;

let calls: Call[];
let routes: Route[];
let clock: number;

function tools(extra: Partial<Parameters<typeof lfgTools>[0]> = {}): Record<string, McpTool> {
  const fake = (async (url: string, init?: RequestInit) => {
    const u = new URL(url);
    const call: Call = { method: init?.method ?? "GET", path: u.pathname + u.search, body: init?.body ? JSON.parse(String(init.body)) : null };
    calls.push(call);
    for (const r of routes) {
      const hit = r(call);
      if (hit) return new Response(JSON.stringify(hit.json ?? {}), { status: hit.status ?? 200 });
    }
    return new Response(JSON.stringify({ error: `no route ${call.method} ${call.path}` }), { status: 404 });
  }) as unknown as typeof fetch;
  const list = lfgTools({
    base: "http://lfg",
    fetch: fake,
    home,
    now: () => clock,
    sleep: async (ms) => {
      clock += ms;
    },
    waitPollMs: 4000,
    waitGraceMs: 8000,
    ...extra,
  });
  return Object.fromEntries(list.map((t) => [t.name, t]));
}

const get = (path: string | RegExp, json: unknown | ((c: Call) => unknown), status = 200): Route => (c) =>
  c.method === "GET" && (typeof path === "string" ? c.path === path : path.test(c.path))
    ? { status, json: typeof json === "function" ? (json as (c: Call) => unknown)(c) : json }
    : undefined;
const post = (path: string, json: unknown = { ok: true }, status = 200): Route => (c) =>
  c.method === "POST" && c.path === path ? { status, json } : undefined;

const txt = (r: ToolResult) => r.content.map((c) => (c.type === "text" ? c.text : `[image ${c.mimeType}]`)).join("\n");

const session = (over: Partial<LfgSession> = {}): LfgSession => ({
  sessionId: A,
  title: "Fix login",
  agent: "claude",
  cwd: join(home, "dev/app"),
  tmuxTarget: "lfg-1:0.0",
  busy: false,
  lastActivityAt: NOW - 5 * 60_000,
  startedAt: NOW - 3600_000,
  ...over,
});

beforeEach(() => {
  calls = [];
  routes = [];
  clock = NOW;
});

// ---- formatting --------------------------------------------------------------------

test("sessionState follows the client's precedence", () => {
  expect(sessionState({ closed: true, prompt: {}, busy: true })).toBe("closed");
  expect(sessionState({ prompt: { question: "?" }, busy: true })).toBe("needs input");
  expect(sessionState({ status: "blocked", busy: true })).toBe("blocked");
  expect(sessionState({ busy: true })).toBe("working");
  expect(sessionState({})).toBe("idle");
});

test("formatSessionList keeps only driveable work sessions, newest first, with ~ paths", () => {
  const out = formatSessionList(
    [
      session({ sessionId: A, title: "Old", agent: "codex", lastActivityAt: NOW - 3 * 3600_000 }),
      session({ sessionId: B, title: "New", busy: true, lastActivityAt: NOW - 5 * 60_000 }),
      session({ sessionId: "ghost", title: "Ghost", tmuxTarget: null }),
      session({ sessionId: "bot", title: "Bot", cwd: "/private/var/folders/T/lfg-autopilot-claude-cwd-1" }),
    ],
    NOW,
    home,
  );
  expect(out).toBe(
    "2 live coding session(s) on this Mac:\n" +
      `- New [claude, working, active 5m ago] ~/dev/app id=${B}\n` +
      `- Old [codex, idle, active 3h ago] ~/dev/app id=${A}`,
  );
});

// ---- reading sessions ----------------------------------------------------------------

test("list_sessions filters by state, merges duplicate rows, and adds closed sessions on request", async () => {
  routes.push(
    get("/api/sessions", {
      sessions: [session({ tmuxTarget: null }), session(), session({ sessionId: B, title: "Deploy", busy: true })],
    }),
    get(/^\/api\/sessions\/resumable\?/, { sessions: [{ sessionId: "cccccccc-1111-2222-3333-444444444444", title: "Done thing", agent: "codex", cwd: join(home, "dev/app"), lastActivityAt: NOW - 86400_000 }] }),
  );
  const t = tools();
  const all = txt(await t.list_sessions!.run({}));
  expect(all).toContain("2 live coding session(s)");
  expect(all.match(/Fix login/g)?.length).toBe(1);
  const working = txt(await t.list_sessions!.run({ state: "working" }));
  expect(working).toContain("Deploy");
  expect(working).not.toContain("Fix login");
  const withClosed = txt(await t.list_sessions!.run({ include_closed: true, limit: 5 }));
  expect(withClosed).toContain("Recently closed (1):");
  expect(withClosed).toContain("Done thing [codex, closed");
  const resumable = calls.find((c) => c.path.startsWith("/api/sessions/resumable"))!;
  expect(resumable.path).toContain("limit=5");
  expect(resumable.path).toContain("exclude=");
  await expect(t.list_sessions!.run({ state: "asleep" })).rejects.toThrow("state must be one of");
});

test("get_session shows the waiting question, undelivered messages, and the latest reply", async () => {
  routes.push(
    get("/api/sessions", {
      sessions: [
        session({
          prompt: {
            question: "Which database?",
            header: "DB",
            context: "I found two options.",
            options: [
              { index: 1, label: "Postgres", description: "Managed" },
              { index: 2, label: "SQLite" },
            ],
          },
        }),
      ],
    }),
    get(`/api/sessions/${A}/messages?limit=40`, {
      messages: [
        { role: "user", kind: "text", text: "set up the db", ts: NOW - 60_000 },
        { role: "assistant", kind: "tool_use", text: "Bash: ls" },
        { role: "assistant", kind: "text", text: "Two choices; asking.", ts: NOW - 30_000 },
      ],
    }),
    get(`/api/sessions/${A}/queue`, { queue: [{ id: "1", text: "old", status: "delivered" }, { id: "2", text: "use postgres", status: "queued" }] }),
  );
  const out = txt(await tools().get_session!.run({ session_id: A }));
  expect(out).toStartWith("Fix login — needs input");
  expect(out).toContain("Question (DB): Which database?");
  expect(out).toContain("  1. Postgres — Managed");
  expect(out).toContain("  2. SQLite");
  expect(out).toContain("[queued] use postgres");
  expect(out).not.toContain("[delivered]");
  expect(out).toContain("Last message to it (1m ago): set up the db");
  expect(out).toContain("Two choices; asking.");
});

test("get_session reports a closed session from its transcript, and an unknown id as an error", async () => {
  routes.push(
    get("/api/sessions", { sessions: [] }),
    get(`/api/sessions/${A}/messages?limit=40`, { messages: [{ role: "assistant", kind: "text", text: "All done.", ts: NOW - 7200_000 }] }),
    get(`/api/sessions/${A}/transcript-status`, { found: true, agent: "codex", cwd: join(home, "dev/app"), lastActivityAt: NOW - 7200_000 }),
    get(`/api/sessions/${B}/messages?limit=40`, { error: "session transcript not found" }, 404),
    get(`/api/sessions/${B}/transcript-status`, { found: false }),
  );
  const t = tools();
  const closed = txt(await t.get_session!.run({ session_id: A }));
  expect(closed).toContain("is closed (not running)");
  expect(closed).toContain("codex · folder ~/dev/app · last activity 2h ago");
  expect(closed).toContain("All done.");
  const unknown = await t.get_session!.run({ session_id: B });
  expect(unknown.isError).toBe(true);
});

test("session ids are validated before they reach a URL", async () => {
  await expect(tools().get_session!.run({ session_id: "../../api/term" })).rejects.toThrow("session_id must be");
  expect(calls).toEqual([]);
});

test("wait_for_session returns when the turn ends, but not before the startup grace", async () => {
  // idle, idle (inside the 8 s grace) → working → idle (settled)
  const states = [false, false, true, false];
  let n = 0;
  routes.push(
    get("/api/sessions", () => ({ sessions: [session({ busy: states[Math.min(n++, states.length - 1)] })] })),
    get(/\/messages\?limit=40$/, { messages: [{ role: "assistant", kind: "text", text: "Tests pass.", ts: NOW }] }),
    get(/\/queue$/, { queue: [] }),
  );
  const out = txt(await tools().wait_for_session!.run({ session_id: A, timeout_seconds: 30 }));
  expect(out).toStartWith("Done waiting after 12s: idle.");
  expect(out).toContain("Tests pass.");
});

test("wait_for_session gives up at the timeout and says it is still working", async () => {
  routes.push(
    get("/api/sessions", { sessions: [session({ busy: true })] }),
    get(/\/messages\?limit=40$/, { messages: [] }),
    get(/\/queue$/, { queue: [] }),
  );
  const out = txt(await tools().wait_for_session!.run({ session_id: A, timeout_seconds: 10 }));
  expect(out).toStartWith("Still working after 8s.");
});

test("wait_for_session returns at once when a question appears", async () => {
  routes.push(
    get("/api/sessions", { sessions: [session({ prompt: { question: "Ship it?", options: [{ index: 1, label: "Yes" }] } })] }),
    get(/\/messages\?limit=40$/, { messages: [] }),
    get(/\/queue$/, { queue: [] }),
  );
  const out = txt(await tools().wait_for_session!.run({ session_id: A }));
  expect(out).toStartWith("Done waiting after 0s: needs input.");
});

test("get_transcript pages backward, hides tool noise by default, and hands back a cursor", async () => {
  routes.push(
    get(/\/messages\?page=backward/, {
      total: 500,
      nextBefore: 460,
      messages: [
        { role: "user", kind: "text", text: "run the tests" },
        { role: "assistant", kind: "thinking", text: "(thinking)" },
        { role: "assistant", kind: "tool_use", text: "Bash: bun test" },
        { role: "user", kind: "tool_result", text: "10 pass" },
        { role: "assistant", kind: "text", text: "All 10 pass." },
      ],
    }),
  );
  const t = tools();
  const plain = txt(await t.get_transcript!.run({ session_id: A, limit: 2, before: 500 }));
  expect(calls[0]!.path).toBe(`/api/sessions/${A}/messages?page=backward&limit=40&before=500`);
  expect(plain).toContain("2 message line(s) from 5 of 500 entries");
  expect(plain).toContain("call again with before=460");
  expect(plain).toContain("Eugene: run the tests\nAgent: All 10 pass.");
  expect(plain).not.toContain("[tool]");
  calls = [];
  const withTools = txt(await t.get_transcript!.run({ session_id: A, include_tools: true, limit: 5 }));
  expect(calls[0]!.path).toBe(`/api/sessions/${A}/messages?page=backward&limit=5`);
  expect(withTools).toContain("  [tool] Bash: bun test\n  [result] 10 pass");
});

test("get_transcript reads further back when a page is all tool calls", async () => {
  routes.push(
    get(/before=100$/, { total: 300, nextBefore: null, messages: [{ role: "assistant", kind: "text", text: "Earlier reply." }] }),
    get(/\/messages\?page=backward&limit=40$/, {
      total: 300,
      nextBefore: 100,
      messages: Array.from({ length: 40 }, () => ({ role: "assistant", kind: "tool_use", text: "Read: x" })),
    }),
  );
  const out = txt(await tools().get_transcript!.run({ session_id: A, limit: 5 }));
  expect(calls.map((c) => c.path.split("?")[1])).toEqual(["page=backward&limit=40", "page=backward&limit=40&before=100"]);
  expect(out).toContain("1 message line(s) from 41 of 300 entries");
  expect(out).toContain("Agent: Earlier reply.");
  expect(out).not.toContain("call again");
});

// ---- acting on sessions ----------------------------------------------------------------

test("start_session posts the resolved folder and creates a one-off ~/dev/inbox folder", async () => {
  routes.push(post("/api/sessions/new", { ok: true, sessionId: B, cwd: join(home, "dev/inbox/price-check"), agent: "codex" }));
  const out = txt(await tools().start_session!.run({ prompt: "compare prices", folder: "~/dev/inbox/price-check", agent: "codex" }));
  expect(existsSync(join(home, "dev/inbox/price-check"))).toBe(true);
  expect(calls[0]!.body).toEqual({ prompt: "compare prices", cwd: join(home, "dev/inbox/price-check"), agent: "codex" });
  expect(out).toContain(`session_id=${B}`);
});

test("start_session defaults to ~/dev/inbox and no longer creates folders under ~/inbox", async () => {
  routes.push(post("/api/sessions/new", { ok: true, sessionId: B, cwd: join(home, "dev/inbox"), agent: "claude" }));
  const t = tools();
  await t.start_session!.run({ prompt: "quick task" });
  expect(calls[0]!.body).toEqual({ prompt: "quick task", cwd: join(home, "dev/inbox"), agent: "claude" });
  await expect(t.start_session!.run({ prompt: "x", folder: "~/inbox/new-thing" })).rejects.toThrow("no such file");
  expect(existsSync(join(home, "inbox/new-thing"))).toBe(false);
});

test("start_session refuses folders outside the allowed roots and unknown agents", async () => {
  const t = tools();
  await expect(t.start_session!.run({ prompt: "x", folder: "/etc" })).rejects.toThrow("outside");
  await expect(t.start_session!.run({ prompt: "x", folder: "~/dev/inbox/a/b" })).rejects.toThrow("no such file");
  await expect(t.start_session!.run({ prompt: "x", agent: "gemini" })).rejects.toThrow("agent must be");
  expect(calls).toEqual([]);
});

test("send_message queues text with a client id, and reports a resume with the new id", async () => {
  routes.push(post(`/api/sessions/${A}/send`, { ok: true, msg: { status: "queued" } }));
  const t = tools();
  expect(txt(await t.send_message!.run({ session_id: A, text: "  also add tests " }))).toContain("Sent (queued)");
  expect(calls[0]!.body.text).toBe("also add tests");
  expect(typeof calls[0]!.body.clientId).toBe("string");
  routes.unshift(post(`/api/sessions/${A}/send`, { ok: true, resumed: true, sessionId: B }));
  expect(txt(await t.send_message!.run({ session_id: A, text: "hi" }))).toContain(`New session_id=${B}`);
});

test("answer_question maps a number or a label to the option index", async () => {
  const prompt = { question: "Which?", options: [{ index: 1, label: "Postgres" }, { index: 2, label: "SQLite" }] };
  routes.push(get("/api/sessions", { sessions: [session({ prompt })] }), post(`/api/sessions/${A}/answer`));
  const t = tools();
  expect(txt(await t.answer_question!.run({ session_id: A, option: "2" }))).toContain("with 2. SQLite");
  expect(calls.at(-1)!.body).toEqual({ index: 2 });
  await t.answer_question!.run({ session_id: A, option: "postg" });
  expect(calls.at(-1)!.body).toEqual({ index: 1 });
  const bad = await t.answer_question!.run({ session_id: A, option: "5" });
  expect(bad.isError).toBe(true);
  expect(txt(bad)).toContain("1. Postgres");
});

test("answer_question refuses when nothing is asked, and for a phone sign-in prompt", async () => {
  routes.push(get("/api/sessions", { sessions: [session(), session({ sessionId: B, prompt: { source: "phone-sign-in", question: "Sign in to x", options: [] } })] }));
  const t = tools();
  expect((await t.answer_question!.run({ session_id: A, option: "1" })).isError).toBe(true);
  const signIn = await t.answer_question!.run({ session_id: B, option: "1" });
  expect(txt(signIn)).toContain("iPhone");
  expect(calls.some((c) => c.method === "POST")).toBe(false);
});

test("interrupt, close and resume call the matching lfg endpoints", async () => {
  routes.push(
    post(`/api/sessions/${A}/interrupt`, { ok: true, stopped: true }),
    post(`/api/sessions/${A}/close`),
    post("/api/sessions/resume", { ok: true, sessionId: B, cwd: join(home, "dev/app"), resumedFrom: A }),
  );
  const t = tools();
  expect(txt(await t.interrupt_session!.run({ session_id: A }))).toStartWith("Stopped.");
  expect(txt(await t.close_session!.run({ session_id: A }))).toBe(`Closed session ${A}.`);
  const resumed = txt(await t.resume_session!.run({ session_id: A, prompt: "continue" }));
  expect(calls.at(-1)!.body).toEqual({ sessionId: A, prompt: "continue" });
  expect(resumed).toContain(`session_id=${B} (new id`);
});

test("lfg errors surface as thrown messages the protocol layer turns into tool errors", async () => {
  routes.push(post(`/api/sessions/${A}/close`, { error: "session is not in a tmux pane — cannot close" }, 409));
  await expect(tools().close_session!.run({ session_id: A })).rejects.toThrow("cannot close");
});

// ---- files -------------------------------------------------------------------------------

test("list_session_files lists readable files from the whole transcript, newest mention first", async () => {
  routes.push(
    get(`/api/sessions/${A}/messages?full=1`, {
      messages: [
        { role: "assistant", kind: "text", text: `Plan in ~/dev/app/.claude/plan.md and secrets in ${home}/dev/app/.env` },
        { role: "assistant", kind: "tool_use", text: `Write: {"file_path":"${home}/dev/app/report.md"}` },
        { role: "assistant", kind: "text", text: `Done: ${home}/dev/app/report.md and ${home}/dev/app/gone.md, folder ${home}/dev/app` },
      ],
    }),
  );
  const out = txt(await tools().list_session_files!.run({ session_id: A }));
  const lines = out.split("\n").filter((l) => l.startsWith("- "));
  expect(lines.map((l) => l.split(" (")[0])).toEqual(["- ~/dev/app/report.md", "- ~/dev/app/.claude/plan.md"]);
  expect(out).toContain("1 more mentioned file(s) are withheld");
});

/** A transcript that mentions some files in the fixture home. */
function mentionRoute(...paths: string[]): Route {
  return get(`/api/sessions/${A}/messages?full=1`, {
    messages: [{ role: "assistant", kind: "text", text: `Made ${paths.map((p) => `${home}/${p}`).join(" and ")}.` }],
  });
}

test("read_file returns text, truncates large files, sends images, and refuses secrets and binaries", async () => {
  routes.push(mentionRoute("dev/app/report.md", "dev/app/big.txt", "dev/app/shot.png", "dev/app/.env", "dev/app/blob.bin"));
  const t = tools();
  const md = txt(await t.read_file!.run({ session_id: A, path: "~/dev/app/report.md" }));
  expect(md).toContain("~/dev/app/report.md (");
  expect(md).toContain("# Report\nall good");
  const big = txt(await t.read_file!.run({ session_id: A, path: "~/dev/app/big.txt", max_kb: 1 }));
  expect(big).toContain("[truncated: showed 1.0 KB of 2.9 KB");
  const img = await t.read_file!.run({ session_id: A, path: `${home}/dev/app/shot.png` });
  expect(img.content[1]).toEqual({ type: "image", data: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 1, 2]).toString("base64"), mimeType: "image/png" });
  expect(txt(await t.read_file!.run({ session_id: A, path: "~/dev/app/.env" }))).toContain("secrets");
  expect(txt(await t.read_file!.run({ session_id: A, path: "~/dev/app/blob.bin" }))).toContain("binary file");
});

test("read_file downscales an image over 4 MB to a JPEG instead of refusing it", async () => {
  // A real PNG well over the limit: random noise does not compress.
  const big = join(home, "dev/app/huge.png");
  const w = 1400, h = 1100;
  await Bun.$`python3 -c ${`import os,struct,zlib
w,h=${w},${h}
raw=b''.join(b'\\x00'+os.urandom(w*3) for _ in range(h))
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
open('${big}','wb').write(b'\\x89PNG\\r\\n\\x1a\\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,0))+chunk(b'IEND',b''))`}`.quiet();
  routes.push(mentionRoute("dev/app/huge.png"));
  const r = await tools().read_file!.run({ session_id: A, path: big });
  expect(txt(r)).toContain("sent downscaled to");
  const img = r.content[1] as { type: string; mimeType: string; data: string };
  expect(img.mimeType).toBe("image/jpeg");
  expect(Buffer.from(img.data, "base64").length).toBeLessThan(4 * 1024 * 1024);
});

test("read_file refuses a file the session never mentioned, and needs a session id", async () => {
  routes.push(mentionRoute("dev/app/report.md"));
  const t = tools();
  const r = await t.read_file!.run({ session_id: A, path: "~/dev/app/big.txt" });
  expect(r.isError).toBe(true);
  expect(txt(r)).toContain("never mentioned");
  await expect(t.read_file!.run({ path: "~/dev/app/report.md" })).rejects.toThrow("session_id");
});

test("the folder browser is gone: file access is per session only", () => {
  const names = Object.keys(tools());
  expect(names).not.toContain("list_directory");
  expect(names).toContain("list_session_files");
  expect(names).toContain("read_file");
});
