import { sendToChannel, sendToToken, type ApnsEnv, type ApnsResult, type ApnsSecrets } from "./apns";
import { decide, endBody, startBody, unionRows, updateBody, type Card, type Row, type Slice, type Veto } from "./reduce";

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

  private async evaluateNow(): Promise<void> {
    const now = Math.floor(Date.now() / 1000);
    const slices = Object.values((await this.state.storage.get<Record<string, Slice>>("slices")) ?? {});
    const card = (await this.state.storage.get<Card | null>("card")) ?? null;
    const veto = (await this.state.storage.get<Veto>("veto")) ?? null;
    const d = decide({ slices, card, clientEnded: veto, now });

    if (d.vetoed) {
      const key = d.population.join(",");
      if ((await this.state.storage.get<string>("lastVetoTraced")) !== key) {
        await this.trace("start-vetoed", { population: d.population.map((s) => s.slice(0, 8)) });
        await this.state.storage.put("lastVetoTraced", key);
      }
    } else {
      await this.state.storage.delete("lastVetoTraced");
    }

    if (d.action) {
      const summary = { working: d.content.working, needsInput: d.content.needsInput, more: d.content.more, rows: d.content.rows.map((r) => `${r.sid.slice(0, 8)}:${r.state}`) };
      // An undelivered decision is re-made on every evaluation (each slice, each
      // alarm). Trace it once per distinct decision, not once per attempt — a
      // tokenless Worker otherwise fills its 150-line trace with one event.
      const key = `${d.action.event}|${d.population.join(",")}|${d.content.needsInput}`;
      const repeat = (await this.state.storage.get<string>("lastUndelivered")) === key;
      if (!repeat) await this.trace("decide", { apnsEvent: d.action.event, priority: d.action.priority, ...summary });
      const delivered = d.action.event === "start" ? await this.sendStart(d.content, repeat) : await this.broadcast(d.action.event, d.content, d.action.priority, now);
      if (delivered) {
        await this.state.storage.put("card", d.nextCard);
        await this.state.storage.delete("lastUndelivered");
        if (d.action.event === "start") await this.state.storage.delete("veto");
      } else {
        await this.state.storage.put("lastUndelivered", key);
      }
    } else if (d.nextCard !== card) {
      await this.state.storage.put("card", d.nextCard);
    }
    await this.armAlarm(slices.length > 0 || d.nextCard !== null);
  }

  private async sendStart(content: Parameters<typeof startBody>[0], quiet = false): Promise<boolean> {
    const tokens = (await this.state.storage.get<StartToken[]>("tokens")) ?? [];
    if (!tokens.length) { if (!quiet) await this.trace("no-tokens", { apnsEvent: "start" }); return false; }
    let accepted = 0;
    const dead: string[] = [];
    for (const t of tokens) {
      const r = await sendToToken(this.env, t.env, t.token, startBody(content, this.env.ATTRIBUTES_TYPE, this.channel(t.env)));
      await this.trace("send", { apnsEvent: "start", token: t.token.slice(0, 8), env: t.env, status: r.status, ...(r.reason ? { reason: r.reason } : {}) });
      if (r.ok) accepted++;
      else if (isDeadToken(r)) dead.push(t.token);
    }
    if (dead.length) await this.state.storage.put("tokens", tokens.filter((t) => !dead.includes(t.token)));
    return accepted > 0;
  }

  private async broadcast(event: "update" | "end", content: Parameters<typeof updateBody>[0], priority: 5 | 10, now: number): Promise<boolean> {
    const targets = ENVS.filter((e) => this.channel(e));
    if (!targets.length) { await this.trace("no-channel", { apnsEvent: event }); return false; }
    let accepted = 0;
    for (const e of targets) {
      const r = await sendToChannel(this.env, e, this.channel(e)!, event === "end" ? endBody(content, now) : updateBody(content), priority);
      await this.trace("broadcast", { apnsEvent: event, env: e, status: r.status, ...(r.reason ? { reason: r.reason } : {}) });
      if (r.ok) accepted++;
    }
    // Production is the phone that matters (TestFlight). A sandbox channel that
    // refuses must not freeze the production card's state.
    return accepted > 0;
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

    if (path === "/v1/started" && req.method === "POST") {
      // The app created a card itself. Adopt it rather than push-to-start a second;
      // with no content recorded the next evaluation fills it in.
      if (!(await this.state.storage.get<Card | null>("card"))) await this.state.storage.put("card", { startedAt: now });
      await this.state.storage.delete("veto");
      await this.trace("adopted");
      await this.evaluate();
      return json({ ok: true });
    }

    if (path === "/v1/ended" && req.method === "POST") {
      const slices = Object.values((await this.state.storage.get<Record<string, Slice>>("slices")) ?? {});
      const population = unionRows(slices, now).map((r) => r.sid);
      await this.state.storage.put("card", null);
      await this.state.storage.put("veto", { population });
      await this.trace("client-ended", { population: population.map((s) => s.slice(0, 8)) });
      return json({ ok: true });
    }

    if (path === "/v1/state" && req.method === "GET") {
      const slices = (await this.state.storage.get<Record<string, Slice>>("slices")) ?? {};
      return json({
        now,
        slices: Object.values(slices).map((s) => ({ hostId: s.hostId, hostName: s.hostName, ageS: now - s.receivedAt, rows: s.rows.map((r) => `${r.sid.slice(0, 8)}:${r.state}`) })),
        card: (await this.state.storage.get("card")) ?? null,
        veto: (await this.state.storage.get("veto")) ?? null,
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
