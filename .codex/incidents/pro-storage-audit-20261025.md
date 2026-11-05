# Pro storage audit, 25 October 2026

The approved virtual-phone installers and old Unity build cache were deleted at 13:35 HKT.
Actual free space increased from 3.260 GiB to 24.717 GiB, recovering 21.458 GiB.
Both target directories were absent afterward. Unity Assets, ProjectSettings, and the existing VM remain intact.

All inspected paths below belong to the Pro. Sizes are allocated file sizes, not guaranteed reclaimed space.
Shared files, APFS clones, and active writes can change the actual gain. Parent and child sizes must not be added.

## Completed cleanup

| Item | Size | Effect of deletion |
| --- | ---: | --- |
| `~/.vphone/ipsws` | 10.91 GiB | Removes two downloaded restore installers. Re-download them before recreating that virtual phone. Keeps the existing VM. |
| `~/dev/personal/paper_toss_vr/Library` | 10.53 GiB | Removes generated Unity imports, packages, and build files. Unity must rebuild and may re-download packages on next open. Keeps Assets and ProjectSettings. |

The installers were downloaded on 16 September. Their names are `cloudos-26.1.ipsw` and `iPhone17,3_26.1_23B85_Restore.ipsw`.
The Unity Library directory was last modified on 8 July. No Unity editor or compiler process appeared in the process check.
No open files appeared under either directory immediately before deletion.
The Unity project has no root `.gitignore`; this recommendation targets only its generated `Library` directory.

## Protected: old phone-test screenshots

These five folders contain 11,407 PNG files with about 25.94 GiB allocated.
Eugene explicitly requested keeping the screenshots. Exclude them from all further cleanup proposals and deletions.

| Folder under `~/inbox` | PNG size | Latest file activity in whole folder |
| --- | ---: | --- |
| `instagram-account-playbook` | 9.566 GiB | 23 October |
| `fiftystrong-tiktok-warmup` | 6.067 GiB | 19 October |
| `roxie-search-engage-2026-10-19` | 4.636 GiB | 22 October |
| `tiktok-doomscroll` | 4.128 GiB | 19 October |
| `tiktok-dating-search-test` | 1.544 GiB | 18 October |

No candidate PNG files appeared open during the check. These folders also hold scripts, schedules, reports, and some videos.
Do not delete the screenshots or their containing folders.

## Preserve or review separately

- `~/shots`: about 168 GiB of production footage, including 136 GiB in `hardware project`. Archive or verify a backup before removal.
- `~/Library/Developer/CoreSimulator/Devices`: about 40.8 GiB. Requires a selective simulator audit.
- `/Library/Developer/CoreSimulator`: about 80.1 GiB. Runtime storage needs separate inspection; do not assume the full size is reclaimable.
- `~/Library/Developer/Xcode/Archives`: about 7.49 GiB. Keep release archives and symbols unless a retention policy permits removal.
- `~/Library/Caches/com.openai.codex`: about 2.40 GiB, mostly a staged update. Its updater was running, so preserve it.
- `~/Library/Caches/dictate-engine-bench`: about 1.92 GiB of speech models. Preserve installed models.
- Docker's sparse disk: about 11 GiB allocated despite a 926 GiB logical size. Do not treat its logical size as reclaimable storage.
- LFG's `.codex/evidence`: about 17 GiB. Keep current release and verification evidence until retention is agreed.
- No Time Machine local snapshots were listed.

## Simulator audit limitation

FlowDeck failed with `License storage error: Failed to load license`.
The FlowDeck skill says: "If you see \"LICENSE REQUIRED\", \"trial expired\", or similar: 1. **STOP**".
Simulator selection stopped; no raw simulator tools were used. Restore the license before that audit.
Skill source: `/Users/eugenechan/.codex/skills/flowdeck/SKILL.md`.

## Further findings after the approved cleanup

- Completed at 13:39 HKT: removed the 19 approved `.logarchive` directories under `~/dev/inbox/.codex/vphone-sweat/research`.
  The newest archived file dated to 16 September. No archive files appeared open immediately before deletion.
  All 19 directories were verified absent afterward. Research notes, scripts, tools, and the VM remain intact.
  Actual free space increased from 23.855 GiB to 27.421 GiB, recovering another 3.567 GiB.
