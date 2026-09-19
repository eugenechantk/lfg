import type { BrowserContext } from "playwright-core";
import { readSignInToken, validateTransfer } from "./browser-sign-in.ts";

/** Attach to the context the agent ALREADY uses; close() disconnects only this bridge. */
export function connectPhoneSignIn(
  context: BrowserContext,
  options: {
    name: string;
    baseURL?: string;
    token?: string;
    onStatus?: (status: "connected" | "disconnected") => void;
  },
) {
  const base = new URL(options.baseURL || "http://127.0.0.1:8766");
  if (
    !["localhost", "127.0.0.1", "[::1]"].includes(base.hostname) ||
    !["http:", "https:"].includes(base.protocol) ||
    base.username ||
    base.password
  )
    throw Error("Browser bridge must connect to loopback LFG.");
  const token = options.token || readSignInToken();
  if (!token) throw Error("Run browser-sign-in-setup.ts first.");
  base.pathname = "/api/browser-sign-in/adapter";
  base.search = "";
  base.hash = "";
  base.protocol = base.protocol === "https:" ? "wss:" : "ws:";
  let closed = false,
    socket: WebSocket | undefined,
    timer: ReturnType<typeof setTimeout> | undefined,
    heartbeat: ReturnType<typeof setInterval> | undefined,
    busy = false;
  function connect() {
    if (closed) return;
    const ws = new WebSocket(base);
    socket = ws;
    ws.onopen = () => {
      ws.send(
        JSON.stringify({
          type: "hello",
          name: options.name,
          kind: "playwright",
          token,
        }),
      );
      heartbeat = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send('{"type":"ping"}');
      }, 20000);
    };
    ws.onmessage = async (event) => {
      try {
        if (typeof event.data !== "string" || event.data.length > 262144) {
          ws.close();
          return;
        }
        const job = JSON.parse(event.data);
        if (job.type === "ready") {
          options.onStatus?.("connected");
          return;
        }
        if (job.type !== "import") return;
        let installed = 0,
          uncertain = false,
          reason;
        if (
          !busy &&
          Number.isFinite(job.deadline) &&
          job.deadline > Date.now()
        ) {
          busy = true;
          try {
            const transfer = validateTransfer(job);
            for (const c of transfer.cookies) {
              if (
                closed ||
                ws.readyState !== WebSocket.OPEN ||
                Date.now() >= job.deadline
              ) {
                uncertain = true;
                reason = "deadline";
                break;
              }
              const { hostOnly, ...cookie } = c;
              try {
                await context.addCookies([cookie]);
              } catch (error) {
                reason = `set-rejected:${c.name}@${c.domain}:${(error as Error)?.message ?? "unknown"}`;
                throw error;
              }
              // Cookie jar readback checks delivery without navigating or touching agent pages.
              const values = await context.cookies();
              if (
                !values.some(
                  (v) =>
                    v.name === c.name &&
                    v.value === c.value &&
                    v.domain === c.domain &&
                    v.path === c.path,
                )
              ) {
                uncertain = true;
                reason = `set-mismatch:${c.name}@${c.domain}`;
                break;
              }
              installed++;
            }
          } catch (error) {
            uncertain = true;
            reason ??= `invalid-transfer:${(error as Error)?.message ?? "unknown"}`;
          } finally {
            busy = false;
          }
        }
        if (ws.readyState === WebSocket.OPEN)
          ws.send(
            JSON.stringify({
              type: "result",
              id: job.id,
              installed,
              uncertain,
              ...(reason ? { reason } : busy ? { reason: "busy" } : {}),
            }),
          );
      } catch {
        ws.close();
      }
    };
    ws.onerror = () => ws.close();
    ws.onclose = () => {
      clearInterval(heartbeat);
      options.onStatus?.("disconnected");
      if (!closed) timer = setTimeout(connect, 3000);
    };
  }
  function close() {
    closed = true;
    clearTimeout(timer);
    clearInterval(heartbeat);
    socket?.close();
    context.off("close", close);
  }
  context.on("close", close);
  connect();
  return { close };
}
