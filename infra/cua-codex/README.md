# Codex desktop image

This profile runs Codex, Firefox/Chromium, gog, Node, Python and Git in a Linux Space. It keeps the official Cua desktop and media services.

## Build

Run from the repository root:

```
uv run python infra/cua-codex/build.py
```

The script uses the installed Cua Spaces CLI and Docker Desktop. It creates or resumes a tool-only seed Space, installs Cua's pinned Codex dependencies with its checksum checks, copies only the tool cache, verifies the gog archive checksum and builds `lfg-cua-codex:1`. It never copies an authenticated home into the image. The final image adds less storage than a separate copy of its shared base layers.

The current profile targets Apple silicon (`linux/arm64`). `versions.json` records the tool versions. If Cua changes its harness pins, update and verify this profile before rebuilding. The build refuses missing expected cache versions.

Cua checks `/opt/cua/tools` for baked tool markers. Its current runner also expects the ACP SDK under the guest user's tool path. Version links provide that compatibility while leaving the user cache writable for future versions.

## Configure an LFG host

Set `LFG_CUA_PROFILE` to a host-owned JSON file, then start the LFG host. A profile has this shape:

```json
{
  "image": "lfg-cua-codex:1",
  "mounts": [
    {"source": "/absolute/path/chosen/by/user", "target": "/pro/projects", "readOnly": true}
  ],
  "codexModel": "gpt-6.1-sol"
}
```

Each mount requires an explicit readOnly value and a unique `/pro/name` target. These are live host files. A read/write mount lets the agent change the originals. Empty mounts are valid while selecting folders.

LFG uses Docker to create a container with those mounts and a loopback-only Cua port. It registers that endpoint with Cua. Cua's current `create_space` MCP tool does not expose host bind mounts. Existing standard Spaces continue through their original Cua lifecycle.

New profile Spaces default to Codex when the API caller omits agent. The current native New Space sheet still requires choosing Codex in its existing agent picker. No client update is required to use the profile.

Turn Space off pauses the managed container. Turn Space on resumes it. Neither operation deletes its files. Paused containers retain memory. Removing a profile file does not remove any container; keep the host profile available for lifecycle control.

## Sign-ins

Credentials and personal files are supplied at runtime, never in the image.

For a temporary trial, optional `codexAuthSource` may point to the Pro's Codex `auth.json`. LFG injects its current access token through stdin, strips the refresh token, and does not copy host configuration, skills or history. This avoids competing with the Pro's token rotation. The trial sign-in expires with that access token.

For durable use, sign in separately inside the Space with Codex's supported login flow. Its credential file stays in that container. Automatic sign-in renewal from the Pro is not implemented.

Google uses gog's own account setup. Run `gog auth --help` inside the Space to configure the intended Google account. The baked Codex system config registers `gog mcp`; tools default to read-only. CLI availability and MCP registration do not prove account access. Google authentication and real Google operations were not part of this build acceptance.

## Evidence

See `.codex/feature/cua-codex-image.md` for actual image, agent, browser and host-file verification. The acceptance host uses a temporary test folder until Eugene selects real Pro folders and permissions.
