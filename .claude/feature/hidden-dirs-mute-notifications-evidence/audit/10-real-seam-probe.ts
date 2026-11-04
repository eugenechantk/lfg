// Real-seam probe: the sim's ACTUAL stored device record (copied from the scratch
// server's push-devices.json) + the real store module + the real session list
// (from the scratch server) driven through the real runPushTick. Only APNs send
// and pane observation are faked. Store file is a temp copy, never the live one.
const R = "/Users/eugenechan/dev/personal/lfg/src";
const { listDevices } = await import(`${R}/push/store.ts`);
const { runPushTick } = await import(`${R}/push/watcher.ts`);
const { SessionNotifications } = await import(`${R}/session-notifications.ts`);
const devices = await listDevices();
console.log("devices (from LFG_PUSH_STORE copy):", devices.map((d: any) => `${d.token.slice(0, 8)} hidden=${JSON.stringify(d.hiddenDirs ?? null)}`));
const res = await fetch("http://127.0.0.1:8792/api/sessions");
const sessions = ((await res.json()).sessions as any[]).map((s) => ({ ...s, tmuxTarget: s.tmuxTarget ?? "t" }));
console.log("real sessions:", sessions.map((s) => `${s.sessionId.slice(0, 8)} ${s.cwd}`));
let busy = true;
const sent: string[] = [];
const prior = new Map();
const deps: any = {
  sessions: async () => sessions,
  observe: async () => ({ busy, promptPresent: false, promptQuestion: null }),
  devices: listDevices,
  cfg: { key: "x", keyId: "k", teamId: "t", topic: "dev.omg.lfg" },
  send: async (d: any, p: any) => { sent.push(`${d.token.slice(0, 8)} <- ${p.sid.slice(0, 8)} cwd=${p.session?.cwd}`); return { ok: true, status: 200 }; },
  now: () => 1_000_000,
};
await runPushTick(prior, deps);
busy = false;
await runPushTick(prior, deps);
console.log("\nwatcher sends (every session busy->idle):");
for (const s of sent.sort()) console.log("  " + s);
const inboxToSim = sent.filter((s) => s.startsWith("80cab62f") && s.includes("/dev/inbox"));
console.log(`\nsim token got ${inboxToSim.length} sends for /dev/inbox sessions; got ${sent.filter((s) => s.startsWith("80cab62f")).length} total`);

// lfg notify path with the same real device record
const nsent: string[] = [];
const inbox = sessions.find((s) => s.cwd?.startsWith("/Users/eugenechan/dev/inbox"));
const visible = sessions.find((s) => s.cwd === "/Users/eugenechan/dev/personal/lfg");
const svc = new SessionNotifications(`${process.env.PROBE_DIR}/notif.json`, {
  sessions: async () => sessions, emit: () => {}, devices: listDevices,
  send: async (d: any, p: any) => { nsent.push(`${d.token.slice(0, 8)} <- ${p.sid.slice(0, 8)}`); return { ok: true, status: 200 }; },
});
await svc.ready;
const a = await svc.send(inbox.sessionId, { requestID: "probe-a", status: "completed", message: "x" });
const b = await svc.send(visible.sessionId, { requestID: "probe-b", status: "completed", message: "x" });
console.log("\nlfg notify inbox session:", JSON.stringify(a.mobile), "sends:", nsent.filter((s) => s.endsWith(inbox.sessionId.slice(0, 8))));
console.log("lfg notify lfg session:  ", JSON.stringify(b.mobile), "sends:", nsent.filter((s) => s.endsWith(visible.sessionId.slice(0, 8))));
