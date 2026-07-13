// Registry of APNs Live Activity tokens. Push-to-start tokens are device-level;
// activity update tokens are per Live Activity instance. The fleet Live Activity
// has one update token per device, not one per session.
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
    ...(input.kind === "activityUpdate" && input.sessionId ? { sessionId: input.sessionId } : {}),
    env: input.env,
    updatedAt: Date.now(),
  };
  const existing = list.find((t) => t.token === input.token);
  const next = existing
    ? list.map((t) => (t.token === input.token ? record : t))
    : [...list, record];
  await writeTokens(next);
  return record;
}

export async function lookupLiveActivityToken(token: string): Promise<LiveActivityToken | null> {
  return (await listLiveActivityTokens()).find((t) => t.token === token) ?? null;
}

export async function listPushToStartTokens(): Promise<LiveActivityToken[]> {
  return (await listLiveActivityTokens()).filter((t) => t.kind === "pushToStart");
}

export async function listActivityUpdateTokens(sessionId: string): Promise<LiveActivityToken[]> {
  return (await listLiveActivityTokens()).filter(
    (t) => t.kind === "activityUpdate" && t.sessionId === sessionId,
  );
}

export async function listFleetUpdateTokens(): Promise<LiveActivityToken[]> {
  return (await listLiveActivityTokens()).filter((t) => t.kind === "activityUpdate");
}

export async function removeLiveActivityToken(token: string): Promise<void> {
  const list = await listLiveActivityTokens();
  const next = list.filter((t) => t.token !== token);
  if (next.length !== list.length) await writeTokens(next);
}
