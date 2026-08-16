// Map a live process to its tmux pane and inject input. Claude Code sessions
// run inside tmux panes; we discover the `claude` pid via pgrep/proc, walk up
// its parent chain to the pane's top process, and `send-keys` into that pane.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { ppidOf as procPpidOf, ttyOf, normalizeTty } from "./procinfo";

// Known-good Claude model to launch with when a caller doesn't specify one.
// Never launch a managed `claude` bare — see spawnManagedSession. Pin the
// current Opus ID instead of the alias so new sessions don't inherit a stale
// provider default.
export const DEFAULT_MODEL = "claude-opus-5";

// Geometry for every tmux session lfg owns. NOT cosmetic — it is the only
// reason a question's preamble is readable in the client at all.
//
// Claude Code does not flush the assistant turn containing an interactive tool
// (AskUserQuestion, a permission prompt, plan approval) to its transcript JSONL
// until the user answers. While the question is live, the prose the model wrote
// right before asking exists ONLY in Claude's memory and on the pane — it is on
// disk nowhere (verified: a phrase unique to that prose matched nothing under
// ~/.claude). `parsePrompt`'s `context` scrape is therefore the only way the
// client can show it, and the scrape can only see what fits on the pane.
//
// And it cannot see more: Claude Code runs in the ALTERNATE SCREEN, so the pane
// has `history_size == 0` and `capture-pane -S -500` returns exactly the same
// rows as a plain capture. There is no scrollback to fall back on.
//
// At tmux's default 80x24 a two-paragraph preamble plus a selector box does not
// fit, so the top of the turn — including the `⏺` bullet `contextAbovePrompt`
// keys off — was simply gone, and the client got a mid-sentence fragment or
// nothing. Hence "the response before the question is cut off". Rows are what
// matter; columns only reduce wrapping. Capture cost barely moves, because
// `capture-pane` emits an unused row as an empty string, not as padding.
export const PANE_COLS = 120;
export const PANE_ROWS = 200;

// Size flags for `tmux new-session`. tmux records these as the session's
// `default-size`, so a detached session keeps them.
export function paneSizeArgs(): string[] {
  return ["-x", String(PANE_COLS), "-y", String(PANE_ROWS)];
}

/**
 * Restore a pane to {@link PANE_ROWS} when it has been shrunk.
 *
 * Load-bearing, and the reason earlier fixes here regressed: tmux does NOT
 * restore `default-size` after a client detaches. Measured —
 *
 *   before: w=200 h=60 → during attach: w=80 h=23 → after detach: w=80 h=23
 *
 * so a single visit to the Terminal tab (or any `tmux attach`) permanently
 * re-breaks preamble capture for that session. Creating sessions at the right
 * size is therefore not enough; the size has to be reconciled.
 *
 * Skips attached sessions on purpose — resizing a window a human is looking at
 * would yank their terminal. They get the size back when they detach.
 *
 * STICKY SIDE EFFECT, reverted elsewhere: per tmux(1), `resize-window` "will
 * automatically set window-size to manual in the window options", and manual
 * means the window stops following attached clients FOREVER. So every session
 * this touches would otherwise attach at a fixed 120 cols regardless of the
 * terminal — long lines run off the right edge instead of wrapping. The owner of
 * undoing that is the attach path: `Opener.attachCommand` in
 * desktop/LFGSessions.swift flips `window-size` back to `latest` ahead of every
 * `attach-session`. The two halves are self-healing — on detach the window keeps
 * the client's short size, so the next tick lands back here. See
 * .claude/diagnosis-mosh-attach-window-width-20260811.md.
 *
 * Returns true when a resize was issued.
 */
export function ensurePaneRows(target: string, minRows = PANE_ROWS): boolean {
  try {
    const r = Bun.spawnSync([
      "tmux", "display-message", "-p", "-t", target,
      "#{window_height} #{session_attached}",
    ]);
    if (r.exitCode !== 0) return false;
    const [h, attached] = new TextDecoder().decode(r.stdout).trim().split(/\s+/);
    if (Number(attached) > 0) return false; // a human is looking at it
    if (!(Number(h) < minRows)) return false; // already tall enough (or unreadable)
    const resize = Bun.spawnSync([
      "tmux", "resize-window", "-t", target, "-x", String(PANE_COLS), "-y", String(minRows),
    ]);
    return resize.exitCode === 0;
  } catch {
    return false;
  }
}

// claude shows a blocking "Is this a project you trust?" dialog the first time
// it opens an untrusted cwd. It is NOT bypassed by --dangerously-skip-permissions
// and it renders BEFORE the TUI starts — so a spawned session hangs on it and
// never writes its pidfile, which means listSessions() can't resolve it and it
// silently never appears in the session list. Pre-accept trust for `cwd` in
// ~/.claude.json so the dialog never fires. Idempotent: a no-op once trusted.
export function ensureFolderTrusted(cwd: string): void {
  try {
    const cfgPath = `${homedir()}/.claude.json`;
    if (!existsSync(cfgPath)) return;
    const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));
    cfg.projects ??= {};
    const p = cfg.projects[cwd] ?? {};
    if (p.hasTrustDialogAccepted === true) return; // already trusted
    p.hasTrustDialogAccepted = true;
    p.hasCompletedProjectOnboarding = true;
    if (!p.projectOnboardingSeenCount) p.projectOnboardingSeenCount = 1;
    cfg.projects[cwd] = p;
    writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
  } catch {
    // best-effort — if we can't patch the config the worst case is the old hang
  }
}

// Resolve the `claude` executable to an absolute path. We must NOT rely on a
// bare `claude` in the spawn: when lfg runs as a systemd service its PATH
// often lacks ~/.local/bin, so `tmux new-session … claude` can't exec claude
// and the session dies on the spot (looks like "can't create a session"). Bun
// .which() honours the current PATH; fall back to the known install locations.
let _claudeBin: string | null = null;
export function claudeBin(): string {
  if (_claudeBin) return _claudeBin;
  const onPath = Bun.which("claude");
  if (onPath) return (_claudeBin = onPath);
  const home = process.env.HOME ?? homedir();
  for (const p of [
    `${home}/.local/bin/claude`,
    `${home}/.bun/bin/claude`,
    "/usr/local/bin/claude",
  ]) {
    if (existsSync(p)) return (_claudeBin = p);
  }
  return (_claudeBin = "claude"); // last resort: let the failure surface
}

let _codexBin: string | null = null;
export function codexBin(): string {
  if (_codexBin) return _codexBin;
  const onPath = Bun.which("codex");
  if (onPath) return (_codexBin = onPath);
  const home = process.env.HOME ?? homedir();
  for (const p of [
    `${home}/.local/bin/codex`,
    `${home}/.bun/bin/codex`,
    "/usr/local/bin/codex",
  ]) {
    if (existsSync(p)) return (_codexBin = p);
  }
  return (_codexBin = "codex");
}

// Spawned agents run with cwd set to one repo, but Claude Code scopes tool
// access to the cwd tree — which sandboxes the agent to that single repo. The
// agents are trusted operators of this whole box, so grant tool access to the
// repos root (every repo under LFG_REPOS_ROOT) via --add-dir. Override the root
// with LFG_REPOS_ROOT if the repos live elsewhere.
function reposRoot(): string {
  return process.env.LFG_REPOS_ROOT ?? `${homedir()}/repos`;
}

