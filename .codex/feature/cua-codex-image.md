# Codex Space image

## User story
Create Linux Spaces with Codex, browser, gog, Node, Python and Git already installed, plus access to chosen Pro folders.

## Success criteria
- [x] SC1: Build a reusable image with the requested tools and Cua desktop services. Verify binary versions and browser capture from a fresh container.
- [x] SC2: A new Cua Space starts the pinned Codex harness without installation downloads. Verify Cua run logs and a harmless coding task.
- [ ] SC3: Access selected Pro folders at a stable guest path with the selected permissions. Verify reading a host-created marker and permitted write behavior.
- [x] SC4: LFG creates new Spaces using the custom image. Verify API integration tests and a real creation; existing Spaces remain intact.

## Decisions
- Continue in existing isolated worktree; no commits, pushes or production release.
- Keep credentials and personal files outside image layers. No Google API changes or emails are part of acceptance.
- Folder scope and permissions are pending the user's answer. Image building can proceed independently.
- Retain the official Cua base image and its browser/streaming services.

## Initial evidence
The recorded verification appears below.

## Bugs
None yet.

## Implementation
The image retains Cua's desktop base and adds pinned Codex tooling under `/opt/cua/tools`, matching per-user version links, gog, a Python alias, and the Codex system Google MCP configuration. Dockerfile/build script and version record are in `infra/cua-codex/`.

A host-owned profile selects the image and explicit bind mounts. LFG launches it with a loopback-only Cua port, registers the endpoint, and retains the container name for pause/resume. Standard Spaces keep their existing provisioner. The native agent picker is unchanged: choose Codex.

## Verification evidence
- Image build passed: `.codex/evidence/cua-codex-image/build.log`.
- Real binaries: Node24.21.0, Codex0.156.1, Python3.12.3, Git2.43.0, gog0.45.0. Browser and Cua media services remain present.
- LFG API created Codex Ready (`74d7beb8-d7fc-44f8-bc9c-d767ee24b8cb`) with a temporary Pro folder at `/pro/test`; no real project folders were mounted.
- Real Codex run `run-673798e6` authenticated, read the Pro marker, wrote `CODEX_IMAGE_AND_PRO_SHARE_OK` back to the host and drove the browser to example.org. It finished idle. Log: `lfg-agent-status.json`.
- All four install steps reported `cached`, with no downloads in that run.
- `codex mcp list --json` showed the enabled Google server. `gog mcp --list-tools` returned typed Google tools without accessing an account.
- 19 backend tests /100 assertions passed, including profile provisioning, secrets via stdin, stripped host refresh token, mount permissions, lifecycle routing and existing streaming regression tests.

## Resolved issues
- gog archive names include `./gog`; Docker extraction now matches its actual entry.
- The base already includes Node symlinks. The build replaces them with the selected pinned version.
- Cua recognizes baked ACP SDK markers but its current runner links the per-user SDK path. Version links fix the missing runner dependency.
- Persistent Cua agents reject extra `mcp_servers`. The image registers Google through Codex's documented system configuration instead.
- Codex initially tried `python`; the image now supplies the standard alias to Python3.

## Pending user decision
Which Pro folders should Spaces access, and with which read/write permissions? The asynchronous question is pending. The live bind mechanism is verified only with a temporary task folder. Google account authentication is not configured. Trial Codex auth uses the Pro's current access token without its refresh token; a durable independent Space login remains separate.

## Final verification and pending scope
Independent audit PASS for the image and configured temporary share: `.codex/evidence/cua-codex-image-audit/REPORT.md`. A second fresh Space completed a real Python task, wrote a host-visible marker and streamed H.264 frames. Final image includes the working `python` alias. The audit exposed no blocking defect.

The build script itself was rerun successfully with tag `lfg-cua-codex:verify-build`; evidence `rebuild-script.log`. Runtime read-only enforcement was verified separately: reading succeeded and a write failed (`readonly-proof.txt`). Both LFG-managed image Spaces paused, resumed to the same idle agent run, and paused again (`lifecycle.json`). All test containers are now paused. The isolated trial host listens on 127.0.0.1:18968; production 8766 was untouched.

SC3 remains pending only for the real folder selection. The mount implementation passed read/write and read-only tests against a temporary task folder on the Pro. No actual project or home folder has been exposed. The asynchronous folder/permission question is still unanswered, so a real folder profile cannot be activated yet.
