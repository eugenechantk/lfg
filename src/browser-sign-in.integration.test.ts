import { test, expect } from "bun:test";
import { chromium } from "playwright-core";
import {
  BrowserSignInHub,
  type SignInResult,
  signInHTTP,
  allowsSignInAdapter,
} from "./browser-sign-in.ts";
import { connectPhoneSignIn } from "./browser-sign-in-playwright.ts";
import { execFileSync } from "node:child_process";
import { mkdtemp, rm, cp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";

// One real protected fixture. Never start the application's database/server or use 8766.
function fixture() {
  try {
    const out = execFileSync("lsof", ["-nP", "-iTCP:9983", "-sTCP:LISTEN"], {
      encoding: "utf8",
    });
    if (out.trim()) throw Error("Port 9983 is occupied");
  } catch (e: any) {
    if (e.status !== 1) throw e;
  }
  const hub = new BrowserSignInHub(() => "a".repeat(64));
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 9983,
    fetch(req, server) {
      const url = new URL(req.url);
      if (url.pathname === "/api/browser-sign-in/adapter") {
        if (!allowsSignInAdapter(req)) return new Response("", { status: 403 });
        return server.upgrade(req)
          ? undefined
          : new Response("", { status: 400 });
      }
      return signInHTTP(req, hub);
    },
    websocket: {
      open: (s) => hub.open(s),
      message: (s, m) => hub.message(s, m),
      close: (s) => hub.close(s),
    },
  });
  return {
    hub,
    server,
    close() {
      hub.dispose();
      server.stop(true);
    },
  };
}
async function waitFor(fn: () => boolean | Promise<boolean>) {
  for (let i = 0; i < 100; i++) {
    if (await fn()) return;
    await Bun.sleep(50);
  }
  throw Error("Timed out");
}
const cookie = {
  name: "session",
  value: "synthetic-login",
  domain: "portal.example.com",
  hostOnly: true,
  path: "/",
  secure: true,
  httpOnly: true,
  sameSite: "Lax",
};
async function send(targetId: string) {
  const res = await fetch(
    "http://127.0.0.1:9983/api/browser-sign-in/transfer",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        targetId,
        url: "https://portal.example.com/",
        domains: ["portal.example.com"],
        cookies: [cookie],
      }),
    },
  );
  return res.json() as Promise<SignInResult>;
}

test("real HTTP → WebSocket → existing Playwright context authenticates only the selected browser", async () => {
  const f = fixture();
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext(),
    untouched = await browser.newContext();
  const bridge = connectPhoneSignIn(context, {
    token: "a".repeat(64),
    name: "Fixture Playwright",
    baseURL: "http://127.0.0.1:9983",
  });
  try {
    await context.route("https://portal.example.com/**", (route) =>
      route.fulfill({
        status: route
          .request()
          .headers()
          ["cookie"]?.includes("session=synthetic-login")
          ? 200
          : 401,
        body: "fixture",
      }),
    );
    const page = await context.newPage();
    expect((await page.goto("https://portal.example.com/"))?.status()).toBe(
      401,
    );
    await waitFor(() => f.hub.targets().length === 1);
    expect(await send(f.hub.targets()[0]!.id)).toEqual({
      state: "installed",
      installed: 1,
      total: 1,
    });
    expect((await page.reload())?.status()).toBe(200);
    expect(await untouched.cookies()).toHaveLength(0);
    const c = (await context.cookies())[0]!;
    expect(c.httpOnly).toBe(true);
    expect(c.secure).toBe(true);
    expect(c.expires).toBe(-1);
    const attack = await fetch(
      "http://127.0.0.1:9983/api/browser-sign-in/transfer",
      {
        method: "POST",
        headers: {
          Origin: "https://evil.example",
          "Content-Type": "application/json",
        },
        body: "{}",
      },
    );
    expect(attack.status).toBe(403);
    const huge = await fetch(
      "http://127.0.0.1:9983/api/browser-sign-in/transfer",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "x".repeat(262145),
      },
    );
    expect(huge.status).toBe(413);
    bridge.close();
    await waitFor(() => f.hub.targets().length === 0);
    expect(context.pages()).toContain(page);
  } finally {
    bridge.close();
    await browser.close();
    f.close();
  }
}, 20000);

test("real MV3 Chrome extension installs HttpOnly session cookie and rejects ungranted site", async () => {
  const f = fixture();
  const dir = await mkdtemp(join(tmpdir(), "lfg-sign-in-extension-"));
  const extension = join(dir, "extension");
  await cp(resolve("extensions/phone-sign-in"), extension, { recursive: true });
  const manifest = JSON.parse(
    await readFile(join(extension, "manifest.json"), "utf8"),
  );
  manifest.host_permissions.push("https://portal.example.com/*");
  await writeFile(join(extension, "manifest.json"), JSON.stringify(manifest));
  const context = await chromium.launchPersistentContext(join(dir, "profile"), {
    channel: "chromium",
    headless: true,
    args: [
      `--disable-extensions-except=${extension}`,
      `--load-extension=${extension}`,
    ],
  });
  try {
    const worker =
      context.serviceWorkers()[0] ||
      (await context.waitForEvent("serviceworker"));
    // Test-only manifest pregrants one synthetic origin; production requires Options consent.
    const optionsPage = await context.newPage();
    await optionsPage.goto(new URL("options.html", worker.url()).href);
    await optionsPage.locator("#name").fill("Fixture Chrome");
    await optionsPage.locator("#port").fill("9983");
    await optionsPage.locator("#token").fill("a".repeat(64));
    await optionsPage.getByRole("button", {name:"Save connection"}).click();
    expect(await optionsPage.locator("#token").inputValue()).toBe("");

    try {
      await waitFor(() => f.hub.targets().length === 1);
    } catch (e) {
      console.log(
        "Extension status:",
        await worker.evaluate(() =>
          (globalThis as any).chrome.storage.session.get("status"),
        ),
      );
      throw e;
    }
    expect((await send(f.hub.targets()[0]!.id)).state).toBe("installed");
    const actual = (await context.cookies())[0]!;
    expect(actual.value).toBe(cookie.value);
    expect(actual.httpOnly).toBe(true);
    expect(actual.secure).toBe(true);
    expect(actual.expires).toBe(-1);
    const page = await context.newPage();
    await context.route("https://portal.example.com/**", (route) =>
      route.fulfill({
        status: route
          .request()
          .headers()
          ["cookie"]?.includes("session=synthetic-login")
          ? 200
          : 401,
        body: "fixture",
      }),
    );
    expect((await page.goto("https://portal.example.com/"))?.status()).toBe(
      200,
    );
    // Test import using already-granted loopback host permissions over HTTPS.
    const response = await fetch(
      "http://127.0.0.1:9983/api/browser-sign-in/transfer",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          targetId: f.hub.targets()[0]!.id,
          url: "http://127.0.0.1/",
          domains: ["127.0.0.1"],
          cookies: [{ ...cookie, domain: "127.0.0.1" }],
        }),
      },
    );
    // HTTPS loopback is not granted by the shipped manifest: verify fail-closed too.
    expect(((await response.json()) as SignInResult).state).toBe("failed");
    expect(await context.cookies()).toHaveLength(1);
  } finally {
    await context.close();
    f.close();
    await rm(dir, { recursive: true, force: true });
  }
}, 20000);
