// Host side of the fleet Live Activity aggregator (workers/fleet-aggregator).
//
// A Live Activity push REPLACES the card's whole content and iOS never merges two
// senders, so with sessions on more than one host no single host can publish a
// correct card — and a host that sees zero of ITS sessions would end a card the
// other host still needs (2026-09-20: the Pro ended the app's card every few
// seconds while both running sessions were on the Air). In slice mode a host
// therefore publishes only its own rows here, and the Worker — the one publisher —
// merges every host's slice and talks to APNs.
//
// Pure of lfg state: no imports from the watcher, so both it and serve.ts can use it.

export type SliceRow = { sid: string; title: string; state: "working" | "needsInput"; since: number };
export type AggregatorConfig = { url: string; secret: string };

/** Republish an unchanged slice this often. The Worker drops a host that has been
 *  silent for 90 s, so this is its heartbeat — three missed beats and the host's
 *  rows leave the card. */
export const SLICE_HEARTBEAT_MS = 30_000;

export function aggregatorConfig(env: Record<string, string | undefined> = process.env): AggregatorConfig | null {
  const url = env.LFG_FLEET_AGGREGATOR_URL?.trim().replace(/\/+$/, "");
  const secret = env.LFG_FLEET_AGGREGATOR_SECRET?.trim();
  return url && secret ? { url, secret } : null;
}

type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body?: string; signal?: AbortSignal }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export async function aggregatorRequest(
  cfg: AggregatorConfig,
  method: "GET" | "POST" | "PUT",
  path: string,
  body?: unknown,
  fetchImpl: FetchLike = fetch as unknown as FetchLike,
): Promise<{ ok: boolean; status: number; data?: unknown }> {
  try {
    const r = await fetchImpl(`${cfg.url}${path}`, {
      method,
      headers: { authorization: `Bearer ${cfg.secret}`, "content-type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(8_000),
    });
    return { ok: r.ok, status: r.status, data: await r.json().catch(() => undefined) };
  } catch {
    return { ok: false, status: 0 };
  }
}

const fingerprint = (rows: SliceRow[]): string =>
  JSON.stringify([...rows].sort((a, b) => (a.sid < b.sid ? -1 : 1)).map((r) => [r.sid, r.title, r.state, r.since]));

export class FleetSlicePublisher {
  /// Per-session state clock, carried between ticks so a row keeps its start time
  /// (the reducer used to keep this on the card it owned; the host owns no card now).
  since: Record<string, { state: SliceRow["state"]; at: number }> = {};
  private lastSent?: string;
  private lastSentAt = 0;

  constructor(
    private cfg: AggregatorConfig,
    private host: { id: () => string; name: () => string },
    private fetchImpl?: FetchLike,
    private trace: (event: string, extra?: Record<string, unknown>) => void = () => {},
  ) {}

  /** Send when the rows changed, or as a heartbeat. A failed send is not recorded,
   *  so the very next tick (2 s) retries. */
  async publish(rows: SliceRow[], nowMs: number): Promise<"sent" | "skipped" | "failed"> {
    const fp = fingerprint(rows);
    if (fp === this.lastSent && nowMs - this.lastSentAt < SLICE_HEARTBEAT_MS) return "skipped";
    const changed = fp !== this.lastSent;
    const r = await aggregatorRequest(
      this.cfg, "PUT", `/v1/hosts/${encodeURIComponent(this.host.id())}/slice`,
      { hostName: this.host.name(), rows }, this.fetchImpl,
    );
    if (!r.ok) {
      this.trace("slice-failed", { status: r.status });
      return "failed";
    }
    this.lastSent = fp;
    this.lastSentAt = nowMs;
    if (changed) this.trace("slice", { rows: rows.map((x) => `${x.sid.slice(0, 8)}:${x.state}`) });
    return "sent";
  }
}
