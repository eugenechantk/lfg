// Registry of APNs Live Activity tokens. Both kinds are device-level: there is
// exactly one (fleet) Live Activity per device, so update tokens need no session
// keying. `sessionId` is still tolerated on input so an older client that sends
// it does not fail registration.
// Persisted as a small JSON file following the device push store conventions.
import { dirname, join } from "node:path";
import { mkdir } from "node:fs/promises";
import { PATHS } from "../config.ts";

export type LiveActivityTokenKind = "pushToStart" | "activityUpdate";

export type LiveActivityToken = {
  token: string;
  kind: LiveActivityTokenKind;
  sessionId?: string;
  env: "sandbox" | "production";
  updatedAt: number;
};

const storePath = () =>
  process.env.LFG_LIVE_ACTIVITY_STORE ?? join(PATHS.data, "live-activity-tokens.json");

export async function listLiveActivityTokens(): Promise<LiveActivityToken[]> {
  const f = Bun.file(storePath());
  if (!(await f.exists())) return [];
  try {
    return JSON.parse(await f.text()) as LiveActivityToken[];
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
  kind: LiveActivityTokenKind;
  sessionId?: string;
  env: "sandbox" | "production";
}): Promise<LiveActivityToken> {
  const list = await listLiveActivityTokens();
  const record: LiveActivityToken = {
    token: input.token,
    kind: input.kind,
    // Recorded for debugging only — nothing selects on it any more.
    ...(input.kind === "activityUpdate" && input.sessionId ? { sessionId: input.sessionId } : {}),
    env: input.env,
    updatedAt: Date.now(),
  };
  const existing = list.find((t) => t.token === input.token);
  const replaced = existing
    ? list.map((t) => (t.token === input.token ? record : t))
    : [...list, record];
  await writeTokens(supersede(replaced, record));
  return record;
}

/**
 * A device has exactly one fleet Live Activity, so it has exactly one live
 * `activityUpdate` token per APNs environment. Registering a new one means the
 * previous card (or the previous rotation of this one) is gone — drop it.
 *
 * WHY THIS IS NOT JUST HOUSEKEEPING. A dead Live Activity token does not answer
 * `410`/`BadDeviceToken`; APNs accepts it and drops the payload. `isDeadApnsToken`
 * in `watcher.ts` therefore never fires for one, nothing prunes it, and — worse —
 * `sendLiveActivityToTokens` counts its **200** as a delivery. One corpse in the
 * list is enough to convince the watcher its update landed, so it advances
 * `active.current`, never re-sends `start`, and the real card silently stops
 * updating until the app is opened. Keeping the list to the one token that can
 * actually be live is what makes that 200 mean something.
 * See `.claude/diagnosis-live-activity-background-updates.md`.
 *
 * Scoped to `env` because a debug (sandbox) and a TestFlight (production) install
 * are different cards. `pushToStart` is deliberately exempt: it is a property of
 * the install, not of any one activity, and outlives every card.
 *
 * KNOWN LIMIT: two devices on the same env would fight over the single slot. The
 * registration payload carries no device identifier, so that cannot be
 * distinguished here today; it needs a device id on the wire.
 */
function supersede(list: LiveActivityToken[], record: LiveActivityToken): LiveActivityToken[] {
  if (record.kind !== "activityUpdate") return list;
  return list.filter(
    (t) =>
      t.token === record.token || t.kind !== "activityUpdate" || t.env !== record.env,
  );
}

export async function lookupLiveActivityToken(token: string): Promise<LiveActivityToken | null> {
  return (await listLiveActivityTokens()).find((t) => t.token === token) ?? null;
}

export async function listPushToStartTokens(): Promise<LiveActivityToken[]> {
  return (await listLiveActivityTokens()).filter((t) => t.kind === "pushToStart");
}

export async function listActivityUpdateTokens(): Promise<LiveActivityToken[]> {
  return (await listLiveActivityTokens()).filter((t) => t.kind === "activityUpdate");
}

export async function removeLiveActivityToken(token: string): Promise<void> {
  const list = await listLiveActivityTokens();
  const next = list.filter((t) => t.token !== token);
  if (next.length !== list.length) await writeTokens(next);
}