// listSessions() resolves a tmux target for every live proc, and each call used
// to rebuild the whole pane map with a fresh `tmux list-panes -a` spawn — dozens
// of redundant subprocess spawns per pass, all blocking the single event loop.
// Memoize the map for a short TTL so one pass shares one snapshot.
const PANE_MAP_TTL_MS = 1000;
export interface PaneInfo {
  target: string;
  tty: string | null;
}
let paneMapSnap: { at: number; map: Map<number, PaneInfo> } | null = null;
function paneMap(): Map<number, PaneInfo> {
  const now = Date.now();
  if (paneMapSnap && now - paneMapSnap.at < PANE_MAP_TTL_MS) return paneMapSnap.map;
  const m = buildPaneMap();
  paneMapSnap = { at: now, map: m };
  return m;
}

// Parse `tmux list-panes -a` output into pane_pid → {target, tty}. Split on the
// LAST two spaces, not the first: a pane target never contains a space but this
// keeps the parse anchored to the fixed-arity tail regardless of format order.
export function parsePaneList(out: string): Map<number, PaneInfo> {
  const m = new Map<number, PaneInfo>();
  for (const line of out.split("\n")) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const pid = Number(parts[0]);
    const target = parts[1];
    const tty = normalizeTty(parts[2]);
    if (pid && target) m.set(pid, { target, tty });
  }
  return m;
}

function buildPaneMap(): Map<number, PaneInfo> {
  try {
    const r = Bun.spawnSync([
      "tmux",
      "list-panes",
      "-a",
      "-F",
      "#{pane_pid} #{session_name}:#{window_index}.#{pane_index} #{pane_tty}",
    ]);
    return parsePaneList(new TextDecoder().decode(r.stdout));
  } catch {
    return new Map();
  }
}

// Parent pid for the pane→proc parent-chain walk. Platform branch (Linux /proc,
// macOS ps) lives in ./procinfo.
function ppidOf(pid: number): number | null {
  return procPpidOf(pid);
}

// Resolve a live pid to the tmux pane whose keystrokes reach it, or null.
//
// Deliberately a pure ancestry walk: a pane's keys do NOT always go to the
// process holding its tty. Claude Code's branch view runs the fronted
// conversation in a DETACHED child (spawned via the transient daemon, no
// controlling terminal) and proxies the pane's input to it — so gating this on
// a tty match made every branch conversation unsendable. Several pids therefore
// legitimately resolve to one pane; picking which of them actually fronts it is
// resolveePaneOwners()' job in sessions.ts, not this function's.
export function tmuxTargetForPid(pid: number | null): string | null {
  if (!pid) return null;
  const panes = paneMap();
  let cur: number | null = pid;
  for (let i = 0; i < 12 && cur && cur > 1; i++) {
    const pane = panes.get(cur);
    if (pane) return pane.target;
    cur = ppidOf(cur);
  }
  return null;
}

// Controlling terminal of the process owning `target`'s pane, or null. Used as
// a last-resort tiebreak when no candidate for a pane looks like a live
// conversation.
export function paneTtyForTarget(target: string): string | null {
  for (const pane of paneMap().values()) {
    if (pane.target === target) return pane.tty;
  }
  return null;
}

export function tmuxHasSession(name: string): boolean {
  try {
    return Bun.spawnSync(["tmux", "has-session", "-t", `=${name}`]).exitCode === 0;
  } catch {
    return false;
  }
}

// Close a Claude session by killing its pane. The `claude` process gets a
// SIGHUP and exits, so the session drops out of the list on the next poll. We
// kill the pane (not the whole tmux session) so any other panes the user has
// in that session survive.
export function tmuxKillPane(target: string): boolean {
  try {
    return Bun.spawnSync(["tmux", "kill-pane", "-t", target]).exitCode === 0;
  } catch {
    return false;
  }
}

// Tear down a whole tmux session by name — the clean teardown for a session
// lfg started itself (one session == one managed claude, no sibling panes to
// preserve, unlike tmuxKillPane).
export function tmuxKillSession(name: string): boolean {
  try {
    return Bun.spawnSync(["tmux", "kill-session", "-t", `=${name}`]).exitCode === 0;
  } catch {
    return false;
  }
}

// pane_pid of a session's first pane. When the session was created with a
// command (no shell wrapper) this is the command's pid directly.
export function panePidForSession(name: string): number | null {
  try {
    const r = Bun.spawnSync([
      "tmux",
      "list-panes",
      "-t",
      `=${name}`,
      "-F",
      "#{pane_pid}",
    ]);
    if (r.exitCode !== 0) return null;
    const pid = Number(new TextDecoder().decode(r.stdout).split("\n")[0]?.trim());
    return Number.isFinite(pid) && pid > 0 ? pid : null;
  } catch {
    return null;
  }
}

