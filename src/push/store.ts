// Registry of devices that want APNs push notifications for session events.
// Persisted as a small JSON file so registrations survive a `lfg serve` restart.
// Deduped by APNs device token. The store path is env-overridable (LFG_PUSH_STORE)
// purely so tests can write to a temp file instead of the real data dir.
import { join, dirname } from "node:path";
import { mkdir } from "node:fs/promises";
import { PATHS } from "../config.ts";

export type PushDevice = {
  token: string; // APNs device token (hex)
  platform: "ios";
  // Which APNs host this token belongs to. A Debug build run from Xcode talks to
  // the sandbox gateway; TestFlight/App Store builds talk to production. The app
  // reports this at registration so the sender picks the right host.
  env: "sandbox" | "production";
  // Optional owner (an LFG_USERS email). Stored for a future per-user filter; the
  // v1 watcher fans out to all devices regardless.
  owner: string | null;
  createdAt: number;
  lastSeenAt: number;
};

const storePath = () =>
  process.env.LFG_PUSH_STORE ?? join(PATHS.data, "push-devices.json");

export async function listDevices(): Promise<PushDevice[]> {
  const f = Bun.file(storePath());
  if (!(await f.exists())) return [];
  try {
    return JSON.parse(await f.text()) as PushDevice[];
  } catch {
    return [];
  }
}

async function writeDevices(list: PushDevice[]): Promise<void> {
  await mkdir(dirname(storePath()), { recursive: true });
  await Bun.write(storePath(), JSON.stringify(list, null, 2));
}

export async function registerDevice(input: {
  token: string;
  env: "sandbox" | "production";
  owner?: string | null;
}): Promise<PushDevice> {
  const list = await listDevices();
  const now = Date.now();
  const existing = list.find((d) => d.token === input.token);
  const device: PushDevice = {
    token: input.token,
    platform: "ios",
    env: input.env,
    owner: input.owner ?? existing?.owner ?? null,
    createdAt: existing?.createdAt ?? now,
    lastSeenAt: now,
  };
  const next = existing
    ? list.map((d) => (d.token === input.token ? device : d))
    : [...list, device];
  await writeDevices(next);
  return device;
}

/** Remove a device (explicit unregister, or APNs told us the token is dead). */
export async function unregisterDevice(token: string): Promise<void> {
  const list = await listDevices();
  const next = list.filter((d) => d.token !== token);
  if (next.length !== list.length) await writeDevices(next);
}

export async function deviceCount(): Promise<number> {
  return (await listDevices()).length;
}
