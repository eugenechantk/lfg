// Screenshot canvas boards served from a local folder (port 8794).
// node shot.mjs <outDir> name:w:h[:clickSel|clickSel...] ...
import { chromium } from "playwright-core";
const [,, outDir, ...boards] = process.argv;
const b = await chromium.connectOverCDP("http://127.0.0.1:9333");
const ctx = b.contexts()[0] || await b.newContext();
const page = await ctx.newPage();
const errs = [];
page.on("pageerror", e => errs.push("PAGEERROR " + e.message));
for (const spec of boards) {
  const [name, w, h, clicks] = spec.split(":");
  await page.setViewportSize({ width: +w, height: +h });
  await page.goto(`http://127.0.0.1:8794/${name}.dc.html`, { waitUntil: "networkidle" });
  await page.waitForTimeout(1200);
  if (clicks) for (const sel of clicks.split("|")) { await page.click(sel, { timeout: 3000 }).catch(e => errs.push("CLICK " + sel + " " + e.message.split("\n")[0])); await page.waitForTimeout(400); }
  await page.screenshot({ path: `${outDir}/${name}${clicks ? "-c" : ""}.png`, clip: { x: 0, y: 0, width: +w, height: +h } });
  console.log("shot", name);
}
console.log(errs.slice(0, 20).join("\n"));
await page.close();
process.exit(0);
