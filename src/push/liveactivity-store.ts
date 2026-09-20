// Registry of APNs **push-to-start** tokens.
//
// There used to be a second kind, `activityUpdate` — one token per live card,
// used to address update/end. It is gone: obtaining it required iOS to wake the
// app after a push-to-start, which on an idle phone routinely never happened, and
// a dead Live Activity token answers 200 so the server could not even tell it was
// shouting into a void. Update and end now go over a broadcast channel
// (`broadcast.ts`), which needs no wake and no registration.
//
// Push-to-start tokens remain, because broadcast cannot START an activity.
// Persisted as a small JSON file following the device push store conventions.
import { dirname, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { PATHS } from "../config.ts";

export type LiveActivityTokenKind = "pushToStart";

export type LiveActivityToken = {
  token: string;
  kind: LiveActivityTokenKind;
  env: "sandbox" | "production";
  updatedAt: number;
};

const storePath = () =>
  process.env.LFG_LIVE_ACTIVITY_STORE ?? join(PATHS.data, "live-activity-tokens.json");

export async function listLiveActivityTokens(): Promise<LiveActivityToken[]> {
  const f = Bun.file(storePath());
  if (!(await f.exists())) return [];
  try {
    const parsed = JSON.parse(await f.text()) as LiveActivityToken[];
    if (!Array.isArray(parsed)) return [];
    // Legacy `activityUpdate` rows are dropped on READ, not merely on the next
    // write. A store written before the broadcast channel can hold dozens of them
    // (the Air's held 35, untouched since July) and they are pure liability now:
    // they address nothing, and the old supersede rule that used to bound them is
    // gone with the kind itself.
    return parsed.filter((t) => t?.kind === "pushToStart");
  } catch {
    return [];
  }
}

async function writeTokens(list: LiveActivityToken[]): Promise<void> {
  await mkdir(dirname(storePath()), { recursive: true });
  await Bun.write(storePath(), JSON.stringify(list, null, 2));
}

export async function upsertLiveActivityToken(input: {
  token: string;
  kind?: LiveActivityTokenKind;
  env: "sandbox" | "production";
}): Promise<LiveActivityToken> {
  const list = await listLiveActivityTokens();
  const record: LiveActivityToken = {
    token: input.token,
    kind: "pushToStart",
    env: input.env,
    updatedAt: Date.now(),
  };
  const existing = list.find((t) => t.token === input.token);
  const replaced = existing
    ? list.map((t) => (t.token === input.token ? record : t))
    : [...list, record];
  await writeTokens(capPushToStart(replaced));
  return record;
}

/**
 * At most this many `pushToStart` tokens per APNs environment, newest first.
 *
 * These tokens rot rather than die: dev/simulator builds each mint one, a stale
 * one rarely answers 410 promptly, and the live store reached NINETEEN — every
 * `start` decision blasted all of them (slow, and stale-but-live tokens risk
 * duplicate cards). Newest-N keeps the real install's token by construction —
 * push-to-start re-registers on every app launch, so the device that matters is
 * always among the newest — where age-based pruning could strand a device that
 * simply hasn't opened the app lately. Per-env so churning sandbox dev builds
 * can never evict a production (TestFlight) token.
 */
export const MAX_PUSH_TO_START_PER_ENV = 3;

function capPushToStart(list: LiveActivityToken[]): LiveActivityToken[] {
  const keep = new Set<string>();
  for (const env of ["sandbox", "production"] as const) {
    [...list]
      .filter((t) => t.kind === "pushToStart" && t.env === env)
      .sort((a, b) => b.updatedAt - a.updatedAt)
      .slice(0, MAX_PUSH_TO_START_PER_ENV)
      .forEach((t) => keep.add(t.token));
  }
  return list.filter((t) => t.kind !== "pushToStart" || keep.has(t.token));
}

export async function lookupLiveActivityToken(token: string): Promise<LiveActivityToken | null> {
  return (await listLiveActivityTokens()).find((t) => t.token === token) ?? null;
}

export async function listPushToStartTokens(): Promise<LiveActivityToken[]> {
  // Capped at read too, so a store that grew oversized before this cap existed
  // (or was edited on disk) is bounded on the next server start — not only
  // after the next registration happens to rewrite it.
  return capPushToStart(await listLiveActivityTokens()).filter((t) => t.kind === "pushToStart");
}

export async function removeLiveActivityToken(token: string): Promise<void> {
  const list = await listLiveActivityTokens();
  const next = list.filter((t) => t.token !== token);
  if (next.length !== list.length) await writeTokens(next);
}
