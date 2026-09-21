import { sendToChannel, sendToToken, type ApnsEnv, type ApnsResult, type ApnsSecrets } from "./apns";
import { broadcastFor, decide, endBody, startBody, unionRows, updateBody, type Card, type ContentState, type Row, type Slice, type Veto } from "./reduce";

type Env = ApnsSecrets & {
  AGG_SECRET: string;
  ATTRIBUTES_TYPE: string;
  CHANNEL_PRODUCTION?: string;
  CHANNEL_SANDBOX?: string;
  FLEET: DurableObjectNamespace;
};

type StartToken = { token: string; env: ApnsEnv; deviceId?: string; updatedAt: number };
type TraceEvent = { t: string; event: string } & Record<string, unknown>;

const ENVS: ApnsEnv[] = ["production", "sandbox"];
const MAX_TOKENS_PER_ENV = 3;
const HEARTBEAT_MS = 30_000;
const json = (body: unknown, status = 200) => Response.json(body, { status });
const isDeadToken = (r: ApnsResult) =>
  !r.ok && (r.status === 410 || ["BadDeviceToken", "Unregistered", "ExpiredToken", "DeviceTokenNotForTopic"].includes(r.reason ?? ""));

/**
 * The one publisher of the fleet Live Activity.
 *
 * A single Durable Object instance holds every host's slice, the phone's
 * push-to-start tokens, and what the card last showed. Hosts know nothing about
 * each other; the phone registers here rather than with a host, so a card can be
 * started and kept current with any (or every) Mac asleep.
 */
export class FleetAggregator {
  private chain: Promise<unknown> = Promise.resolve();

  constructor(private state: DurableObjectState, private env: Env) {}

  private channel(env: ApnsEnv): string | undefined {
    const id = env === "production" ? this.env.CHANNEL_PRODUCTION : this.env.CHANNEL_SANDBOX;
    return id && id.trim() ? id.trim() : undefined;
  }

  private async trace(event: string, extra: Record<string, unknown> = {}): Promise<void> {
    const log = ((await this.state.storage.get<TraceEvent[]>("trace")) ?? []).slice(-149);
    log.push({ t: new Date().toISOString(), event, ...extra });
    await this.state.storage.put("trace", log);
  }

  /** Serialised: an evaluation awaits APNs, and two interleaved ones could both
   *  decide `start` — the one push that is not idempotent. */
  private evaluate(): Promise<void> {
    const run = this.chain.then(() => this.evaluateNow());
    this.chain = run.catch(() => undefined);
    return run;
  }

