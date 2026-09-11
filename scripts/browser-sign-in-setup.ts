import { mkdirSync, writeFileSync, chmodSync, existsSync } from "node:fs";
import { dirname } from "node:path";
import { randomBytes } from "node:crypto";
import { signInTokenPath, readSignInToken } from "../src/browser-sign-in.ts";
const path = signInTokenPath();
if (!existsSync(path)) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  writeFileSync(path, randomBytes(32).toString("hex"), {
    mode: 0o600,
    flag: "wx",
  });
}
chmodSync(path, 0o600);
const token = readSignInToken();
if (!token)
  throw Error(
    "Existing token file is invalid; inspect it before replacing it.",
  );
// Only this explicitly invoked setup command displays the local pairing credential.
console.log(
  "Paste this connection token into the LFG Chrome extension options:",
);
console.log(token);
