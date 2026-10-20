import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { codexBin } from "./tmux.ts";

export type UsageProvider = "claude" | "codex";
export type UsageIdentity = { accountId: string | null; accountLabel: string | null; plan: string | null };
export type QuotaWindow = { id: string; durationMinutes: number; name: string | null; usedPercent: number | null; resetsAt: string | null };
export type AccountUsage = UsageIdentity & {
  provider: UsageProvider;
  status: "ok" | "unavailable" | "error" | "api";
  fetchedAt: string | null;
  windows: QuotaWindow[];
  error: "read_failed" | "auth_rejected" | null;
};

const object = (value: unknown): Record<string, any> => value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, any> : {};
const string = (value: unknown): string | null => typeof value === "string" && value.trim() ? value.trim().slice(0, 240) : null;
const percentage = (value: unknown): number | null => typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.min(100, value) : null;
function date(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const millis = typeof value === "number" ? value * 1000 : Date.parse(value);
  const parsed = new Date(millis);
  return Number.isFinite(parsed.getTime()) && millis > 0 ? parsed.toISOString() : null;
}

export function usageIdentity(provider: UsageProvider, proof: string | null): string | null {
  return proof ? `${provider}:${createHash("sha256").update(proof).digest("hex")}` : null;
}

function missing(durationMinutes: number): QuotaWindow {
  return { id: `missing-${durationMinutes}`, durationMinutes, name: null, usedPercent: null, resetsAt: null };
}

function completeWindows(windows: QuotaWindow[]): QuotaWindow[] {
  if (windows.length && !windows.some(w => w.durationMinutes < 10080)) windows.push(missing(300));
  if (windows.length && !windows.some(w => w.durationMinutes === 10080)) windows.push(missing(10080));
  return windows.sort((a, b) => a.durationMinutes - b.durationMinutes || a.id.localeCompare(b.id));
}

function reading(provider: UsageProvider, identity: UsageIdentity, fetchedAt: string, windows: QuotaWindow[]): AccountUsage {
  return { provider, ...identity, fetchedAt, status: windows.length ? "ok" : "unavailable", windows: completeWindows(windows), error: null };
}

export function normalizeClaudeUsage(raw: unknown, identity: UsageIdentity, fetchedAt: string): AccountUsage {
  const value = object(raw);
  const windows: QuotaWindow[] = [];
  for (const [key, duration, name] of [["five_hour", 300, null], ["seven_day", 10080, null], ["seven_day_opus", 10080, "Opus"], ["seven_day_sonnet", 10080, "Sonnet"]] as const) {
    if (!value[key] && (key !== "five_hour" && key !== "seven_day")) continue;
    const window = object(value[key]);
    windows.push({ id: key, durationMinutes: duration, name, usedPercent: percentage(window.utilization), resetsAt: date(window.resets_at) });
  }
  const result = reading("claude", identity, fetchedAt, windows);
  if (!value.five_hour && !value.seven_day && windows.every(w => w.usedPercent === null)) result.status = "unavailable";
  return result;
}

export function normalizeCodexUsage(raw: unknown, identity: UsageIdentity, fetchedAt: string): AccountUsage {
  const value = object(raw);
  const buckets = Object.entries(object(value.rateLimitsByLimitId));
  if (!buckets.length && value.rateLimits) buckets.push(["codex", value.rateLimits]);
  const windows: QuotaWindow[] = [];
  for (const [id, rawBucket] of buckets) {
    const bucket = object(rawBucket);
    for (const key of ["primary", "secondary"]) {
      const window = object(bucket[key]);
      const duration = window.windowDurationMins;
      if (typeof duration !== "number" || !Number.isFinite(duration) || duration <= 0 || duration > 52_560_000) continue;
      windows.push({ id: `${id}:${key}`, durationMinutes: duration, name: id === "codex" ? null : string(bucket.limitName) ?? id,
        usedPercent: percentage(window.usedPercent), resetsAt: date(window.resetsAt) });
    }
  }
  return reading("codex", identity, fetchedAt, windows);
}

class UsageReadError extends Error {
  constructor(readonly code: "read_failed" | "auth_rejected" = "read_failed") { super(code); }
}

