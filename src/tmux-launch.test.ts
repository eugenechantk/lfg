import { expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { prepareTmuxLaunch, spawnTmuxLaunch, tmuxLaunchArgv } from "./tmux-launch.ts";

test("short commands keep literal tmux escaping and command queue", () => {
  const launch = { prefix: ["tmux", "new-session"], command: ["agent", "hello;"], suffix: [";", "set-option"] };
  const prepared = prepareTmuxLaunch(launch);
  expect(prepared.argv).toEqual(tmuxLaunchArgv(launch));
  expect(prepared.argv).toEqual(["tmux", "new-session", "agent", "hello\\;", ";", "set-option"]);
  expect(prepared.path).toBeUndefined();
  prepared.cleanup();
});

for (const provider of ["claude", "codex"]) test(`real tmux preserves long ${provider} arguments and cleans private files`, async () => {
  const root = mkdtempSync(join(tmpdir(), "lfg-launch-test-"));
  const socket = `lfg-launch-test-${process.pid}-${provider}`;
  const target = `long-${provider}`;
  const output = join(root, "received.json");
  const marker = join(root, "must-not-exist");
  const recorder = join(root, "recorder.ts");
  writeFileSync(recorder, 'await Bun.write(process.argv[2], JSON.stringify({args:process.argv.slice(3),tty:process.stdin.isTTY})); await Bun.sleep(5000);');
  const prompt = `women's fitness \\ \"quoted\"\n香港 🏋️\n$(touch '${marker}') \`touch '${marker}'\`\n`.repeat(400) + (provider === "codex" ? "end;" : "end;\n\n");
  const command = [process.execPath, recorder, output, "--model", provider, "--", prompt];
  const suffix = provider === "codex" ? [";", "set-option", "-w", "-t", `=${target}:`, "window-style", "fg=#dcdcdc,bg=#15191f"] : [];
  const launch = { prefix: ["tmux", "-L", socket, "new-session", "-d", "-s", target, "-c", root], command, suffix };
  const prepared = prepareTmuxLaunch(launch);
  try {
    expect(prepared.path).toBeString();
    expect(statSync(prepared.path!).mode & 0o777).toBe(0o600);
    expect(statSync(join(prepared.path!, "..")).mode & 0o777).toBe(0o700);
    expect(prepared.argv.join(" ").length).toBeLessThan(2000);
    const result = Bun.spawnSync(prepared.argv);
    expect(result.stderr.toString()).toBe("");
    expect(result.exitCode).toBe(0);
    for (let i = 0; i < 100 && !existsSync(output); i++) await Bun.sleep(30);
    expect(JSON.parse(readFileSync(output, "utf8"))).toEqual({ args: command.slice(3), tty: true });
    expect(existsSync(marker)).toBe(false);
    expect(existsSync(prepared.path!)).toBe(false);
    if (suffix.length) {
      const style = Bun.spawnSync(["tmux", "-L", socket, "show-option", "-wv", "-t", `=${target}:`, "window-style"]);
      expect(style.stdout.toString().trim()).toBe("fg=#dcdcdc,bg=#15191f");
    }
  } finally {
    Bun.spawnSync(["tmux", "-L", socket, "kill-server"]);
    prepared.cleanup();
    rmSync(root, { recursive: true, force: true });
  }
});

test("failed launches can remove unique private files without deleting another launch", () => {
  const launch = { prefix: ["tmux", "new-session"], command: ["agent", "🦊".repeat(3000)] };
  const a = prepareTmuxLaunch(launch);
  const b = prepareTmuxLaunch(launch);
  try {
    expect(a.path).not.toBe(b.path);
    a.cleanup();
    a.cleanup();
    expect(existsSync(a.path!)).toBe(false);
    expect(existsSync(b.path!)).toBe(true);
  } finally { a.cleanup(); b.cleanup(); }
});

test("spawn failure removes the staged command and reports the error", () => {
  const files = () => readdirSync(tmpdir()).filter(name => name.startsWith("lfg-session-launch-")).sort();
  const before = files();
  const result = spawnTmuxLaunch({ prefix: ["/usr/bin/false"], command: ["agent", "x".repeat(20_000)] });
  expect(result).toEqual({ ok: false, error: "new-session failed" });
  expect(files()).toEqual(before);
});
