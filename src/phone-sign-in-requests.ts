import { readFileSync, writeFileSync, mkdirSync, renameSync } from "node:fs";
import { dirname } from "node:path";
import { loginURL, type SignInTarget, type SignInResult } from "./browser-sign-in.ts";

export type PhoneSignInRequest = {
  id: string; sessionId: string; url: string; target: SignInTarget;
  state: "waiting" | "delivering" | "installed" | "partial" | "failed" | "unknown" | "cancelled" | "expired" | "offline";
  createdAt: number; expiresAt: number; result?: SignInResult;
};
interface Backend { targets(): SignInTarget[]; transfer(input: unknown): Promise<SignInResult> }
const active = (r: PhoneSignInRequest) => r.state === "waiting" || r.state === "delivering";
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
/** Bounded request metadata. Optional disk history contains origins only, never cookies. */
export class PhoneSignInRequests {
  private rows = new Map<string, PhoneSignInRequest>();
  constructor(private backend: Backend, private now = Date.now, private ttl = 15 * 60_000, private historyPath?: string) {
    if (!historyPath) return;
    try {
      const records = JSON.parse(readFileSync(historyPath, "utf8"));
      if (!Array.isArray(records)) return;
      for (const input of records.slice(-128)) {
        const r = this.metadata(input);
        if (r.state === "waiting") r.state = "expired";
        if (r.state === "delivering") r.state = "unknown";
        this.rows.set(r.id, r);
      }
      this.persist();
    } catch { /* Missing or invalid history must not prevent host startup. */ }
  }
  private metadata(input: PhoneSignInRequest): PhoneSignInRequest {
    if (!uuid.test(input.id) || !uuid.test(input.sessionId) || !Number.isFinite(input.createdAt) || !Number.isFinite(input.expiresAt)
      || typeof input.target?.id !== "string" || typeof input.target.name !== "string"
      || !["chrome", "playwright"].includes(input.target.kind)
      || !["waiting","delivering","installed","partial","failed","unknown","cancelled","expired","offline"].includes(input.state)) throw Error("Invalid history");
    const row: PhoneSignInRequest = {
      id: input.id, sessionId: input.sessionId, url: loginURL(input.url).origin,
      target: {id: input.target.id, name: input.target.name, kind: input.target.kind},
      state: input.state, createdAt: input.createdAt, expiresAt: input.expiresAt,
    };
    if (input.result && ["installed","partial","failed","unknown"].includes(input.result.state)
      && Number.isInteger(input.result.installed) && Number.isInteger(input.result.total)) {
      row.result = {state: input.result.state, installed: input.result.installed, total: input.result.total};
    }
    return row;
  }
  private persist() {
    if (!this.historyPath) return;
    try {
      mkdirSync(dirname(this.historyPath), {recursive: true, mode: 0o700});
      const temporary = this.historyPath + ".tmp-" + crypto.randomUUID();
      writeFileSync(temporary, JSON.stringify([...this.rows.values()].map(r => this.metadata(r))), {mode: 0o600, flag: "wx"});
      renameSync(temporary, this.historyPath);
    } catch { console.warn("Phone sign-in history could not be saved."); }
  }
  private sweep() {
    let changed = false;
    for (const r of this.rows.values()) {
      const previous = r.state;
      if (r.state === "waiting") {
        if (r.expiresAt <= this.now()) r.state = "expired";
        else if (!this.backend.targets().some(t => t.id === r.target.id)) r.state = "offline";
      }
      changed ||= previous !== r.state;
    }
    if (changed) this.persist();
  }
  create(input: {sessionId?: unknown; targetId?: unknown; url?: unknown}): PhoneSignInRequest {
    this.sweep();
    if (typeof input.sessionId !== "string" || !uuid.test(input.sessionId) || typeof input.url !== "string" || input.url.length > 2048)
      throw Error("A session ID and HTTPS login URL are required.");
    const url = loginURL(input.url).href;
    const target = this.backend.targets().find(t => t.id === input.targetId);
    if (!target) throw Error("The requested browser is offline.");
    const existing = [...this.rows.values()].find(r => active(r) && r.target.id === target.id);
    if (existing) {
      if (existing.sessionId === input.sessionId && existing.url === url) return {...existing};
      throw Error("This browser already has a sign-in request. Wait for it to finish.");
    }
    if (this.rows.size >= 128) {
      const oldest = [...this.rows.values()].find(r => !active(r));
      if (oldest) this.rows.delete(oldest.id);
      else throw Error("Too many sign-in requests.");
    }
    const row: PhoneSignInRequest = {id: crypto.randomUUID(), sessionId: input.sessionId, url, target: {...target}, state:"waiting", createdAt:this.now(), expiresAt:this.now()+this.ttl};
    this.rows.set(row.id, row);
    this.persist();
    return {...row};
  }
  list(sessionId: string) { this.sweep(); return [...this.rows.values()].filter(r => r.sessionId === sessionId).reverse().sort((a,b) => b.createdAt-a.createdAt).map(r => ({...r})); }
  get(id: string) { this.sweep(); const r = this.rows.get(id); return r ? {...r} : undefined; }
  cancel(id: string) {
    this.sweep(); const r = this.rows.get(id);
    if (!r) throw Error("Sign-in request no longer exists.");
    if (r.state === "delivering") throw Error("Delivery is in progress. Check its result before cancelling.");
    if (r.state === "waiting") { r.state = "cancelled"; this.persist(); }
    return {...r};
  }
  async complete(id: string, cookies: unknown): Promise<PhoneSignInRequest> {
    this.sweep(); const r = this.rows.get(id);
    if (!r) throw Error("Sign-in request no longer exists.");
    if (r.state !== "waiting") return {...r}; // Never replay a Done request.
    if (!Array.isArray(cookies) || !cookies.length) throw Error("Finish signing in before pressing Done.");
    // The phone supplies only cookies. URL, browser and domains cannot be overridden.
    const domains = [...new Set(cookies.map(c => typeof c?.domain === "string" ? c.domain.replace(/^\./, "").toLowerCase() : ""))];
    r.state = "delivering";
    this.persist();
    try {
      r.result = await this.backend.transfer({targetId:r.target.id, url:r.url, domains, cookies});
      r.state = r.result.state;
    } catch {
      r.state = "failed"; r.result = {state:"failed",installed:0,total:cookies.length};
    }
    this.persist();
    return {...r};
  }
}