// Per-credential keys prevent a changed sign-in inheriting another account's
// last reading. Keys and credentials never cross the API boundary.
export class UsageCache {
  private values = new Map<string, { expires: number; value: AccountUsage }>();
  private pending = new Map<string, Promise<AccountUsage>>();
  constructor(private now: () => number = Date.now) {}
  async read(key: string, load: () => Promise<AccountUsage>): Promise<AccountUsage> {
    const cached = this.values.get(key);
    if (cached && cached.expires > this.now()) return cached.value;
    const existing = this.pending.get(key);
    if (existing) return existing;
    const promise = (async () => {
      try {
        const value = await load();
        this.values.set(key, { expires: this.now() + 60_000, value });
        // Bound old credential contexts in a long-lived host process.
        if (this.values.size > 20) this.values.delete(this.values.keys().next().value!);
        return value;
      } catch (error) {
        if (!cached) throw error;
        const value: AccountUsage = { ...cached.value, status: "error", error: error instanceof UsageReadError ? error.code : "read_failed" };
        this.values.set(key, { expires: this.now() + 10_000, value });
        return value;
      }
    })().finally(() => this.pending.delete(key));
    this.pending.set(key, promise);
    return promise;
  }
}

const cache = new UsageCache();
async function jsonFile(path: string): Promise<Record<string, any>> {
  try { const file = Bun.file(path); return file.size < 1_000_000 ? object(await file.json()) : {}; } catch { return {}; }
}

async function keychainCredentials(): Promise<Record<string, any>> {
  if (process.platform !== "darwin") return {};
  const proc = Bun.spawn(["/usr/bin/security", "find-generic-password", "-s", "Claude Code-credentials", "-w"], { stdout: "pipe", stderr: "ignore" });
  const timer = setTimeout(() => { try { proc.kill("SIGKILL"); } catch {} }, 5_000);
  try {
    const output = await new Response(proc.stdout).text();
    return await proc.exited === 0 ? object(JSON.parse(output)) : {};
  } catch { return {}; } finally { clearTimeout(timer); }
}

function empty(provider: UsageProvider, identity: UsageIdentity, status: AccountUsage["status"], error: AccountUsage["error"] = null): AccountUsage {
  return { provider, ...identity, status, error, windows: [], fetchedAt: null };
}

