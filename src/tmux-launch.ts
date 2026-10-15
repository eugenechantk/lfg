import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export type TmuxLaunch = { prefix: string[]; command: string[]; suffix?: string[] };

// tmux treats a trailing semicolon in ANY argument as a queue separator.
export function tmuxLiteral(arg: string): string {
  return arg.endsWith(";") ? `${arg.slice(0, -1)}\\;` : arg;
}

export function tmuxLaunchArgv(launch: TmuxLaunch): string[] {
  return [...launch.prefix, ...launch.command.map(tmuxLiteral), ...(launch.suffix ?? [])];
}

// Keep well below tmux's IPC message limit, measured in bytes, not characters.
const INLINE_COMMAND_BYTES = 8_000;
const shellLiteral = (arg: string) => `'${arg.replaceAll("'", "'\\''")}'`;

export function prepareTmuxLaunch(launch: TmuxLaunch): { argv: string[]; path?: string; cleanup: () => void } {
  const argv = tmuxLaunchArgv(launch);
  if (argv.reduce((total, arg) => total + Buffer.byteLength(arg) + 1, 0) < INLINE_COMMAND_BYTES)
    return { argv, cleanup() {} };

  // Only the short path crosses tmux's IPC boundary. The shell reads the file
  // locally, removes it, and execs the CLI with its exact original arguments.
  // Single-quoting makes prompt text data: no eval, expansion, or substitution.
  const directory = mkdtempSync(join(tmpdir(), "lfg-session-launch-"));
  const path = join(directory, "launch.sh");
  const cleanup = () => rmSync(directory, { recursive: true, force: true });
  try {
    chmodSync(directory, 0o700);
    const script = `#!/bin/sh\nset -eu\n/bin/rm -f -- ${shellLiteral(path)}\n/bin/rmdir -- ${shellLiteral(directory)}\nexec ${launch.command.map(shellLiteral).join(" ")}\n`;
    writeFileSync(path, script, { mode: 0o600, flag: "wx" });
    return { argv: [...launch.prefix, "/bin/sh", path, ...(launch.suffix ?? [])], path, cleanup };
  } catch (error) { cleanup(); throw error; }
}

export function spawnTmuxLaunch(launch: TmuxLaunch): { ok: boolean; error?: string } {
  let prepared: ReturnType<typeof prepareTmuxLaunch> | undefined;
  try {
    prepared = prepareTmuxLaunch(launch);
    const result = Bun.spawnSync(prepared.argv);
    if (result.exitCode === 0) return { ok: true }; // The shell owns cleanup after it opens the file.
    prepared.cleanup();
    return { ok: false, error: result.stderr.toString() || "new-session failed" };
  } catch (error) {
    prepared?.cleanup();
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}