// Launch an interactive `claude` in a fresh detached tmux session so the rest
// of lfg (session list, prompt detection, send/answer) can drive it. The
// initial instruction is passed as claude's positional prompt arg (after a `--`
// so the variadic --add-dir doesn't eat it), which the TUI auto-submits on
// boot — robust, unlike send-keys which races the splash screen and silently
// drops keys on a cold start. The instruction points at a brief file rather
// than inlining a huge prompt.
export function spawnAgentSession(opts: {
  name: string;
  cwd: string;
  briefPath: string;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  ensureFolderTrusted(opts.cwd);
  const create = Bun.spawnSync([
    "tmux",
    "new-session",
    "-d",
    ...paneSizeArgs(),
    "-s",
    opts.name,
    "-c",
    opts.cwd,
    claudeBin(),
    "--dangerously-skip-permissions",
    "--add-dir",
    reposRoot(),
    // `--` terminates option parsing: --add-dir is variadic and otherwise
    // greedily swallows the positional prompt as a second directory, leaving
    // the TUI at an empty composer (the brief never gets submitted).
    "--",
    `Read the task brief at ${opts.briefPath} and carry it out end-to-end.`,
  ]);
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Start an interactive `claude` in a fresh detached tmux session that lfg
// owns and drives. Like spawnAgentSession but for a user-initiated session: the
// first prompt is optional (omit it to land at an empty composer). The caller
// resolves the new sessionId from panePidForSession(name) once claude writes
// its pidfile.
// Build the `tmux new-session … claude …` argv for a managed session. Pure and
// side-effect-free (no spawn, no trust prompt) so the flag wiring — resume,
// fork, model, prompt terminator — is unit-testable without launching anything.
export function managedSessionArgv(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model?: string;
  resume?: string;
  fork?: boolean;
}): string[] {
  const argv = ["tmux", "new-session", "-d", ...paneSizeArgs(), "-s", opts.name, "-c", opts.cwd,
    claudeBin(), "--dangerously-skip-permissions", "--add-dir", reposRoot()];
  // Resume the prior conversation when asked. Placed before --model so the flags
  // read like relaunchSessionWithModel's argv; order is irrelevant to claude.
  if (opts.resume && opts.resume.trim()) {
    argv.push("--resume", opts.resume.trim());
    // Branch instead of revive: fork mints a new id from the resumed history.
    if (opts.fork) argv.push("--fork-session");
  }
  // ALWAYS pin a model. A bare `claude` inherits Claude Code's saved global
  // default, which can silently rot — when Anthropic retires/disables that
  // model (e.g. the Fable off-switch), every inheriting session boots straight
  // into "model unavailable" and freezes, replaying the error on every turn.
  // An explicit --model is the only thing that overrides it. DEFAULT_MODEL is a
  // known-good fallback when the caller didn't pick one.
  argv.push("--model", opts.model || DEFAULT_MODEL);
  // `--` terminates option parsing so the variadic --add-dir can't swallow the
  // positional prompt as a second directory (which strands the new session at
  // an empty composer — the first message never gets submitted).
  if (opts.prompt && opts.prompt.trim()) argv.push("--", opts.prompt);
  return argv;
}

export function spawnManagedSession(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model?: string;
  // When set, resume the on-disk transcript with this sessionId (`claude
  // --resume <id>`) instead of starting a fresh conversation — the way lfg
  // brings a closed/dead session back after the box (and its tmux server +
  // claude procs) was rebooted. Claude continues the conversation into a NEW
  // sessionId/transcript, so the caller resolves the live id from the pidfile
  // afterwards (same as a fresh spawn). The full prior history is preserved.
  resume?: string;
  // When set alongside `resume`, append `--fork-session` so claude mints a NEW
  // session id from the resumed history instead of reusing the original — a
  // branch, not a revive. The original transcript is left untouched, so the
  // source session (live or closed) is unaffected. Ignored without `resume`.
  fork?: boolean;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  ensureFolderTrusted(opts.cwd);
  const create = Bun.spawnSync(managedSessionArgv(opts));
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Switch a running Claude session's model by RELAUNCHING its pane on the new
// model, resuming the same transcript (`--resume <id>`). This is the heavy
// hammer for a session whose model became invalid mid-flight: when the launch
// model is unavailable, Claude Code rejects every turn *before* it processes an
// injected `/model` slash command, so the in-place switch (see serve's /model
// endpoint) silently no-ops ("Kept model as <dead model>"). A fresh process
// with an explicit --model is the only thing that takes. `--resume` preserves
// the full conversation, so the build picks up where it froze. respawn-pane
// keeps the same tmux pane/name, so the managed registry and live view stay
// bound. No prompt is re-submitted — it lands at the composer, ready to go.
export function relaunchSessionWithModel(opts: {
  tmuxTarget: string;
  cwd: string;
  sessionId: string;
  model: string;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  ensureFolderTrusted(opts.cwd);
  const r = Bun.spawnSync([
    "tmux", "respawn-pane", "-k", "-c", opts.cwd, "-t", opts.tmuxTarget,
    claudeBin(), "--dangerously-skip-permissions", "--add-dir", reposRoot(),
    "--resume", opts.sessionId, "--model", opts.model,
  ]);
  if (r.exitCode !== 0)
    return { ok: false, error: dec.decode(r.stderr) || "respawn-pane failed" };
  return { ok: true };
}

export function managedCodexSessionArgv(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model?: string;
  resume?: string;
  fork?: boolean;
}): string[] {
  const argv = [
    "tmux",
    "new-session",
    "-d",
    ...paneSizeArgs(),
    "-s",
    opts.name,
    "-c",
    opts.cwd,
    codexBin(),
    "--cd",
    opts.cwd,
    "--sandbox",
    "danger-full-access",
    "--ask-for-approval",
    "never",
    // codex gates hooks behind a per-entry `trusted_hash` in config.toml, so a
    // hook file dropped in by `scripts/install-agent-hooks.py` silently does NOT
    // run — measured: codex exits 0, writes its rollout, and fires nothing.
    // That leaves codex sessions without the turn-state and SessionEnd signals
    // Claude Code gets, so `closed` falls back to the 90s lease expiry.
    //
    // Trusting them here is defensible precisely because lfg AUTHORED the hook
    // file it is trusting — this is not accepting a third party's code. The
    // shell aliases (`codexy` in ~/.zshrc) pass the same flag for the same
    // reason, so hand-started and lfg-started sessions behave identically.
    "--dangerously-bypass-hook-trust",
    "--add-dir",
    reposRoot(),
  ];
  if (opts.model && !(opts.resume && !opts.fork)) argv.push("--model", opts.model);
  if (opts.resume && opts.resume.trim()) {
    argv.push(opts.fork ? "fork" : "resume", opts.resume.trim());
    if (opts.prompt && opts.prompt.trim()) argv.push(opts.prompt);
  } else if (opts.prompt && opts.prompt.trim()) {
    argv.push("--", opts.prompt);
  }
  return argv;
}

export function spawnManagedCodexSession(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model?: string;
  resume?: string;
  fork?: boolean;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  const create = Bun.spawnSync(managedCodexSessionArgv(opts));
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Spawn a headless "aisdk" session: the lfg `aisdk-session` harness, supervised
// by a tmux session. The pane is only a lifecycle handle (survives serve restarts
// + reuses tmuxKillSession teardown) — I/O happens via the registry/command files
// and the transcript, not the pane. We run it with the same bun runtime that's
// running serve, pointed at this repo's cli.ts.
export function spawnManagedAisdkSession(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model: string;
  sessionId: string;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  // The provider drives the bundled claude binary, which still honors the trust
  // dialog — pre-accept it so the first turn doesn't hang.
  ensureFolderTrusted(opts.cwd);
  // Spawn the harness module directly (not via the lfg CLI) so it has no
  // dependency on the rest of the command surface.
  const harnessPath = `${import.meta.dir}/agents/backends/aisdk-session.ts`;
  const argv = [
    "tmux", "new-session", "-d", ...paneSizeArgs(), "-s", opts.name, "-c", opts.cwd,
    process.execPath, harnessPath,
    "--session", opts.sessionId,
    "--model", opts.model,
    "--cwd", opts.cwd,
    "--tmux", opts.name,
  ];
  if (opts.prompt && opts.prompt.trim()) argv.push("--", opts.prompt);
  const create = Bun.spawnSync(argv);
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Spawn a headless "codex-aisdk" session: the lfg codex-aisdk-session harness,
// supervised by a tmux session. Mirrors spawnManagedAisdkSession exactly except
// it points at the codex harness and passes the control-plane KEY (--key) rather
// than a deterministic --session id — codex assigns its thread id only after the
// first turn, so the key is all we know up front (see the harness header).
export function spawnManagedCodexAisdkSession(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model: string;
  key: string;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  // Harmless for codex: ensureFolderTrusted only patches ~/.claude.json and is a
  // no-op when that file (or the project entry) is absent. Codex doesn't gate on
  // it, but keeping it costs nothing and keeps this in lockstep with the Claude
  // spawn helper.
  ensureFolderTrusted(opts.cwd);
  // Spawn the harness module directly (not via the lfg CLI) so it has no
  // dependency on the rest of the command surface.
  const harnessPath = `${import.meta.dir}/agents/backends/codex-aisdk-session.ts`;
  const argv = [
    "tmux", "new-session", "-d", ...paneSizeArgs(), "-s", opts.name, "-c", opts.cwd,
    process.execPath, harnessPath,
    "--key", opts.key,
    "--model", opts.model,
    "--cwd", opts.cwd,
    "--tmux", opts.name,
  ];
  if (opts.prompt && opts.prompt.trim()) argv.push("--", opts.prompt);
  const create = Bun.spawnSync(argv);
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Spawn a headless "opencode" session: the lfg opencode-aisdk-session harness,
// supervised by a tmux session. Mirrors spawnManagedCodexAisdkSession exactly
// except it points at the opencode harness. Like codex-aisdk it passes a
// control-plane KEY (--key) — but for opencode the key is ALSO the transcript id
// (the harness owns the transcript file it writes), so serve can treat the
// returned sessionId as == key (see the harness header).
export function spawnManagedOpencodeAisdkSession(opts: {
  name: string;
  cwd: string;
  prompt?: string;
  model: string;
  key: string;
}): { ok: boolean; error?: string } {
  const dec = new TextDecoder();
  // Harmless for opencode: ensureFolderTrusted only patches ~/.claude.json and
  // is a no-op when that file (or the project entry) is absent. Kept in lockstep
  // with the other AI-SDK spawn helpers.
  ensureFolderTrusted(opts.cwd);
  // Spawn the harness module directly (not via the lfg CLI) so it has no
  // dependency on the rest of the command surface.
  const harnessPath = `${import.meta.dir}/agents/backends/opencode-aisdk-session.ts`;
  const argv = [
    "tmux", "new-session", "-d", ...paneSizeArgs(), "-s", opts.name, "-c", opts.cwd,
    process.execPath, harnessPath,
    "--key", opts.key,
    "--model", opts.model,
    "--cwd", opts.cwd,
    "--tmux", opts.name,
  ];
  if (opts.prompt && opts.prompt.trim()) argv.push("--", opts.prompt);
  const create = Bun.spawnSync(argv);
  if (create.exitCode !== 0)
    return { ok: false, error: dec.decode(create.stderr) || "new-session failed" };
  return { ok: true };
}

// Codex 0.135 can show an update selector before the composer, which strands a
// dashboard-spawned pane until someone manually presses "Skip". Dismiss only
// that exact startup prompt; normal permission/question selectors are left for
// the dashboard's prompt-answer flow.
export function dismissCodexUpdatePrompt(target: string): boolean {
  const pane = capturePane(target);
  if (!pane || !/Update available!/i.test(pane) || !/\b2\.\s+Skip\b/.test(pane))
    return false;
  Bun.spawnSync(["tmux", "send-keys", "-t", target, "-l", "2"]);
  Bun.spawnSync(["tmux", "send-keys", "-t", target, "Enter"]);
  return true;
}

export function capturePane(target: string): string | null {
  try {
    const r = Bun.spawnSync(["tmux", "capture-pane", "-t", target, "-p"]);
    if (r.exitCode !== 0) return null;
    return new TextDecoder().decode(r.stdout);
  } catch {
    return null;
  }
}

// Minimal counting semaphore: bounds how many async child processes run at once
// so a burst of pollers can't fork an unbounded number of `tmux` children.
class Semaphore {
  private active = 0;
  private waiters: Array<() => void> = [];
  constructor(private readonly max: number) {}
  async run<T>(fn: () => Promise<T>): Promise<T> {
    if (this.active >= this.max) {
      await new Promise<void>((res) => this.waiters.push(res));
    }
    this.active++;
    try {
      return await fn();
    } finally {
      this.active--;
      this.waiters.shift()?.();
    }
  }
}

// The SSE poll loop scrapes every pane on a 700ms/1s tick, for every connected
// client. Doing that with the synchronous capturePane() blocks the single event
// loop for the child's lifetime — dozens of clients × panes stalls all HTTP.
// The async variant uses non-blocking Bun.spawn behind a small concurrency cap,
// so pane scrapes overlap with (and never freeze) HTTP. Same null-on-failure
// contract as capturePane(). Use this on the hot poll path; keep the sync
// capturePane() for the one-shot send/confirm flows where ordering matters.
const captureLimiter = new Semaphore(6);
export function capturePaneAsync(target: string): Promise<string | null> {
  return capturePaneAsyncStyled(target).then((t) => (t == null ? null : stripAnsi(t)));
}

/** SGR/CSI escape sequences tmux emits under `-e`. */
const ANSI_RE = /\x1b\[[0-9;]*[A-Za-z]/g;

/** The plain text a `-e` capture would have produced without `-e`. */
export function stripAnsi(text: string): string {
  return text.replace(ANSI_RE, "");
}

/**
 * Capture WITH escape sequences (`-e`).
 *
 * The styling is the only surviving trace of the model's markdown: by the time
 * text reaches the pane the TUI has already rendered `**bold**` as SGR 1 and
 * `` `code` `` as a 256-colour span, and a plain capture throws that away — which
 * is why a recovered preamble read as flat prose. `PaneStitcher` maps it back
 * (see `ansiToMarkdown`).
 *
 * One capture serves both needs: everything that wants plain text goes through
 * `capturePaneAsync`, which strips. Capturing twice would double the tmux
 * spawns on the 1 Hz poll path for every session.
 */
export function capturePaneAsyncStyled(target: string): Promise<string | null> {
  return captureLimiter.run(async () => {
    try {
      const proc = Bun.spawn(["tmux", "capture-pane", "-t", target, "-p", "-e"], {
        stdout: "pipe",
        stderr: "ignore",
      });
      const text = await new Response(proc.stdout).text();
      const code = await proc.exited;
      return code === 0 ? text : null;
    } catch {
      return null;
    }
  });
}

// Capture a pane (no line-join) with some scrollback. We deliberately do NOT
// pass -J: long URLs are often broken by the app's own hard wrap, not tmux
// auto-wrap, so -J can't rejoin them — link reconstruction handles the joining
// itself (see src/links.ts) and needs the rows kept separate.
export function capturePaneScroll(target: string, scrollback = 200): string | null {
  try {
    const r = Bun.spawnSync([
      "tmux", "capture-pane", "-t", target, "-p", "-S", `-${scrollback}`,
    ]);
    if (r.exitCode !== 0) return null;
    return new TextDecoder().decode(r.stdout);
  } catch {
    return null;
  }
}

// Same, but with escape sequences preserved (-e) so OSC 8 hyperlink targets
// survive — those carry the full URL regardless of how it visually wraps.
export function capturePaneEscaped(target: string, scrollback = 200): string | null {
  try {
    const r = Bun.spawnSync([
      "tmux", "capture-pane", "-t", target, "-p", "-e", "-S", `-${scrollback}`,
    ]);
    if (r.exitCode !== 0) return null;
    return new TextDecoder().decode(r.stdout);
  } catch {
    return null;
  }
}

// A pane's current column count — the wrap width link reconstruction joins on.
export function paneWidth(target: string): number | null {
  try {
    const r = Bun.spawnSync([
      "tmux", "display-message", "-p", "-t", target, "#{pane_width}",
    ]);
    if (r.exitCode !== 0) return null;
    const n = Number(new TextDecoder().decode(r.stdout).trim());
    return Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

export type PromptOption = {
  index: number;
  label: string;
  selected: boolean;
  // The option's description — the indented prose the AskUserQuestion TUI renders
  // under each label. Scraped from the pane so it's available while the question
  // is live (the structured version isn't in the transcript until answered).
  description?: string;
};
export type PanePrompt = {
  question: string;
  options: PromptOption[];
  // The assistant prose shown directly above the selector — the explanation the
  // model wrote right before asking. AskUserQuestion's containing turn is NOT
  // flushed to the transcript JSONL until the user answers, so this pane scrape
  // is the ONLY live source of that context; without it the client shows a bare
  // question and the explanation "appears only after the question is answered".
  context?: string;
};

// A separator line the Claude TUI draws to box an interactive selector (a run of
// ─ / ╌ / — / = / _). Used to bound the option box and locate the assistant
// prose above it.
const SELECTOR_SEP_RE = /^[╌─—_=-]{5,}$/;

// The assistant message bullet the Claude TUI prints ("⏺ <text>"), with 2-space
// -indented continuation lines for wrapped prose.
const ASSISTANT_BULLET = "⏺";

// How far above a selector `contextAbovePrompt` will walk. Sized to PANE_ROWS —
// the pane is the true limit, so anything smaller just re-introduces the clip.
const CONTEXT_SCAN_MAX_LINES = PANE_ROWS * 2;

// Scrape the assistant prose shown directly above a selector's top separator
// (`sepIdx`) — the explanation the model wrote right before asking. Claude
// renders it as "⏺ <text>" with wrap-continuation lines and blank-line
// paragraph breaks.
//
// We REQUIRE the "⏺" assistant bullet to be visible in the block: it is the only
// reliable signal that this prose is the assistant's and not the user's own
// prompt. Both render as 2-space-indented wrapped lines once their leading
// marker scrolls off the full-screen (no-scrollback) TUI, so without the bullet
// we cannot tell them apart — and guessing surfaced the user's own prompt as
// fake "context". If a preamble is long enough that its bullet scrolled off, we
// return nothing rather than risk echoing the user's prompt; the full turn shows
// as a normal transcript bubble once Claude flushes it.
//
// Walking up from the separator we collect lines until a boundary: the "⏺"
// bullet (top of the turn, inclusive), the user/composer "❯"/"›" marker, another
// separator, two consecutive blanks, the pane top, or a hard line cap. Single
// blank lines are kept as paragraph breaks; wrapped lines within a paragraph are
// re-joined with spaces so the client doesn't render mid-sentence hard breaks.
function contextAbovePrompt(
  lines: string[],
  sepIdx: number,
  lastUserText?: string,
): string | undefined {
  const collected: string[] = []; // bottom-to-top; reversed below
  let i = sepIdx - 1;
  while (i >= 0 && !lines[i].trim()) i--; // skip blanks adjacent to the box
  let consecutiveBlank = 0;
  let foundBullet = false;
  // Cap generously: the pane itself is the real bound (PANE_ROWS), and a cap
  // below it silently re-clips the preamble the tall pane exists to preserve.
  for (let scanned = 0; i >= 0 && scanned < CONTEXT_SCAN_MAX_LINES; i--, scanned++) {
    const trimmed = lines[i].trim();
    if (!trimmed) {
      if (++consecutiveBlank >= 2) break; // a real gap ends the block
      collected.push(""); // single blank = paragraph break, keep it
      continue;
    }
    consecutiveBlank = 0;
    if (SELECTOR_SEP_RE.test(trimmed)) break; // another selector box
    if (trimmed.startsWith("❯") || trimmed.startsWith("›")) break; // user / composer
    const isBullet = trimmed.startsWith(ASSISTANT_BULLET);
    collected.push(
      isBullet ? trimmed.replace(new RegExp(`^${ASSISTANT_BULLET}\\s*`), "") : trimmed,
    );
    if (isBullet) {
      foundBullet = true;
      break; // reached the top of the assistant turn
    }
  }
  const ordered = collected.reverse();
  while (ordered.length && !ordered[0]) ordered.shift();
  while (ordered.length && !ordered[ordered.length - 1]) ordered.pop();
  if (!ordered.length) return undefined;
  // Group consecutive non-blank lines into paragraphs (join wrap with spaces);
  // separate paragraphs with a blank line.
  const paragraphs: string[] = [];
  let current: string[] = [];
  for (const line of ordered) {
    if (!line) {
      if (current.length) paragraphs.push(current.join(" "));
      current = [];
    } else current.push(line);
  }
  if (current.length) paragraphs.push(current.join(" "));
  const text = paragraphs.join("\n\n").trim();
  if (!text) return undefined;
  // The bullet confirms this is the assistant's prose — safe to surface.
  if (foundBullet) return text;
  // No bullet in view: the block is either a scrolled-off assistant preamble OR
  // the user's own scrolled-off prompt (both render as bare wrapped lines). If
  // we know the last user turn and this block is part of it, it's the prompt —
  // don't echo it back as "context". Otherwise it's the assistant's preamble
  // (bullet scrolled off above a long response) — surface the visible tail.
  const norm = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();
  if (!lastUserText) return undefined; // can't disambiguate → stay safe
  const b = norm(text);
  if (b.length < 12) return undefined; // too short to attribute confidently
  if (norm(lastUserText).includes(b)) return undefined; // it's the user's prompt
  return text;
}

// Detect a Claude Code interactive selector in a pane capture (permission /
// plan-approval / trust dialogs AND AskUserQuestion). They render as numbered
// options with a "❯" cursor on the active one — the cursor is what tells a live
// prompt apart from a static numbered list in the transcript above.
//
// Permission prompts pack options on adjacent lines; AskUserQuestion puts a
// wrapped, indented description under each option (so the numbered lines are
// NOT contiguous). We therefore don't require contiguity — we gather every
// numbered line and group by consecutive numbering (a reset to a lower number
// starts a new group), then pick the bottom-most group whose active option
// carries the cursor.
const OPT_RE = /^\s*(❯|›)?\s*(\d+)\.\s+(\S.*?)\s*$/;

export function parsePrompt(pane: string, lastUserText?: string): PanePrompt | null {
  const lines = pane.replace(/\s+$/, "").split("\n");
  type Hit = { line: number; index: number; label: string; selected: boolean };
  const hits: Hit[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(OPT_RE);
    if (!m) continue;
    hits.push({ line: i, index: Number(m[2]), label: m[3].trim(), selected: !!m[1] });
  }
  if (!hits.length) return null;
  // Split into runs where the option number increments by exactly 1.
  const groups: Hit[][] = [];
  for (const h of hits) {
    const g = groups[groups.length - 1];
    if (g && h.index === g[g.length - 1].index + 1) g.push(h);
    else groups.push([h]);
  }
  let group: Hit[] | null = null;
  for (let i = groups.length - 1; i >= 0; i--) {
    if (groups[i].length >= 2 && groups[i].some((h) => h.selected)) {
      group = groups[i];
      break;
    }
  }
  if (!group) return null;
  const start = group[0].line;
  // Each option's description = the indented prose the AskUserQuestion TUI draws
  // between this option's numbered line and the next numbered line (of any
  // group), minus box rules and the footer. Wrapped description lines are
  // re-joined with spaces. (A very long LABEL that itself wrapped would leak its
  // tail into the description here — unresolvable from the pane, but labels are
  // usually short; the transcript path, preferred when available, has the exact
  // split.)
  const optionLines = new Set(hits.map((h) => h.line));
  const options: PromptOption[] = group.map((h, gi) => {
    const end = gi + 1 < group!.length ? group![gi + 1].line : lines.length;
    const desc: string[] = [];
    for (let j = h.line + 1; j < end; j++) {
      const t = lines[j].trim();
      if (!t) continue;
      if (optionLines.has(j)) break; // next option's line
      if (SELECTOR_SEP_RE.test(t)) break; // box rule
      if (/Enter to select/i.test(t)) break; // footer
      desc.push(t);
    }
    return {
      index: h.index,
      label: h.label,
      selected: h.selected,
      description: desc.join(" ") || undefined,
    };
  });
  // Question = the FULL block of contiguous lines above the first option. Claude
  // wraps a long question across several flush-left lines; grabbing only the
  // nearest one (the old behavior) surfaced "just the end of it". Join the wrap;
  // stop at the box header (☐ …), a separator, the multi-question nav bar
  // (←  … ✔ Submit …), or a blank line.
  const qLines: string[] = [];
  {
    let i = start - 1;
    while (i >= 0 && !lines[i].trim()) i--; // skip blank(s) directly above options
    for (; i >= 0; i--) {
      const t = lines[i].trim();
      if (!t) break;
      if (SELECTOR_SEP_RE.test(t)) break;
      if (t.startsWith("☐") || t.startsWith("←") || /✔\s*Submit/.test(t)) break;
      qLines.unshift(t);
    }
  }
  const question = qLines.join(" ");
  // The assistant preamble lives above the selector's TOP separator (the box's
  // opening rule, itself above the header/question). Find that separator, then
  // scrape the "⏺ …" prose block above it.
  let context: string | undefined;
  for (let i = start - 1; i >= 0 && i >= start - 8; i--) {
    if (SELECTOR_SEP_RE.test(lines[i].trim())) {
      context = contextAbovePrompt(lines, i, lastUserText);
      break;
    }
  }
  return { question, options, context };
}

// True when an AskUserQuestion selector is open in the pane, even when its
// option layout is unparseable (preview / multi-select). Keys off the stable
// footer the question dialog renders ("Enter to select · ↑/↓ to navigate · …
// Esc to cancel") — distinct from the composer and from permission prompts.
// Used to gate the number-key answer fallback so a stray keystroke can't land
// in the composer when no selector is up.
export function questionSelectorOpen(pane: string): boolean {
  return /Enter to select/i.test(pane) && /to navigate/i.test(pane);
}

// Claude is mid-turn when the TUI pins its live spinner meter just above the
// composer, e.g. "✢ Cerebrating… (2m 34s · ↓ 9.7k tokens)". That meter is
// present for the whole turn (the verb is random) and a finished turn collapses
// it to a past-tense summary with no parens ("✻ Baked for 18m 45s").
//
// The STABLE part of the meter is the live "(<elapsed> · …" clock — an open
// paren, an elapsed time ("4m 37s", "45s", "0s"), then a "·" separator. The
// detail after the "·" varies by phase:
//   • normal work:      "(4m 37s · ↓ 14.4k tokens)"
//   • extended thinking: "(5m 56s · still thinking with medium effort)"  ← no "tokens"!
// We previously matched on the literal word "tokens", so during thinking phases
// the meter didn't match and isBusy fell back to the "esc to interrupt" footer
// hint alone. But that footer ROTATES through other hints mid-turn ("← for
// agents", "PR #96", tips…), so when a thinking phase coincided with the hint
// rotating away, isBusy read FALSE while the agent was genuinely running — which
// fired a spurious "Finished" push every dedupe window. Matching the elapsed
// clock + "·" (instead of "tokens") keeps busy true through thinking phases.
// The "esc to interrupt" hint stays as a fallback for the first frame, before
// the clock renders.
// The meter is also anchored to END OF LINE. The region check below narrows the
// scan to the few lines above the composer, but an agent QUOTING a meter can
// land inside that window ('… renders as "✶ Crunching… (5m 50s · ↓ 2.2k
// tokens)".'). The real meter is the last thing on its line — it closes on the
// paren, or on a "…" when the TUI truncates it to the pane width — whereas a
// quote carries trailing prose. (A quote that is ITSELF truncated mid-clock
// still slips through; the region check keeps that to a 6-line window.)
const BUSY_METER = /\((?:\d+h\s+)?(?:\d+m\s+)?\d+s\b[^)]*·[^)]*[)…]\s*$/m;
const ESC_HINT = /esc to interrupt/i;

// Both markers are TUI CHROME: they only ever render in a fixed region around
// the composer box, never in the transcript scrolling above it. Testing them
// against the WHOLE pane let an agent's own output pin it busy — a session that
// merely *wrote about* "esc to interrupt" (this repo discusses its own busy
// detection, so its sessions do it constantly) read busy for as long as that
// text stayed on screen. And since paneBusy overrides the transcript-age
// fallback in listSessions, the session showed "running" forever, which also
// made the send queue hold every message for a session that was plainly idle.
//
// The real layout, from a live capture of a busy pane:
//
//   ✶ Crunching… (5m 50s · ↓ 2.2k tokens)          ← meter, above the top border
//     ⎿  Tip: …                                     ← 0-N optional interstitials
//                    Update available! …            ┘
//   ────────────────────────────────────            ← composer top border
//   ❯ typed text                                    ← composer content
//   ────────────────────────────────────            ← composer bottom border
//     ⏵⏵ bypass permissions … · esc to interrupt …  ← footer, below the border
//
// So: scan for the hint strictly BELOW the composer's bottom border, and for
// the meter in a short window immediately ABOVE its top border. Transcript
// prose can reach neither.
const METER_LOOKBACK_LINES = 6;

// ── codex TUI ────────────────────────────────────────────────────────────────
//
// Everything above describes CLAUDE's shape. Codex draws a different TUI and the
// Claude-shaped scans silently mis-read it — which is what stranded every codex
// send as "queued" and then "not sent" (see
// .claude/diagnosis-codex-send-not-sent-20260806.md). A real busy codex pane:
//
//   • Running the requested command now.              ← agent output
//   • Working (1m 16s • esc to interrupt) · 1 back…   ← meter
//   • Messages to be submitted after next tool call…  ← codex's OWN queue notice
//     ↳ the queued message                            ┘ (only renders mid-turn)
//   › typed text                                      ← the composer: ONE line
//     gpt-5.6-sol high fast · ~/dev/personal/lfg      ← status footer
//
// Two consequences, both load-bearing:
//
//   * There is no bordered composer, so `busyChromeRegions` fell through to a
//     6-line tail. That fits a plain busy pane but NOT one showing the queue
//     notice, which pushes the meter to 6 lines above the composer — so the
//     marker went unseen and a busy codex read idle. Self-reinforcing: the
//     notice only appears once something is queued, so the first queued message
//     is what blinds us.
//   * Codex still prints rule lines — `─ Worked for 1m 17s ─` after every turn,
//     plus plain runs in agent output. With two or more on screen the composer
//     scan paired them and returned the AGENT'S OUTPUT as "the composer".
//
// Discriminator: a `›` composer line lying BELOW the last rule line. Claude's
// composer content sits *between* two rule lines, so only codex puts one there.
const CODEX_PROMPT = /^\s*›\s*(.*?)\s*$/;

// Codex terminates its unbordered composer with a model + cwd status line:
//   gpt-5.6-sol high fast · ~/dev/personal/lfg · Main [default]
// The cwd is the stable discriminator; model names and optional branch suffixes
// vary. This boundary lets inputBoxFromPane include multiline continuation rows
// without accidentally consuming transcript output above the composer.
const CODEX_STATUS_FOOTER = /^\s{2,}.+\s·\s(?:~\/|\/).*/;

// How far above the codex composer its chrome can reach (meter + queue notice +
// blank lines). Bounded so an unbounded pane never lets transcript prose in.
const CODEX_CHROME_LOOKBACK = 10;

// Codex chrome markers. Deliberately TIGHTER than the bare `esc to interrupt`
// hint: the codex chrome region is not fenced by a border, so it can include a
// line or two of agent prose, and this repo's own sessions discuss busy
// detection constantly. A parenthesised elapsed clock immediately followed by
// the interrupt hint is chrome in practice; prose quoting it is not.
const CODEX_BUSY_METER = /\((?:\d+h\s*)?(?:\d+m\s*)?\d+s\s*[•·]\s*esc to interrupt\)/i;
// Only rendered while a turn is in flight, so it is a positive busy signal in
// its own right — and it is exactly the frame the old 6-line window missed.
const CODEX_QUEUE_NOTICE = /messages? to be submitted after next tool call/i;

/**
 * Index of the codex composer line, or null if this pane isn't a codex TUI.
 *
 * Requires the `›` line to sit below every rule line — that is what separates a
 * codex composer from a Claude composer's contents. Numbered rows (`› 1. …`)
 * are selector options, not an editable composer, so they disqualify the pane
 * (the send queue must not treat an open selector as somewhere to type).
 */
export function codexComposerIndex(lines: string[]): number | null {
  let lastRule = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    if (isRuleLine(lines[i])) {
      lastRule = i;
      break;
    }
  }
  for (let i = lines.length - 1; i > lastRule; i--) {
    const m = lines[i].match(CODEX_PROMPT);
    if (!m) continue;
    if (/^\d+\.\s+/.test(m[1] ?? "")) return null;
    return i;
  }
  return null;
}

// The codex chrome block: from just under the last rule line (never into
// scrollback) or a bounded lookback above the composer, through the end of the
// pane. Returns null when the pane isn't a codex TUI.
function codexChrome(lines: string[]): string | null {
  const composer = codexComposerIndex(lines);
  if (composer == null) return null;
  let lastRule = -1;
  for (let i = composer - 1; i >= 0; i--) {
    if (isRuleLine(lines[i])) {
      lastRule = i;
      break;
    }
  }
  const start = Math.max(lastRule + 1, composer - CODEX_CHROME_LOOKBACK, 0);
  return lines.slice(start).join("\n");
}

// Split a captured pane into the two chrome regions isBusy is allowed to read.
// Border runs are collapsed the same way inputBoxFromPane collapses them: a
// border drawn wider than the pane wraps into two consecutive rule lines.
export function busyChromeRegions(pane: string): { meter: string; footer: string } {
  const lines = pane.split("\n");
  // Codex first: its rule lines are transcript separators, not composer
  // borders, so the border pairing below would fence off the wrong region and
  // the 6-line tail is too short whenever the queue notice is on screen.
  const codex = codexChrome(lines);
  if (codex != null) return { meter: codex, footer: codex };
  let i = lines.length - 1;
  while (i >= 0 && !isRuleLine(lines[i])) i--; // into the bottom border run
  if (i < 0) {
    // No composer box and no codex prompt: a pane captured mid-render. Still
    // refuse to read scrollback — the chrome is always at the bottom — so fall
    // back to the tail for both regions.
    const tail = lines.slice(-METER_LOOKBACK_LINES).join("\n");
    return { meter: tail, footer: tail };
  }
  const footer = lines.slice(i + 1).join("\n");
  while (i >= 0 && isRuleLine(lines[i])) i--; // skip the whole wrapped run
  const aboveComposer = i;
  while (i >= 0 && !isRuleLine(lines[i])) i--; // over the composer content
  if (i < 0) {
    // Only one border in the pane — treat everything above it as the meter
    // region rather than losing the signal entirely.
    i = aboveComposer;
  } else {
    while (i >= 0 && isRuleLine(lines[i])) i--; // skip the top border run
  }
  const meter = lines
    .slice(Math.max(0, i - METER_LOOKBACK_LINES + 1), i + 1)
    .join("\n");
  return { meter, footer };
}

export function isBusy(pane: string): boolean {
  const lines = pane.split("\n");
  const codex = codexChrome(lines);
  // Codex renders neither Claude's meter nor its footer hint in a fenced
  // region, so match its own chrome instead of the loose `esc to interrupt`
  // hint — the codex region can contain a line of agent prose. BUSY_METER rides
  // along because it is end-of-line anchored (prose carries trailing text) and
  // the two failure modes are not symmetric: reading a busy agent as IDLE is
  // what re-drove messages and failed them, while reading an idle agent as busy
  // only holds the send until the next poll.
  if (codex != null) {
    return (
      CODEX_BUSY_METER.test(codex) || CODEX_QUEUE_NOTICE.test(codex) || BUSY_METER.test(codex)
    );
  }
  const { meter, footer } = busyChromeRegions(pane);
  return BUSY_METER.test(meter) || ESC_HINT.test(footer);
}

// Claude Code occasionally floats a session-rating overlay just above the
// composer: a single line like "  1: Bad   2: Fine   3: Good   0: Dismiss".
// It captures Enter and number keys, but it renders as `N: label` (colon, all
// on one line) — NOT the `❯ N. label` newline-separated shape parsePrompt
// matches — so the send queue can't see it. A send then types into the
// composer fine but the Enter is swallowed by the overlay, stranding the
// message ("never left the input box after retries"). Match the distinctive
// options line directly so the sender can dismiss it first.
export function feedbackPromptOpen(pane: string): boolean {
  return pane
    .split("\n")
    .some((l) => /\b0:\s*Dismiss\b/.test(l) && /\b(Bad|Fine|Good)\b/.test(l));
}

// Dismiss the rating overlay by selecting its "0: Dismiss" option (a single
// keystroke, no Enter). Harmless — the rating is optional — and it returns
// keyboard focus to the composer so the queued message can submit.
export function tmuxDismissFeedback(target: string): void {
  Bun.spawnSync(["tmux", "send-keys", "-t", target, "-l", "0"]);
}

// Answer an active selector by arrowing the cursor to the target option, then
// Enter. Arrow nav is reliable in this modal state where literal text is not.
export async function answerPrompt(
  target: string,
  index: number,
): Promise<{ ok: boolean; error?: string }> {
  const pane = capturePane(target);
  const p = pane ? parsePrompt(pane) : null;
  if (!p) {
    // The pane parser couldn't read a selector, but an AskUserQuestion with an
    // option preview (or a multi-select/wrapped layout) still has one open — it
    // just renders a side-by-side box the scraper can't follow, and the prompt
    // was surfaced from the transcript instead (see pendingToolPrompt). Answer
    // it by pressing the option's number directly: single-key selection doesn't
    // need to know the current cursor position, so it works where arrow-nav
    // (which depends on parsing the cursor) can't. 1–9 only — every real
    // AskUserQuestion has ≤4 options.
    if (pane && questionSelectorOpen(pane) && index >= 1 && index <= 9) {
      Bun.spawnSync(["tmux", "send-keys", "-t", target, "-l", String(index)]);
      await Bun.sleep(120);
      const r = Bun.spawnSync(["tmux", "send-keys", "-t", target, "Enter"]);
      if (r.exitCode !== 0)
        return { ok: false, error: new TextDecoder().decode(r.stderr) || "Enter failed" };
      return { ok: true };
    }
    return { ok: false, error: "no active prompt in pane" };
  }
  const order = p.options.map((o) => o.index);
  const cur = p.options.find((o) => o.selected)?.index ?? order[0];
  const ci = order.indexOf(cur);
  const ti = order.indexOf(index);
  if (ti < 0) return { ok: false, error: "option not found" };
  const delta = ti - ci;
  const key = delta > 0 ? "Down" : "Up";
  for (let i = 0; i < Math.abs(delta); i++) {
    Bun.spawnSync(["tmux", "send-keys", "-t", target, key]);
    await Bun.sleep(60);
  }
  await Bun.sleep(120);
  const r = Bun.spawnSync(["tmux", "send-keys", "-t", target, "Enter"]);
  if (r.exitCode !== 0)
    return { ok: false, error: new TextDecoder().decode(r.stderr) || "Enter failed" };
  return { ok: true };
}

// Dismiss an open interactive selector (AskUserQuestion / permission / plan) by
// sending Escape — Claude cancels the selector and returns to the composer (for
// AskUserQuestion it records that the user declined to answer). Guarded on a live
// prompt so a stray call can't interrupt a running turn or, on an idle composer,
// trip the second-Escape rewind-history overlay.
//
// A *single* Escape is unreliable: the TUI's input parser can't tell a lone ESC
// from the start of an escape sequence (arrow keys arrive as `ESC [ A`), so the
// byte can sit buffered until the next keystroke flushes it — one send-keys then
// silently does nothing (the observed "X button doesn't dismiss" bug). So we
// re-send, re-checking the pane each round and stopping the instant the selector
// clears. Because we only fire again while the prompt is STILL up, we never land
// a second Escape on the composer (which would open the rewind-history overlay).
export async function dismissPrompt(
  target: string,
): Promise<{ ok: boolean; error?: string }> {
  let pane = capturePane(target);
  if (!pane || !parsePrompt(pane)) return { ok: false, error: "no active prompt in pane" };
  for (let attempt = 0; attempt < 3; attempt++) {
    const r = Bun.spawnSync(["tmux", "send-keys", "-t", target, "Escape"]);
    if (r.exitCode !== 0)
      return { ok: false, error: new TextDecoder().decode(r.stderr) || "Escape failed" };
    // Poll a few times before re-sending: the parser may register the lone ESC
    // on its own disambiguation timeout, in which case one Escape is enough and
    // we avoid leaving a stray buffered keystroke behind.
    for (let i = 0; i < 6; i++) {
      await Bun.sleep(150);
      pane = capturePane(target);
      if (!pane || !parsePrompt(pane)) return { ok: true };
    }
  }
  return { ok: false, error: "prompt did not dismiss after repeated Escape" };
}

// ---- low-level keystroke primitives for the confirmed-send queue (sendq.ts).
// Blind text+sleep+Enter loses messages (the fixed sleep races a busy TUI, a
// dropped Enter leaves text stranded in the box). sendq drives these and reads
// `inputBoxText` back to confirm each step landed.

export function tmuxType(target: string, text: string): boolean {
  return Bun.spawnSync(["tmux", "send-keys", "-t", target, "-l", text]).exitCode === 0;
}

// Insert text into the composer via bracketed paste instead of literal keys.
// `send-keys -l` transmits the string byte-for-byte, so an embedded `\n` reaches
// the TUI as an Enter and a multi-line message submits (or fragments) at the
// first newline — the whole text never lands as one draft. Loading it into a
// tmux buffer and pasting with `-p` (bracketed paste) makes the TUI receive the
// newlines as newlines; Claude collapses the blob to a "[Pasted text +N lines]"
// chip and submits it whole on the next Enter. `-d` drops the buffer after.
export function tmuxPaste(target: string, text: string): boolean {
  const buf = "lfg-send";
  const load = Bun.spawnSync(["tmux", "load-buffer", "-b", buf, "-"], {
    stdin: new TextEncoder().encode(text),
  });
  if (load.exitCode !== 0) return false;
  return (
    Bun.spawnSync(["tmux", "paste-buffer", "-b", buf, "-t", target, "-p", "-d"])
      .exitCode === 0
  );
}

export function tmuxEnter(target: string): boolean {
  return Bun.spawnSync(["tmux", "send-keys", "-t", target, "Enter"]).exitCode === 0;
}

// Wipe the composer before a (re)type so we never fuse our message onto a
// stranded draft. C-u alone (kill-to-start) usually does it, but it's been
// observed to get swallowed once on a freshly-idle pane, leaving the draft —
// and then tmuxType appends, submitting a garbled concatenation. Belt-and-
// suspenders: C-u (kill before cursor) + C-a (jump to start) + C-k (kill after)
// guarantees an empty line regardless of cursor position or a single dropped
// key. All three are harmless no-ops on an already-empty box.
export function tmuxClearInput(target: string): void {
  Bun.spawnSync(["tmux", "send-keys", "-t", target, "C-u", "C-a", "C-k"]);
}

// A single Escape interrupts Claude's current turn (stops generation / aborts
// the running tool). One press only — a second Esc opens the rewind history.
export function tmuxInterrupt(target: string): boolean {
  return Bun.spawnSync(["tmux", "send-keys", "-t", target, "Escape"]).exitCode === 0;
}

// The Claude Code composer renders as the bottom-most pair of `─` rule lines
// with the input (a `❯`-prefixed line, possibly wrapped) between them. We return
// that region verbatim; callers normalize + substring-match their own text, so
// placeholder/ghost hint text in an empty box doesn't matter. Returns null when
// no composer box is visible (e.g. a modal/selector is up instead).
//
// A composer border line. Claude draws it three ways, and a matcher that only
// accepted the first two silently broke sending:
//   ─────────────────────   plain
//   ──── my-session ──      named session (label centred between dash runs)
//   (Branch) ──             branch view (label is a PREFIX; dashes only at the
//                           end) — `^─{3,}` never matched this, so the top
//                           border went unseen.
// The invariant across all three is: the line ENDS in dashes, carries only a
// short label besides them, and never holds composer content (`❯`). Requiring
// two trailing dashes rather than three is what admits `(Branch) ──`.
export function isRuleLine(line: string): boolean {
  const s = line.replace(/[ \t]+$/, "");
  if (!s.endsWith("─")) return false;
  if (s.includes("❯")) return false;
  const dashes = (s.match(/─/g) ?? []).length;
  if (dashes < 2) return false;
  // Cap the label so a wrapped transcript line that happens to end in a rule
  // can't masquerade as a border.
  return s.length - dashes <= 40;
}

export function inputBoxText(target: string): string | null {
  const pane = capturePane(target);
  if (pane == null) return null;
  return inputBoxFromPane(pane);
}

// Extract the composer region from a captured pane. Split out from
// inputBoxText so the border-scan can be tested against real captures.
export function inputBoxFromPane(pane: string): string | null {
  const lines = pane.split("\n");
  // Codex before the border scan, NOT as its fallback. Codex prints rule lines
  // of its own (`─ Worked for 1m 17s ─` after every turn, plus plain runs in
  // agent output), so with two or more on screen the pairing below succeeded
  // and handed back the AGENT'S OUTPUT as "the composer" — the send queue then
  // read every draft as absent and failed with "message never left the input
  // box after retries". The `›` line below the last rule IS the composer.
  const codexIdx = codexComposerIndex(lines);
  if (codexIdx != null) {
    const first = lines[codexIdx].match(CODEX_PROMPT)?.[1] ?? "";
    const footer = lines.findIndex((line, i) => i > codexIdx && CODEX_STATUS_FOOTER.test(line));
    if (footer < 0) return first;

    // Codex expands a bracketed multiline paste directly in its composer: the
    // first line carries `›`, while every later paragraph/wrapped line is
    // indented by two spaces until the model/cwd footer. Returning only the
    // prompt line made the send queue miss any confirmation prefix that crossed
    // the first newline, so it pasted the same message again on every retry.
    const continuation = lines
      .slice(codexIdx + 1, footer)
      .map((line) => (line.startsWith("  ") ? line.slice(2) : line));
    return [first, ...continuation].join("\n").trimEnd();
  }
  // Scan bottom-up for the composer's two borders. Crucially, a border DRAWN
  // WIDER THAN THE PANE wraps into two consecutive rule lines — and pairing
  // each rule line with the next one up made the wrap pair with its own first
  // half, collapsing the composer region to the empty string. Every send then
  // read as "our text never landed in the box", so deliver() retyped three
  // times and failed with "message never left the input box after retries"
  // even though the keys were arriving fine. Collapse each maximal RUN of rule
  // lines into a single border instead.
  let i = lines.length - 1;
  while (i >= 0 && !isRuleLine(lines[i])) i--; // into the bottom border
  if (i >= 0) {
    while (i >= 0 && isRuleLine(lines[i])) i--; // skip the whole wrapped run
    const contentEnd = i;
    while (i >= 0 && !isRuleLine(lines[i])) i--; // into the top border
    if (i >= 0) return lines.slice(i + 1, contentEnd + 1).join("\n");
  }

  // Codex renders the composer as a single bottom prompt line:
  //   › message text
  // Ignore numbered selector rows (`› 1. ...`) so open prompts don't look like
  // an editable composer to the send queue.
  for (let j = lines.length - 1; j >= 0; j--) {
    const m = lines[j].match(/^\s*›\s*(.*?)\s*$/);
    if (!m) continue;
    const text = m[1] ?? "";
    if (/^\d+\.\s+/.test(text)) return null;
    return text;
  }
  return null;
}