export async function claudeAccountUsage(): Promise<AccountUsage> {
  if (process.env.ANTHROPIC_API_KEY || process.env.CLAUDE_CODE_USE_BEDROCK === "1" || process.env.CLAUDE_CODE_USE_VERTEX === "1" || process.env.CLAUDE_CODE_USE_FOUNDRY === "1") {
    return empty("claude", { accountId: null, accountLabel: null, plan: "API billing" }, "api");
  }
  const config = resolve(process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"));
  const isDefault = config === join(homedir(), ".claude");
  const [file, keychain, metadata] = await Promise.all([
    jsonFile(join(config, ".credentials.json")),
    isDefault ? keychainCredentials() : Promise.resolve<Record<string, any>>({}),
    jsonFile(isDefault ? join(homedir(), ".claude.json") : join(config, ".claude.json")),
  ]);
  // On macOS the native CLI's Keychain store is authoritative, even when a
  // different account left a later-dated token in the legacy file.
  const candidates = [object(keychain.claudeAiOauth), object(file.claudeAiOauth)]
    .filter(c => string(c.accessToken));
  const credentials = candidates[0];
  const account = object(metadata.oauthAccount);
  const accountUUID = string(account.accountUuid), organizationUUID = string(account.organizationUuid);
  const tier = string(credentials?.rateLimitTier);
  const identity: UsageIdentity = {
    accountId: usageIdentity("claude", accountUUID && organizationUUID ? `${accountUUID}:${organizationUUID}` : null),
    accountLabel: string(account.emailAddress) ?? string(account.displayName),
    plan: tier?.includes("20x") ? "Max 20×" : tier?.includes("5x") ? "Max 5×" : credentials?.subscriptionType === "max" ? "Max" : credentials?.subscriptionType === "pro" ? "Pro" : null,
  };
  if (!credentials) return empty("claude", { accountId: null, accountLabel: null, plan: null }, "unavailable");
  try {
    return await cache.read(usageIdentity("claude", `${config}:${identity.accountId}:${credentials.accessToken}`)!, async () => {
      const response = await fetch("https://api.anthropic.com/api/oauth/usage", {
        headers: { Authorization: `Bearer ${credentials.accessToken}`, "anthropic-beta": "oauth-2025-04-20" },
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) throw new UsageReadError(response.status === 401 ? "auth_rejected" : "read_failed");
      return normalizeClaudeUsage(await response.json(), identity, new Date().toISOString());
    });
  } catch (error) {
    return empty("claude", identity, "error", error instanceof UsageReadError ? error.code : "read_failed");
  }
}

// A separate read-only process avoids claiming any live thread or depending on
// whether the current CLI has a daemon socket. No inference method is called.
async function codexAccountRead(): Promise<{ account: Record<string, any>; limits: unknown; credentialStore: string | null }> {
  const proc = Bun.spawn([codexBin(), "app-server", "--stdio"], { stdin: "pipe", stdout: "pipe", stderr: "ignore" });
  const timer = setTimeout(() => { try { proc.kill("SIGKILL"); } catch {} }, 12_000);
  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  async function request(id: number, method: string, params: object): Promise<any> {
    proc.stdin.write(JSON.stringify({ id, method, params }) + "\n");
    while (true) {
      const newline = buffer.indexOf("\n");
      if (newline >= 0) {
        const line = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
        let value; try { value = JSON.parse(line); } catch { continue; }
        if (value.id !== id) continue;
        if (value.error) throw new UsageReadError();
        return value.result;
      }
      const chunk = await reader.read();
      if (chunk.done) throw new UsageReadError();
      buffer += decoder.decode(chunk.value, { stream: true });
      if (buffer.length > 1_000_000) throw new UsageReadError();
    }
  }
  try {
    await request(1, "initialize", { clientInfo: { name: "lfg-usage", version: "1" }, capabilities: {} });
    proc.stdin.write(JSON.stringify({ method: "initialized" }) + "\n");
    const account = object((await request(2, "account/read", { refreshToken: false }))?.account);
    if (!account.type || account.type === "apiKey") return { account, limits: null, credentialStore: null };
    let credentialStore: string | null = null;
    try {
      const configuration = object((await request(3, "config/read", { includeLayers: false }))?.config);
      credentialStore = string(configuration.cli_auth_credentials_store);
    } catch { /* Older CLIs can still report limits, without proving file identity. */ }
    return { account, credentialStore, limits: await request(4, "account/rateLimits/read", {}) };
  } finally {
    clearTimeout(timer);
    try { proc.stdin.end(); } catch {}
    try { proc.kill(); } catch {}
    await reader.cancel().catch(() => {});
    let exited = false;
    await Promise.race([proc.exited.then(() => { exited = true; }), Bun.sleep(500)]);
    if (!exited) { try { proc.kill("SIGKILL"); } catch {} }
  }
}

const codexStores = new Map<string, string>();
async function codexUsage(): Promise<AccountUsage> {
  const config = resolve(process.env.CODEX_HOME || join(homedir(), ".codex"));
  const auth = await jsonFile(join(config, "auth.json"));
  const tokens = object(auth.tokens);
  let claims: Record<string, any> = {};
  try { claims = object(JSON.parse(Buffer.from(String(tokens.id_token).split(".")[1]!, "base64url").toString())); } catch {}
  const accountID = string(tokens.account_id), subject = string(claims.sub);
  const identity: UsageIdentity = {
    accountId: usageIdentity("codex", accountID && subject ? `${accountID}:${subject}` : null),
    accountLabel: string(claims.email), plan: null,
  };
  try {
    const configText = await Bun.file(join(config, "config.toml")).text().catch(() => "");
    const key = usageIdentity("codex", `${config}:${configText}:${tokens.access_token ?? auth.auth_mode ?? "unknown"}:${auth.OPENAI_API_KEY ?? ""}`)!;
    const load = async () => {
      const { account, limits, credentialStore } = await codexAccountRead();
      codexStores.set(key, credentialStore ?? "unknown");
      if (codexStores.size > 20) codexStores.delete(codexStores.keys().next().value!);
      const type = String(account.type || "").toLowerCase();
      if (type === "apikey") return empty("codex", { accountId: null, accountLabel: null, plan: "API billing" }, "api");
      if (!type) return empty("codex", { accountId: null, accountLabel: null, plan: null }, "unavailable");
      const plan = string(account.planType);
      const reportedEmail = string(account.email);
      const proved = credentialStore === "file" && reportedEmail && reportedEmail.toLowerCase() === identity.accountLabel?.toLowerCase();
      return normalizeCodexUsage(limits, { ...identity, accountId: proved ? identity.accountId : null, accountLabel: reportedEmail,
        plan: plan ? `ChatGPT ${plan.charAt(0).toUpperCase()}${plan.slice(1)}` : null }, new Date().toISOString());
    };
    // A file fingerprint cannot invalidate a Keychain or ephemeral sign-in.
    // Those contexts are read afresh and never use a stale file as identity.
    return codexStores.has(key) && codexStores.get(key) !== "file" ? await load() : await cache.read(key, load);
  } catch {
    // A failed CLI read has not proved that the file is the active sign-in.
    return empty("codex", { accountId: null, accountLabel: null, plan: null }, "error", "read_failed");
  }
}

export async function accountUsage(): Promise<{ providers: AccountUsage[] }> {
  // An unexpected local read failure cannot discard the other provider.
  const providers = await Promise.all((["claude", "codex"] as const).map(async provider => {
    try { return await (provider === "claude" ? claudeAccountUsage() : codexUsage()); }
    catch { return empty(provider, { accountId: null, accountLabel: null, plan: null }, "error", "read_failed"); }
  }));
  return { providers };
}
