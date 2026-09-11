// Disposable local acceptance fixture. Synthetic credentials only; never touches LFG data.
import { chromium } from "playwright-core";
import {
  BrowserSignInHub,
  signInHTTP,
  allowsSignInAdapter,
} from "../src/browser-sign-in.ts";
import { connectPhoneSignIn } from "../src/browser-sign-in-playwright.ts";
import { execFileSync } from "node:child_process";
try {
  const text = execFileSync("lsof", ["-nP", "-iTCP:9982", "-sTCP:LISTEN"], {
    encoding: "utf8",
  });
  if (text.trim()) throw Error("Port 9982 is occupied");
} catch (e: any) {
  if (e.status !== 1) throw e;
}
const token = "b".repeat(64),
  hub = new BrowserSignInHub(() => token);
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const startedAt = Date.now();
const sid = "11111111-1111-4111-8111-111111111111";
const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 9982,
  idleTimeout: 240,
  async fetch(req, server) {
    const url = new URL(req.url),
      path = url.pathname;
    if (path === "/api/browser-sign-in/adapter") {
      if (!allowsSignInAdapter(req)) return new Response("", { status: 403 });
      return server.upgrade(req)
        ? undefined
        : new Response("", { status: 400 });
    }
    if (path.startsWith("/api/browser-sign-in/")) return signInHTTP(req, hub);
    if (path === "/fixture/login")
      return new Response(
        `<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font:18px system-ui;padding:24px}input,button{display:block;font:inherit;padding:12px;margin:12px 0;width:90%}</style><h1>Test portal</h1><p>Synthetic credentials only.</p><form action="/fixture/auth" method="post"><label>Email<input name="email" type="email" autocomplete="username"></label><label>Password<input name="password" type="password" autocomplete="current-password"></label><button>Sign in</button></form>`,
        { headers: { "Content-Type": "text/html" } },
      );
    if (path === "/fixture/auth" && req.method === "POST")
      return new Response(null, {
        status: 303,
        headers: {
          Location: "/fixture/account",
          "Set-Cookie":
            "fixture_session=synthetic-login; Path=/; HttpOnly; SameSite=Lax",
        },
      });
    if (path === "/fixture/account") {
      const loggedIn = req.headers
        .get("cookie")
        ?.includes("fixture_session=synthetic-login");
      return new Response(
        `<meta name="viewport" content="width=device-width, initial-scale=1"><h1>${loggedIn ? "Signed in to test portal" : "Sign-in required"}</h1><p>${loggedIn ? "Tap Review in LFG to transfer this test login." : "No login cookie."}</p>`,
        {
          status: loggedIn ? 200 : 401,
          headers: { "Content-Type": "text/html" },
        },
      );
    }
    if (path === "/fixture/status")
      return Response.json({
        installed: (await context.cookies()).some(
          (c) => c.name === "fixture_session" && c.value === "synthetic-login",
        ),
      });
    if (path === "/fixture/disconnect" && req.method === "POST") {
      bridge.close();
      return Response.json({ ok: true });
    }
    if (path === "/api/sessions")
      return Response.json({
        sessions: [
          {
            sessionId: sid,
            title: "Phone sign-in test",
            agent: "claude",
            project: "Sign-in fixture",
            cwd: "/tmp/lfg-sign-in-fixture",
            busy: false,
            closed: false,
            lastActivityAt: startedAt,
          },
        ],
      });
    if (path === "/api/sessions/resumable")
      return Response.json({ sessions: [] });
    if (path.endsWith("/messages"))
      return Response.json({ messages: [], total: 0 });
    if (path.endsWith("/queue")) return Response.json({ queue: [] });
    if (path === "/api/users") return Response.json({ users: [] });
    if (path === "/api/events") {
      let timer: ReturnType<typeof setInterval>;
      return new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(": fixture\n\n"));
          timer = setInterval(() => controller.enqueue(new TextEncoder().encode(": hb\n\n")), 10000);
        },
        cancel() { clearInterval(timer); }
      }), { headers: { "Content-Type": "text/event-stream" } });
    }
    if (path === "/api/events/page") return Response.json({events:[],head:0});
    return Response.json({});
  },
  websocket: {
    open: (s) => hub.open(s),
    message: (s, m) => hub.message(s, m),
    close: (s) => hub.close(s),
  },
});
const bridge = connectPhoneSignIn(context, {
  token,
  name: "Playwright test browser",
  baseURL: "http://127.0.0.1:9982",
});
console.log(
  "Fixture ready on http://127.0.0.1:9982 · login /fixture/login · status /fixture/status",
);
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, async () => {
    bridge.close();
    hub.dispose();
    server.stop(true);
    await browser.close();
    process.exit(0);
  });
