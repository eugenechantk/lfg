# Making the Air self-sufficient for signing lfg.app — 2026-08-12

**Goal:** the Air could not sign the desktop app with a stable identity, so every desktop change had
to be built on the Pro and `ditto`'d over. Now both hosts hold the SAME Developer ID cert, so either
can build and the iTerm TCC grant survives.

## Why the Air lacked it

`ios/fastlane/Matchfile` declares `type("appstore")`. That match type provisions **Apple Distribution
+ Apple Development** — the App Store/TestFlight set. `developer_id` is a separate type nothing asked
for, and a Developer ID private key never leaves the machine that generated the CSR unless exported.
The Air's certs are even labelled "Created via API" — minted by fastlane, not by a human at that Mac.

## What was done

| Step | Where | Result |
| --- | --- | --- |
| Export identity from login keychain | Pro | needed the screen unlocked + one "Always Allow" click |
| Split out the Developer ID pair, modulus-verified | Pro | `devid.cer` + PKCS#1 PEM key |
| `match import --type developer_id` | Pro | `certs/developer_id_application/BU3A3ABW96.{cer,p12}` |
| `match developer_id --readonly --skip_provisioning_profiles` | Air | identity `27A195F1…` installed |
| `security set-key-partition-list …` (Eugene, with his password) | Air | stops codesign prompting |
| `./build.sh` in a GUI-session shell | Air | `Authority=Developer ID Application…`, strict verify OK |

Both hosts now report the same identity hash `27A195F1158D07A3105DDE28B9F3058BDE9DF7B8`.

## Three findings worth keeping

**A match repo's `.p12` is not a PKCS#12 file.** `cert/lib/cert/runner.rb` does `File.write(path, pkey)`
— it is a PKCS#1 PEM private key with a `.p12` name, imported with `-P ""`. Feeding `match import` a
real p12 produces `SecKeychainItemImport: MAC verification failed during PKCS12 import`, and it fails
identically with `-legacy` ciphers, so the cipher is a red herring — the format is. `match import`
validates only the file extension. OpenSSL 3 needs `openssl rsa -traditional` (its default PKCS#8
output gives `Unknown format in import`).

**fastlane's installed-check looks at the certificate, not the key.** Import just the `.cer` and match
reports "All required keys, certificates and provisioning profiles are installed 🙌" while silently
skipping the private key. Clear it with `security delete-certificate -Z <sha1>` before re-running.

**Private-key operations need the GUI security session.** Over plain ssh, `codesign` fails with
`errSecInternalComponent` and `security import -A` says "User interaction is not allowed" — even after
the partition list is set. Plain `security import` (writes) does work over ssh. To build on the Air
remotely, go through its existing tmux server, which was started from the GUI session by `cy`:

```
tmux new-session -d -s sigtest "cd ~/dev/personal/lfg/desktop && ./build.sh > /tmp/b.log 2>&1; echo DONE > /tmp/done"
```

## Cleanup / state

All exported key material was deleted from the scratchpad; the private key exists only in the two
login keychains and the (encrypted) match repo. No Developer ID provisioning profile was created —
`--skip_provisioning_profiles true` kept the repo's `profiles/` untouched. No new certificate was
minted, so the team's Developer ID slots are unchanged; the shared cert expires **2027-02-01**.
