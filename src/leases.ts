import { mkdir, readFile, rename, unlink } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { basename, dirname, join } from "node:path";
import { hostInfo } from "./hostinfo.ts";

export const LEASE_FRESH_MS = 90_000;

export type LeaseRecord = {
  hostId: string;
  pid: number;
  acquiredAt: number;
  heartbeatAt: number;
};

export type LeaseManagerDeps = {
  hostId: () => string;
  now: () => number;
  resolveTranscript: (sessionId: string) => Promise<string | null>;
};

export function leasePathForTranscript(sessionId: string, transcriptPath: string): string {
  return join(dirname(transcriptPath), `${sessionId}.lease.json`);
}

export function parseLease(raw: string): LeaseRecord | null {
  try {
    const x = JSON.parse(raw) as Partial<LeaseRecord>;
    if (
      typeof x.hostId !== "string" ||
      !x.hostId ||
      typeof x.pid !== "number" ||
      !Number.isFinite(x.pid) ||
      typeof x.acquiredAt !== "number" ||
      !Number.isFinite(x.acquiredAt) ||
      typeof x.heartbeatAt !== "number" ||
      !Number.isFinite(x.heartbeatAt)
    ) {
      return null;
    }
    return {
      hostId: x.hostId,
      pid: x.pid,
      acquiredAt: x.acquiredAt,
      heartbeatAt: x.heartbeatAt,
    };
  } catch {
    return null;
  }
}

export function leaseIsFresh(lease: LeaseRecord, now: number): boolean {
  return now - lease.heartbeatAt < LEASE_FRESH_MS;
}

async function defaultResolveTranscript(sessionId: string): Promise<string | null> {
  const sessions = await import("./sessions.ts");
  return sessions.resolveTranscript(sessionId);
}

async function atomicWriteJson(path: string, value: unknown): Promise<void> {
  const dir = dirname(path);
  await mkdir(dir, { recursive: true });
  const tmp = join(
    dir,
    `.${basename(path)}.${process.pid}.${Date.now()}.${randomBytes(4).toString("hex")}.tmp`,
  );
  try {
    await Bun.write(tmp, JSON.stringify(value, null, 2));
    await rename(tmp, path);
  } catch (e) {
    try {
      await unlink(tmp);
    } catch {}
    throw e;
  }
}

export function createLeaseManager(
  deps: Partial<LeaseManagerDeps> = {},
): {
  leasePath: (sessionId: string) => Promise<string | null>;
  readLease: (sessionId: string) => Promise<LeaseRecord | null>;
  acquireLease: (sessionId: string, pid: number) => Promise<boolean>;
  renewLease: (sessionId: string) => Promise<boolean>;
  releaseLease: (sessionId: string) => Promise<boolean>;
  foreignFresh: (sessionId: string) => Promise<string | null>;
  foreignFreshAt: (sessionId: string, transcriptPath: string) => Promise<string | null>;
} {
  const hostId = deps.hostId ?? (() => hostInfo().hostId);
  const now = deps.now ?? (() => Date.now());
  const resolveTranscript = deps.resolveTranscript ?? defaultResolveTranscript;

  const leasePath = async (sessionId: string): Promise<string | null> => {
    try {
      const transcript = await resolveTranscript(sessionId);
      return transcript ? leasePathForTranscript(sessionId, transcript) : null;
    } catch {
      return null;
    }
  };

  const readLeaseAt = async (path: string): Promise<LeaseRecord | null> => {
    try {
      return parseLease(await readFile(path, "utf8"));
    } catch {
      return null;
    }
  };

  const readLease = async (sessionId: string): Promise<LeaseRecord | null> => {
    const path = await leasePath(sessionId);
    return path ? readLeaseAt(path) : null;
  };

  const acquireLease = async (sessionId: string, pid: number): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const t = now();
    try {
      await atomicWriteJson(path, {
        hostId: hostId(),
        pid,
        acquiredAt: t,
        heartbeatAt: t,
      } satisfies LeaseRecord);
      return true;
    } catch {
      return false;
    }
  };

  const renewLease = async (sessionId: string): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const lease = await readLeaseAt(path);
    if (!lease || lease.hostId !== hostId()) return false;
    try {
      await atomicWriteJson(path, { ...lease, heartbeatAt: now() } satisfies LeaseRecord);
      return true;
    } catch {
      return false;
    }
  };

  const releaseLease = async (sessionId: string): Promise<boolean> => {
    const path = await leasePath(sessionId);
    if (!path) return false;
    const lease = await readLeaseAt(path);
    if (!lease || lease.hostId !== hostId()) return false;
    try {
      await unlink(path);
      return true;
    } catch {
      return false;
    }
  };

  const foreignHostIfFresh = (lease: LeaseRecord | null): string | null => {
    if (!lease || !leaseIsFresh(lease, now())) return null;
    const ours = hostId();
    return lease.hostId !== ours ? lease.hostId : null;
  };

  const foreignFresh = async (sessionId: string): Promise<string | null> => {
    return foreignHostIfFresh(await readLease(sessionId));
  };

  const foreignFreshAt = async (sessionId: string, transcriptPath: string): Promise<string | null> => {
    return foreignHostIfFresh(await readLeaseAt(leasePathForTranscript(sessionId, transcriptPath)));
  };

  return { leasePath, readLease, acquireLease, renewLease, releaseLease, foreignFresh, foreignFreshAt };
}

const defaultManager = createLeaseManager();

export const leasePath = defaultManager.leasePath;
export const readLease = defaultManager.readLease;
export const acquireLease = defaultManager.acquireLease;
export const renewLease = defaultManager.renewLease;
export const releaseLease = defaultManager.releaseLease;
export const foreignFresh = defaultManager.foreignFresh;
export const foreignFreshAt = defaultManager.foreignFreshAt;
