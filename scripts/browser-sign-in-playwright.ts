import { chromium } from "playwright-core";
import { connectPhoneSignIn } from "../src/browser-sign-in-playwright.ts";
const [endpoint, name = "Playwright", host = "http://127.0.0.1:8766", index] =
  process.argv.slice(2);
if (!endpoint)
  throw Error(
    "Usage: bun scripts/browser-sign-in-playwright.ts <local CDP URL> [browser name] [LFG URL] [context index]",
  );
const url = new URL(endpoint);
if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname))
  throw Error("CDP endpoint must be local.");
const browser = await chromium.connectOverCDP(endpoint);
const contexts = browser.contexts();
if (index === undefined && contexts.length !== 1)
  throw Error("Multiple contexts: supply the exact context index.");
const context = contexts[Number(index ?? 0)];
if (!context) throw Error("Context not found.");
const bridge = connectPhoneSignIn(context, {
  name,
  baseURL: host,
  onStatus: (s) => console.log(`Phone sign-in: ${s}`),
});
// Never close the browser/context owned by an agent.
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.on(signal, () => {
    bridge.close();
    process.exit(0);
  });
