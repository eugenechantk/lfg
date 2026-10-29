const help = `Usage:
  lfg notify sessions
  lfg notify --session <session-id> --status <working|completed|needs-input|blocked|reminder> --message <text> [--title <text>] [--request-id <id>]

Sends custom text to every registered iPhone/iPad and every connected LFG Mac.
Use a concrete result, blocker, or reminder. Keep the same request ID when retrying.
The receipt reports APNs acceptance, not physical delivery. LFG_NOTIFY_URL overrides the local host.`;

export async function cmdNotify(args: string[]) {
  if (!args.length || args.includes("--help") || args.includes("-h")) { console.log(help); return; }
  const base = new URL(process.env.LFG_NOTIFY_URL || "http://127.0.0.1:8766");
  if (!["localhost", "127.0.0.1", "[::1]"].includes(base.hostname) || !["http:", "https:"].includes(base.protocol) || base.username || base.password)
    throw Error("Use a local LFG host for notifications.");
  if (args.length === 1 && args[0] === "sessions") {
    const response = await fetch(new URL("/api/sessions", base), { redirect: "error", signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw Error("Could not list local sessions.");
    const data = await response.json() as { sessions: { sessionId?: string; tmuxName?: string; title?: string; cwd?: string }[] };
    console.log(JSON.stringify({ sessions: data.sessions.map(({ sessionId, tmuxName, title, cwd }) => ({ sessionId, tmuxName, title, cwd })) }));
    return;
  }
  const options: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const flag = args[i]!;
    if (!["--session", "--status", "--message", "--title", "--request-id"].includes(flag) || !args[i + 1]) throw Error(help);
    options[flag.slice(2)] = args[++i]!;
  }
  if (!options.session || !options.status || !options.message) throw Error(help);
  const requestID = options["request-id"] || crypto.randomUUID();
  // Print before sending so a timeout still leaves a safe retry identity.
  console.error(`Notification request ID: ${requestID}`);
  const response = await fetch(new URL(`/api/sessions/${encodeURIComponent(options.session)}/notify`, base), {
    method: "POST", headers: { "Content-Type": "application/json" }, redirect: "error", signal: AbortSignal.timeout(30_000),
    body: JSON.stringify({ requestID, status: options.status, message: options.message, ...(options.title ? { title: options.title } : {}) }),
  });
  const data = await response.json() as { error?: string };
  if (!response.ok) throw Error(data.error || `Notification failed (${response.status}). Retry with request ID ${requestID}.`);
  console.log(JSON.stringify(data));
}