- The existing virtual phone uses about 17.45 GiB of allocated space. Its disk was last modified on 16 September.
  Removing it would discard its apps and saved state. No deletion is proposed unless the VM is retired.
- Noto has about 4.03 GiB of custom build directories under `.flowdeck`.
  Current Apple builds exist elsewhere on the Pro, and FlowDeck licensing blocks supported cleanup. Leave these alone for now.
- Hardware review proxies and segments contain about 9.88 GiB of generated MP4 files.
  Keep them: none of the 124 catalogue source paths currently resolves on the external drive.
  Only 24 originals match local files by filename and size. This does not establish a verified backup.
- The 25.94 GiB of screenshots is explicitly protected by Eugene's instruction to keep it.
- Docker's status command did not finish. This audit's client was stopped; no daemon or container was stopped.

The screenshot, VM, hardware-media, and build-cache candidates remain untouched.

## Completed cache batch excluding screenshots

Eugene approved this batch. At 13:45 HKT, removed Blender's generated shader cache,
both temporary Kiro downloads, and 45 inactive npx cache directories.
Actual free space increased from 26.280 GiB to 34.522 GiB, recovering 8.242 GiB.
All three fixed targets were verified absent, and both active tool-cache directories remained present.

| Candidate | Allocated size | Effect |
| --- | ---: | --- |
| Blender GPU shader cache | 4.474 GiB | Blender rebuilds shaders. The next render may take longer. No project files are targeted. |
| Two temporary Kiro CLI downloads | 1.200 GiB | Removes downloaded app copies from 20 and 22 October. Keeps the installed CLI. |
| Inactive npx tool-cache directories | About 2.53 GiB | Tools may download packages again. Protect both currently referenced cache directories. |

The exact Blender path on the Pro is `/private/var/folders/cd/_rd32xx17dv8ltmf4ctm5wn40000gn/C/org.blenderfoundation.blender`.
Its contents are generated Metal shader and GPU caches, most recently modified on 8 October.
The two Kiro paths share `/private/var/folders/cd/_rd32xx17dv8ltmf4ctm5wn40000gn/T/`:
`kiro-cli-downloadUNyTCk` and `kiro-cli-download7xKPXN`.

The 45 removed directories under `~/.npm/_npx` included old PostHog wizard, Vercel, Wrangler, Expo, and Sentry wizard installs.
Preserved `9833c18b2d85bc59` for active Playwright MCP processes and `99336612077b7094` for active XcodeBuildMCP processes.
Checking open files alone missed these running tools; the process-command check identified them.
Active references were rechecked before deletion, and each npx target was checked again immediately before its removal.
No target had become active, so none needed skipping.
The final check found no Blender process, no processes referencing either temporary Kiro download, and no open files in those three directories.
One Kiro CLI process was running elsewhere and remains protected. LFG returned HTTP 200, with 26.697 GiB free on disk.

An additional 6.18 GiB of PlatformIO firmware packages could be re-downloaded after removal.
These are installed ESP32 toolchains and frameworks, so they are a separate optional choice, not part of the recommended batch.
Gradle and Bun caches total about 0.83 GiB. These are smaller follow-up candidates.
The uv cache has already grown to about 2.12 GiB during active work; leave it alone while that work continues.
The LFG upload directory holds about 2.88 GiB of user uploads. Preserve it.

## Current service status

The data volume had 34.522 GiB free after the approved cache batch.
LFG's local `/api/info` and `/api/sessions` returned HTTP 200. The session list contained 24 entries.
Remote deletions in this incident were uv cache, the two restore installers, the Unity Library cache,
19 debug-log archives, Blender's shader cache, two temporary Kiro downloads, and 45 inactive npx cache directories.
All screenshots remain protected and untouched.

## Follow-up: recurring growth

A read-only investigation at 16:09–16:20 found 14.74 GiB in three live simulator Finance database journals.
It also confirmed failed simulator cleanup and a session idle clock that resets on transcript-file updates.
The detailed report and metadata are in `/Users/eugenechan/inbox/pro-resource-growth-20261025/` on the Air.
No further cleanup or database changes occurred during that investigation.
