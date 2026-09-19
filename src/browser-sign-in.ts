import { PhoneSignInRequests } from "./phone-sign-in-requests.ts";
import { timingSafeEqual } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { parse } from "tldts";

export const SIGN_IN_MAX_BYTES = 256 * 1024;
export const signInTokenPath = () =>
  process.env.LFG_BROWSER_SIGN_IN_TOKEN_FILE ||
  join(homedir(), ".lfg", "browser-sign-in.token");
export function readSignInToken(): string | undefined {
  try {
    const token = readFileSync(signInTokenPath(), "utf8").trim();
    return /^[a-f0-9]{64}$/.test(token) ? token : undefined;
  } catch {
    return undefined;
  }
}
export interface SignInCookie {
  name: string;
  value: string;
  domain: string;
  hostOnly: boolean;
  path: string;
  secure: boolean;
  httpOnly: boolean;
  sameSite?: "Strict" | "Lax" | "None";
  expires?: number;
}
export interface SignInTransfer {
  targetId: string;
  url: string;
  domains: string[];
  cookies: SignInCookie[];
}
export interface SignInTarget {
  id: string;
  name: string;
  kind: "chrome" | "playwright";
}
export interface SignInResult {
  state: "installed" | "partial" | "failed" | "unknown";
  installed: number;
  total: number;
  /** Adapter-reported cause of the first failure: cookie name + domain, never a value. */
  reason?: string;
}
/** Adapters and history are untrusted: keep reasons short, printable and optional. */
export function signInReason(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const text = value.replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, 200);
  return text || undefined;
}
export function cookieDomain(value: string): string {
  const domain = value.replace(/^\./, "").toLowerCase();
  if (
    !/^[a-z0-9.-]+$/.test(domain) ||
    domain.length > 253 ||
    domain.endsWith(".") ||
    domain.includes("..")
  )
    throw new Error("Invalid cookie domain.");
  const parsed = parse(domain, { allowPrivateDomains: true });
  if (!parsed.domain && domain !== "localhost" && domain !== "127.0.0.1")
    throw new Error("Cookie domain must name a website.");
  return domain;
}
export function loginURL(value: string): URL {
  const url = new URL(value);
  const loopback = ["127.0.0.1", "localhost"].includes(url.hostname);
  if (
    (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) ||
    url.username ||
    url.password
  )
    throw new Error("Use an HTTPS website URL.");
  cookieDomain(url.hostname);
  return url;
}
export function validateTransfer(input: unknown): SignInTransfer {
  const p = input as SignInTransfer;
  if (
    !p ||
    typeof p.targetId !== "string" ||
    p.targetId.length > 80 ||
    typeof p.url !== "string" ||
    p.url.length > 2048
  )
    throw new Error("Invalid sign-in request.");
  loginURL(p.url);
  if (
    !Array.isArray(p.domains) ||
    !p.domains.length ||
    p.domains.length > 16 ||
    p.domains.some((d) => typeof d !== "string")
  )
    throw new Error("Choose cookie domains.");
  const domains = [...new Set(p.domains.map(cookieDomain))];
  if (!Array.isArray(p.cookies) || !p.cookies.length || p.cookies.length > 128)
    throw new Error("Choose between 1 and 128 cookies.");
  const cookies = p.cookies.map((c) => {
    if (
      !c ||
      typeof c.domain !== "string" ||
      !domains.includes(cookieDomain(c.domain)) ||
      typeof c.name !== "string" ||
      !c.name ||
      /[\s;=\x00-\x1f\x7f]/.test(c.name) ||
      typeof c.value !== "string" ||
      /[\x00-\x1f\x7f]/.test(c.value) ||
      Buffer.byteLength(c.name + c.value) > 4096 ||
      typeof c.path !== "string" ||
      !c.path.startsWith("/") ||
      c.path.length > 2048 ||
      /[\x00-\x1f\x7f]/.test(c.path) ||
      typeof c.hostOnly !== "boolean" ||
      typeof c.secure !== "boolean" ||
      typeof c.httpOnly !== "boolean"
    )
      throw new Error("Invalid cookie or unselected domain.");
    if (
      c.sameSite !== undefined &&
      !["Strict", "Lax", "None"].includes(c.sameSite)
    )
      throw new Error("Invalid SameSite value.");
    // WebKit keeps cookies a site set as SameSite=None without Secure (Apple's
    // sign-in does this); Chrome refuses that combination. Send them with no
    // SameSite attribute instead of failing the whole login for one flag.
    const sameSite = c.sameSite === "None" && !c.secure ? undefined : c.sameSite;
    if (
      c.expires !== undefined &&
      (!Number.isFinite(c.expires) || c.expires <= Date.now() / 1000)
    )
      throw new Error("Expired cookie. Sign in again.");
    if ("partitionKey" in c || "partitioned" in c)
      throw new Error("Partitioned cookies are not supported.");
    const domain = cookieDomain(c.domain);
    if (
      (c.name.startsWith("__Secure-") && !c.secure) ||
      (c.name.startsWith("__Host-") &&
        (!c.secure || !c.hostOnly || c.path !== "/"))
    )
      throw new Error("Invalid cookie security prefix.");
    return {
      name: c.name,
      value: c.value,
      domain: c.hostOnly ? domain : "." + domain,
      hostOnly: c.hostOnly,
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
      ...(sameSite ? { sameSite } : {}),
      ...(c.expires !== undefined ? { expires: c.expires } : {}),
    };
  });
  if (
    Buffer.byteLength(JSON.stringify({ cookies, domains })) >
    SIGN_IN_MAX_BYTES - 4096
  )
    throw new Error("Sign-in data too large.");
  return { targetId: p.targetId, url: p.url, domains, cookies };
}
interface Socket {
  send(value: string): unknown;
  close(code?: number, reason?: string): unknown;
}
type Peer = {
  target?: SignInTarget;
  seen: number;
  timer: ReturnType<typeof setTimeout>;
};
type Pending = {
  socket: Socket;
  total: number;
  resolve: (r: SignInResult) => void;
  timer: ReturnType<typeof setTimeout>;
};
/** Contains no retained cookie payloads. Destinations are connection-scoped; history is metadata only. */
export class BrowserSignInHub {
  readonly requests: PhoneSignInRequests;
  authenticatesAgent(req: Request): boolean {
    const secret = this.token();
    const supplied = req.headers.get("authorization")?.replace(/^Bearer /, "");
    return !!secret && !!supplied && Buffer.byteLength(secret) === Buffer.byteLength(supplied)
      && timingSafeEqual(Buffer.from(secret), Buffer.from(supplied));
  }
  private peers = new Map<Socket, Peer>();
  private pending = new Map<string, Pending>();
  constructor(
    private token: () => string | undefined = readSignInToken,
    private options: { timeout?: number; historyPath?: string } = {},
  ) { this.requests = new PhoneSignInRequests(this, Date.now, 15 * 60_000, options.historyPath); }
  open(socket: Socket) {
    if (this.peers.size >= 16) {
      socket.close(1013, "Too many browsers");
      return;
    }
    const timer = setTimeout(() => {
      this.close(socket);
      socket.close(1008, "Handshake expired");
    }, 5000);
    this.peers.set(socket, { seen: Date.now(), timer });
  }
  message(socket: Socket, raw: string | Buffer) {
    const peer = this.peers.get(socket);
    if (!peer) return;
    try {
      if (typeof raw !== "string" || Buffer.byteLength(raw) > 4096)
        throw Error();
      const m = JSON.parse(raw);
      if (!peer.target) {
        const secret = this.token();
        if (
          m.type !== "hello" ||
          !secret ||
          typeof m.token !== "string" ||
          m.token.length !== secret.length ||
          !timingSafeEqual(Buffer.from(m.token), Buffer.from(secret)) ||
          !["chrome", "playwright"].includes(m.kind) ||
          typeof m.name !== "string" ||
          !m.name.trim() ||
          m.name.length > 80 ||
          /[\x00-\x1f\x7f]/.test(m.name)
        )
          throw Error();
        peer.target = {
          id: crypto.randomUUID(),
          name: m.name.trim(),
          kind: m.kind,
        };
        socket.send(JSON.stringify({ type: "ready", target: peer.target }));
      } else if (m.type === "result") {
        const job = this.pending.get(m.id);
        if (!job || job.socket !== socket) return;
        if (
          !Number.isInteger(m.installed) ||
          m.installed < 0 ||
          m.installed > job.total
        )
          throw Error();
        const reason = signInReason(m.reason);
        this.finish(m.id, {
          state:
            m.uncertain === true
              ? "unknown"
              : m.installed === job.total
                ? "installed"
                : m.installed === 0
                  ? "failed"
                  : "partial",
          installed: m.installed,
          total: job.total,
          ...(reason ? { reason } : {}),
        });
      } else if (m.type === "ping") socket.send('{"type":"pong"}');
      else throw Error();
      clearTimeout(peer.timer);
      peer.seen = Date.now();
      peer.timer = setTimeout(() => {
        this.close(socket);
        socket.close(1001, "Browser heartbeat expired");
      }, 45000);
    } catch {
      this.close(socket);
      socket.close(1008, "Invalid browser message");
    }
  }
  targets(): SignInTarget[] {
    return [...this.peers.values()].flatMap((p) =>
      p.target ? [p.target] : [],
    );
  }
  async transfer(input: unknown): Promise<SignInResult> {
    const p = validateTransfer(input);
    const socket = [...this.peers].find(
      ([, v]) => v.target?.id === p.targetId,
    )?.[0];
    if (!socket)
      throw Error("Browser is offline. Reconnect and select it again.");
    if ([...this.pending.values()].some((j) => j.socket === socket))
      throw Error("A sign-in is already being delivered to this browser.");
    const id = crypto.randomUUID();
    const timeout = this.options.timeout ?? 15000;
    return new Promise((resolve) => {
      const total = p.cookies.length;
      const timer = setTimeout(() => {
        this.finish(id, { state: "unknown", installed: 0, total, reason: "timeout" });
        // A timed-out browser may still be processing the old import. Invalidate
        // its destination identity before accepting another transfer.
        this.close(socket);
        socket.close(1001, "Sign-in delivery timed out");
      }, timeout);
      this.pending.set(id, { socket, total, resolve, timer });
      try {
        socket.send(
          JSON.stringify({
            type: "import",
            id,
            deadline: Date.now() + timeout,
            ...p,
          }),
        );
      } catch {
        this.finish(id, { state: "unknown", installed: 0, total, reason: "send-failed" });
      }
    });
  }
  private finish(id: string, result: SignInResult) {
    const p = this.pending.get(id);
    if (!p) return;
    clearTimeout(p.timer);
    this.pending.delete(id);
    p.resolve(result);
  }
  close(socket: Socket) {
    const p = this.peers.get(socket);
    if (p) clearTimeout(p.timer);
    this.peers.delete(socket);
    for (const [id, j] of this.pending)
      if (j.socket === socket)
        this.finish(id, { state: "unknown", installed: 0, total: j.total, reason: "browser-disconnected" });
  }
  dispose() {
    for (const s of this.peers.keys()) {
      this.close(s);
      s.close(1001, "Server stopped");
    }
  }
}
/** Native API uses existing host authentication; web pages may not submit credentials. */
export async function signInHTTP(
  req: Request,
  hub: BrowserSignInHub,
): Promise<Response> {
  const response = (body: unknown, status = 200) =>
    Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
  if (req.headers.has("origin"))
    return response({ error: "Use the LFG app for sign-in." }, 403);
  const url = new URL(req.url);
  if (
    url.protocol !== "https:" &&
    !(
      req.headers.get("x-forwarded-proto") === "https" &&
      req.headers.has("cf-connecting-ip")
    ) &&
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)
  )
    return response({ error: "Sign-in requires HTTPS." }, 403);
  if (url.pathname === "/api/browser-sign-in/targets" && req.method === "GET")
    return response({ targets: hub.targets() });
  const requestRoot = "/api/browser-sign-in/requests";
  const requestPath = url.pathname.match(/^\/api\/browser-sign-in\/requests\/([a-f0-9-]{36})(?:\/(complete|cancel))?$/);
  if (req.method === "GET" && url.pathname === requestRoot)
    return response({requests: hub.requests.list(url.searchParams.get("sessionId") || "")});
  if (req.method === "GET" && requestPath && !requestPath[2]) {
    const request = hub.requests.get(requestPath[1]!);
    return request ? response(request) : response({error:"Sign-in request no longer exists."},404);
  }
  if (req.method !== "POST" || !(url.pathname === "/api/browser-sign-in/transfer" || url.pathname === requestRoot || requestPath?.[2]))
    return response({ error: "Not found" }, 404);
  if (url.pathname === requestRoot && (!allowsSignInAdapter(req) || !hub.authenticatesAgent(req)))
    return response({error:"Local agent connection required."},403);
  if (!req.headers.get("content-type")?.startsWith("application/json"))
    return response({ error: "JSON required" }, 415);
  // Stream-bound before parsing; Content-Length alone is not trusted.
  try {
    const reader = req.body?.getReader();
    if (!reader) throw Error("Missing sign-in data.");
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > SIGN_IN_MAX_BYTES) {
        await reader.cancel();
        return response({ error: "Sign-in data too large" }, 413);
      }
      chunks.push(value);
    }
    const data = JSON.parse(Buffer.concat(chunks).toString());
    if (url.pathname === requestRoot) return response(hub.requests.create(data));
    if (requestPath?.[2] === "cancel") return response(hub.requests.cancel(requestPath[1]!));
    if (requestPath?.[2] === "complete") return response(await hub.requests.complete(requestPath[1]!, data.cookies));
    validateTransfer(data);
    return response(await hub.transfer(data));
  } catch {
    return response(
      {
        error:
          "Could not deliver sign-in. Check the destination, selected domains and cookie validity.",
      },
      400,
    );
  }
}
export function allowsSignInAdapter(req: Request): boolean {
  const url = new URL(req.url),
    origin = req.headers.get("origin");
  return (
    ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) &&
    !req.headers.has("cf-connecting-ip") &&
    (!origin || /^chrome-extension:\/\/[a-p]{32}$/.test(origin))
  );
}