  /**
   * One card PER APNs ENVIRONMENT. Production (TestFlight / App Store) and sandbox
   * (a Debug build from Xcode) are different phones-worth of state: on 2026-09-20 a
   * Debug build's sandbox token accepted the `start`, the single shared "a card
   * exists" flag flipped, and the production phone could never be started. An
   * environment with no broadcast channel is skipped entirely — a card started
   * there could never be updated.
   */
  private async evaluateNow(): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const slices = Object.values((await this.state.storage.get<Record<string, Slice>>("slices")) ?? {});
    // The pre-per-env global keys; whatever they said, it was not per environment.
    await this.state.storage.delete(["card", "veto", "lastVetoTraced", "lastUndelivered"]);
    let anyCard = false;
    for (const env of ENVS) {
      if (!this.channel(env)) continue;
      anyCard = (await this.evaluateEnv(env, slices, now)) || anyCard;
    }
    await this.armAlarm(slices.length > 0 || anyCard);
  }

  private async evaluateEnv(env: ApnsEnv, slices: Slice[], now: number): Promise<boolean> {
    const k = (name: string) => `${name}:${env}`;
    const card = (await this.state.storage.get<Card | null>(k("card"))) ?? null;
    const veto = (await this.state.storage.get<Veto>(k("veto"))) ?? null;
    const d = decide({ slices, card, clientEnded: veto, now });

    if (d.vetoed) {
      const key = d.population.join(",");
      if ((await this.state.storage.get<string>(k("lastVetoTraced"))) !== key) {
        await this.trace("start-vetoed", { env, population: d.population.map((s) => s.slice(0, 8)) });
        await this.state.storage.put(k("lastVetoTraced"), key);
      }
    } else {
      await this.state.storage.delete(k("lastVetoTraced"));
    }

    const summary = { working: d.content.working, needsInput: d.content.needsInput, more: d.content.more, rows: d.content.rows.map((r) => `${r.sid.slice(0, 8)}:${r.state}`) };

    // 1. START — the only push that is not idempotent, so the only one gated on
    //    whether a card is believed to exist.
    let nextCard: Card | null = d.nextCard;
    if (d.action?.event === "start") {
      const key = `start|${d.population.join(",")}`;
      const repeat = (await this.state.storage.get<string>(k("lastUndelivered"))) === key;
      if (!repeat) await this.trace("decide", { env, apnsEvent: "start", priority: 10, ...summary });
      if (await this.sendStart(env, d.content, repeat)) {
        await this.state.storage.delete([k("lastUndelivered"), k("veto")]);
      } else {
        await this.state.storage.put(k("lastUndelivered"), key);
        nextCard = null; // not delivered: still no card
      }
    }
    if (nextCard !== card) await this.state.storage.put(k("card"), nextCard);

    // 2. CHANNEL — kept current on every change of content, card known or not
    //    (see `broadcastFor`). A failed broadcast is not recorded, so the next
    //    evaluation retries it.
    const last = await this.state.storage.get<ContentState>(k("lastBroadcast"));
    // `assert` is set when the app reports a card it created itself. That card was
    // drawn from the APP's view, which can be stale (2026-09-21: created at launch
    // showing a session that had finished nine minutes earlier, then frozen for two
    // hours — the Worker's truth was "nothing running", identical to its last
    // broadcast, so it said nothing). A new card must be told the truth even when
    // the truth has not changed: update if anything runs, END if nothing does.
    const asserting = (await this.state.storage.get<boolean>(k("assert"))) === true;
    const total = d.content.working + d.content.needsInput;
    const event = broadcastFor(last, d.content) ?? (asserting ? (total > 0 ? "update" : "end") : null);
    if (event) {
      await this.trace("decide", { env, apnsEvent: event, priority: 10, via: asserting ? "channel-assert" : "channel", ...summary });
      if (await this.broadcast(env, event, d.content, 10, now)) {
        await this.state.storage.put(k("lastBroadcast"), d.content);
        await this.state.storage.delete(k("assert"));
        // An asserted END means the app's card is gone: forget it, or the Worker
        // would believe a card exists and never push-to-start the next one.
        if (event === "end") { await this.state.storage.put(k("card"), null); return false; }
      }
    }
    return nextCard !== null;
  }

  private async sendStart(env: ApnsEnv, content: Parameters<typeof startBody>[0], quiet = false): Promise<boolean> {
    const all = (await this.state.storage.get<StartToken[]>("tokens")) ?? [];
    const tokens = all.filter((t) => t.env === env);
    if (!tokens.length) { if (!quiet) await this.trace("no-tokens", { env, apnsEvent: "start" }); return false; }
    let accepted = 0;
    const dead: string[] = [];
    for (const t of tokens) {
      const r = await sendToToken(this.env, t.env, t.token, startBody(content, this.env.ATTRIBUTES_TYPE, this.channel(t.env)));
      await this.trace("send", { apnsEvent: "start", token: t.token.slice(0, 8), env: t.env, status: r.status, ...(r.reason ? { reason: r.reason } : {}) });
      if (r.ok) accepted++;
      else if (isDeadToken(r)) dead.push(t.token);
    }
    if (dead.length) await this.state.storage.put("tokens", all.filter((t) => !dead.includes(t.token)));
    return accepted > 0;
  }

  private async broadcast(env: ApnsEnv, event: "update" | "end", content: Parameters<typeof updateBody>[0], priority: 5 | 10, now: number): Promise<boolean> {
    const r = await sendToChannel(this.env, env, this.channel(env)!, event === "end" ? endBody(content, now) : updateBody(content), priority);
    await this.trace("broadcast", { apnsEvent: event, env, status: r.status, ...(r.reason ? { reason: r.reason } : {}) });
    return r.ok;
  }

  private async armAlarm(needed: boolean): Promise<void> {
    if (!needed) return;
    if ((await this.state.storage.getAlarm()) === null) await this.state.storage.setAlarm(Date.now() + HEARTBEAT_MS);
  }

  /** Slices expire by the clock, not by a request — this is what ends the card when
   *  the last host simply vanishes. */
  async alarm(): Promise<void> {
    await this.evaluate();
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;
    const body = req.method === "GET" ? {} : ((await req.json().catch(() => ({}))) as Record<string, unknown>);
    const now = Math.floor(Date.now() / 1000);

    const sliceMatch = path.match(/^\/v1\/hosts\/([^/]+)\/slice$/);
    if (sliceMatch && req.method === "PUT") {
      const hostId = decodeURIComponent(sliceMatch[1]!);
      const rows = (Array.isArray(body.rows) ? body.rows : []).slice(0, 200).map((r: Record<string, unknown>): Row => ({
        sid: String(r.sid ?? ""),
        title: String(r.title ?? "").slice(0, 80),
        state: r.state === "needsInput" ? "needsInput" : r.state === "working" ? "working" : ("idle" as never),
        since: Number(r.since) || now,
      }));
      const slices = (await this.state.storage.get<Record<string, Slice>>("slices")) ?? {};
      slices[hostId] = { hostId, hostName: typeof body.hostName === "string" ? body.hostName : undefined, rows, receivedAt: now };
      await this.state.storage.put("slices", slices);
      await this.evaluate();
      return json({ ok: true, rows: rows.length });
    }

    if (path === "/v1/start-token" && req.method === "POST") {
      const token = String(body.token ?? "");
      if (!/^[0-9a-f]{32,}$/i.test(token)) return json({ error: "bad token" }, 400);
      const env: ApnsEnv = body.env === "production" ? "production" : "sandbox";
      const deviceId = typeof body.deviceId === "string" && body.deviceId ? body.deviceId : undefined;
      let tokens = (await this.state.storage.get<StartToken[]>("tokens")) ?? [];
      // One current token per device: a rotation REPLACES the old one. Without a
      // device id every rotation added a token, and one start went to three tokens
      // that were all the same phone.
      tokens = tokens.filter((t) => t.token !== token && !(deviceId && t.deviceId === deviceId && t.env === env));
      tokens.push({ token, env, deviceId, updatedAt: Date.now() });
      const keep = ENVS.flatMap((e) => tokens.filter((t) => t.env === e).sort((a, b) => b.updatedAt - a.updatedAt).slice(0, MAX_TOKENS_PER_ENV));
      await this.state.storage.put("tokens", keep);
      await this.trace("start-token", { token: token.slice(0, 8), env, device: deviceId?.slice(0, 8) });
      await this.evaluate();
      return json({ ok: true });
    }

    if (path === "/v1/channel" && req.method === "GET") {
      const env: ApnsEnv = url.searchParams.get("env") === "production" ? "production" : "sandbox";
      return json({ env, channelId: this.channel(env) ?? null });
    }

    // Reports without an `env` come from builds (and host forwards) that predate
    // per-environment cards; those are TestFlight builds, i.e. production.
    const reportEnv: ApnsEnv = body.env === "sandbox" ? "sandbox" : "production";

    if (path === "/v1/started" && req.method === "POST") {
      // The app created a card itself. Adopt it rather than push-to-start a second;
      // with no content recorded the next evaluation fills it in.
      if (!(await this.state.storage.get<Card | null>(`card:${reportEnv}`))) await this.state.storage.put(`card:${reportEnv}`, { startedAt: now });
      await this.state.storage.delete(`veto:${reportEnv}`);
      await this.state.storage.put(`assert:${reportEnv}`, true);
      await this.trace("adopted", { env: reportEnv });
      await this.evaluate();
      return json({ ok: true });
    }

    if (path === "/v1/ended" && req.method === "POST") {
      const slices = Object.values((await this.state.storage.get<Record<string, Slice>>("slices")) ?? {});
      const population = unionRows(slices, now).map((r) => r.sid);
      await this.state.storage.put(`card:${reportEnv}`, null);
      await this.state.storage.put(`veto:${reportEnv}`, { population });
      await this.trace("client-ended", { env: reportEnv, population: population.map((s) => s.slice(0, 8)) });
      return json({ ok: true });
    }

    if (path === "/v1/state" && req.method === "GET") {
      const slices = (await this.state.storage.get<Record<string, Slice>>("slices")) ?? {};
      return json({
        now,
        slices: Object.values(slices).map((s) => ({ hostId: s.hostId, hostName: s.hostName, ageS: now - s.receivedAt, rows: s.rows.map((r) => `${r.sid.slice(0, 8)}:${r.state}`) })),
        cards: Object.fromEntries(await Promise.all(ENVS.map(async (e) => [e, (await this.state.storage.get(`card:${e}`)) ?? null]))),
        vetoes: Object.fromEntries(await Promise.all(ENVS.map(async (e) => [e, (await this.state.storage.get(`veto:${e}`)) ?? null]))),
        tokens: ((await this.state.storage.get<StartToken[]>("tokens")) ?? []).map((t) => ({ token: t.token.slice(0, 8), env: t.env, device: t.deviceId?.slice(0, 8), updatedAt: new Date(t.updatedAt).toISOString() })),
        channels: Object.fromEntries(ENVS.map((e) => [e, this.channel(e)?.slice(0, 8) ?? null])),
        trace: ((await this.state.storage.get<TraceEvent[]>("trace")) ?? []).slice(-Number(url.searchParams.get("n") ?? 40)),
      });
    }

    return json({ error: "not found" }, 404);
  }
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.headers.get("authorization") !== `Bearer ${env.AGG_SECRET}`) return json({ error: "unauthorized" }, 401);
    const path = new URL(req.url).pathname;
    if (path === "/v1/probe") {
      // Transport + auth health: a well-formed but unknown token must come back
      // `400 BadDeviceToken` over HTTP/2. Sends nothing to any real device.
      return json(await sendToToken(env, "production", "0".repeat(64), { aps: { timestamp: 1, event: "update", "content-state": {} } }));
    }
    return env.FLEET.get(env.FLEET.idFromName("fleet")).fetch(req);
  },
};
