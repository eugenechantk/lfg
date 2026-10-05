import { test, expect, beforeAll, afterAll } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkPath, checkSessionFile, defaultRoots, isProbablyText, looksSecret, mentionedPaths } from "./mcp-file-policy.ts";

let home: string;
let roots: string[];

beforeAll(() => {
  home = realpathSync(mkdtempSync(join(tmpdir(), "mcp-policy-")));
  for (const d of ["dev/app/.claude", "dev/app/.git", "dev/app/src", "inbox/report", ".ssh", ".codex", "secret-elsewhere"]) mkdirSync(join(home, d), { recursive: true });
  writeFileSync(join(home, ".codex/notes.md"), "x");
  writeFileSync(join(home, "inbox/report/out.md"), "# out\n");
  writeFileSync(join(home, "dev/app/src/main.ts"), "export {}\n");
  writeFileSync(join(home, "dev/app/src/ForgotPasswordView.swift"), "struct V {}\n");
  writeFileSync(join(home, "dev/app/.claude/plan.md"), "# plan\n");
  writeFileSync(join(home, "dev/app/.git/config"), "[core]\n");
  writeFileSync(join(home, "dev/app/.env"), "KEY=1\n");
  writeFileSync(join(home, "dev/app/Secrets.xcconfig"), "KEY=1\n");
  writeFileSync(join(home, "dev/app/cert.p12"), "x");
  writeFileSync(join(home, ".ssh/id_ed25519"), "x");
  writeFileSync(join(home, "secret-elsewhere/notes.txt"), "x");
  // A symlink inside an allowed root that points outside it.
  symlinkSync(join(home, ".ssh"), join(home, "dev/app/sshlink"));
  roots = defaultRoots(home);
});

afterAll(() => rmSync(home, { recursive: true, force: true }));

test("allows project files, agent docs, and ~ paths", () => {
  expect(checkPath(join(home, "dev/app/src/main.ts"), roots, home)).toEqual({ ok: true, path: join(home, "dev/app/src/main.ts") });
  expect(checkPath("~/dev/app/.claude/plan.md", roots, home).ok).toBe(true);
  expect(checkPath("~/dev/app/src/ForgotPasswordView.swift", roots, home).ok).toBe(true);
  expect(checkPath("~/inbox/report", roots, home).ok).toBe(true);
});

test("refuses secrets, hidden folders, outside roots, symlink escapes, and relative paths", () => {
  const no = (p: string) => {
    const r = checkPath(p, roots, home);
    expect(r.ok).toBe(false);
    return r.ok ? "" : r.reason;
  };
  expect(no("~/dev/app/.env")).toContain("secrets");
  expect(no("~/dev/app/Secrets.xcconfig")).toContain("secrets");
  expect(no("~/dev/app/cert.p12")).toContain("secrets");
  expect(no("~/dev/app/.git/config")).toContain("hidden folder");
  expect(no("~/.ssh/id_ed25519")).toContain("outside");
  expect(no("~/secret-elsewhere/notes.txt")).toContain("outside");
  expect(no("~/dev/app/sshlink/id_ed25519")).toContain("outside");
  expect(no("dev/app/src/main.ts")).toContain("absolute");
  expect(no("~/dev/app/nope.txt")).toBe("no such file or directory");
  expect(no(home)).toContain("outside");
});

test("checkSessionFile reads only files the session mentioned, resolved the same way", () => {
  const out = join(home, "inbox/report/out.md");
  // Mentioned as ~/…, asked for by absolute path: same file.
  expect(checkSessionFile(out, ["~/inbox/report/out.md"], home)).toEqual({ ok: true, path: out });
  const unmentioned = checkSessionFile(join(home, "dev/app/src/main.ts"), ["~/inbox/report/out.md"], home);
  expect(unmentioned.ok).toBe(false);
  expect(unmentioned.ok ? "" : unmentioned.reason).toContain("never mentioned");
  // A symlink the session never named does not count as the file it points to.
  expect(checkSessionFile(join(home, "dev/app/sshlink/id_ed25519"), [join(home, ".ssh/id_ed25519")], home).ok).toBe(false);
});

test("checkSessionFile still refuses mentioned secrets, hidden folders, home-level config, and folders", () => {
  const reason = (p: string) => {
    const r = checkSessionFile(p, [p], home);
    expect(r.ok).toBe(false);
    return r.ok ? "" : r.reason;
  };
  expect(reason(join(home, "dev/app/.env"))).toContain("secrets");
  expect(reason(join(home, "dev/app/.git/config"))).toContain("hidden folder (.git)");
  expect(reason(join(home, ".ssh/id_ed25519"))).toContain("~/.ssh");
  expect(reason(join(home, ".codex/notes.md"))).toContain("~/.codex");
  expect(reason(join(home, "dev/app"))).toBe("not a file");
  expect(reason("relative/x.md")).toContain("absolute");
  expect(checkSessionFile(join(home, "dev/app/.claude/plan.md"), ["~/dev/app/.claude/plan.md"], home).ok).toBe(true);
});

test("looksSecret spares source files that merely mention the words", () => {
  expect(looksSecret("credentials.json")).toBe(true);
  expect(looksSecret("client_secret.plist")).toBe(true);
  expect(looksSecret(".env.production")).toBe(true);
  expect(looksSecret("AuthKey_ABC.p8")).toBe(true);
  expect(looksSecret("CredentialsView.swift")).toBe(false);
  expect(looksSecret("reset-password.tsx")).toBe(false);
  expect(looksSecret("README.md")).toBe(false);
  expect(looksSecret("mcp-creds.env")).toBe(true);
  expect(looksSecret("auth.json")).toBe(true);
  expect(looksSecret("cookies.txt")).toBe(true); // Netscape cookie jars are .txt
  expect(looksSecret("chrome-cookies.json")).toBe(true);
  expect(looksSecret("tokens.ts")).toBe(false);
  expect(looksSecret("app.sqlite")).toBe(true);
});

test("isProbablyText: utf-8 text yes, NUL bytes no, a character split at 8 KB still yes", () => {
  expect(isProbablyText(new TextEncoder().encode("hello ✓"))).toBe(true);
  expect(isProbablyText(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x00, 0x01]))).toBe(false);
  const big = new TextEncoder().encode("a".repeat(8191) + "✓" + "b".repeat(100));
  expect(isProbablyText(big)).toBe(true);
});

test("mentionedPaths finds absolute and ~ paths in prose and tool calls", () => {
  const t = 'Wrote `/Users/e/dev/app/report.md`. See ~/inbox/x/shot.png, and {"file_path":"/Users/e/dev/app/a.ts"}.';
  expect(mentionedPaths(t, "/Users/e")).toEqual(["/Users/e/dev/app/report.md", "~/inbox/x/shot.png", "/Users/e/dev/app/a.ts"]);
  expect(mentionedPaths("GET /api/sessions and /Users/other/x.md", "/Users/e")).toEqual([]);
  expect(mentionedPaths("shot at /private/tmp/claude-501/s/out.png and /tmp/a.json", "/Users/e")).toEqual(["/private/tmp/claude-501/s/out.png", "/tmp/a.json"]);
});
