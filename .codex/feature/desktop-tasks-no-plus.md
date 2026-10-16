# Remove the desktop task-list plus button

## Request
Remove the plus button in the desktop task list.

## Behavior
The desktop task toolbar has More and Search. Task creation and manual setup remain in More.
Search moves into More below 360 points. Mobile controls stay unchanged.

## Success criteria
- [x] No standalone plus button appears at narrow or wide desktop widths. Verify the running app and screenshots at 300, 440, 760, and 1440 points.
- [x] More still opens New scheduled task and manual setup. Verify accessibility actions in the running app.
- [x] Desktop build and existing feature checks pass.
- [x] Independent visual audit passes. The verified build is installed on Pro and Air.

## Scope
The changed view code is inside the macOS conditional. No phone build or layout changes.

## Evidence
Build, feature tests, screenshots, installation records, and independent audit are in `.codex/evidence/desktop-tasks-no-plus-20261016/`.

## Self-verification
- Standalone signed build passed. Existing desktop feature checks: 183 passed.
- Onscreen screenshots at 300, 440, 760, and 1440 points show no standalone toolbar plus button.
- The installed Pro app's More menu contains New scheduled task and manual setup for each host.
- Selecting New scheduled task opened the task_chat_request form. Closed it without entering or submitting a task.
- Pro installed binary SHA-256: c3aff3695a21821df6911be59df3d269a630f4137da94b6439850106e02567b3.
- Prior app backup: ~/Library/Application Support/lfg-desktop-backups/20261016-no-task-plus/lfg.app.

## Initial installation
The same signed binary was installed and running on both Macs before a concurrent release replaced it.
Pro: /Applications/lfg.app, PID 19092 at installation.
Air: /Applications/lfg.app, PID 91571 at installation.
SHA-256 on both: c3aff3695a21821df6911be59df3d269a630f4137da94b6439850106e02567b3.
The Air also passed all 183 built-in feature checks. Its prior app is backed up at the same relative path as Pro.
The shared Swift source was copied to Air after confirming its previous hash matched this checkout's base.
No commits or pushes were made. Air installation does not substitute for a live Air UI audit.

## Concurrent release
A separate session installed version 1.4.0 from its clean worktree and restored the toolbar plus. The independent auditor caught the regression.
The release owner handed desktop installation to this session; its acknowledgement is in `coordination/ack.md`. We rebuilt root main with its 1.4.0 version and the toolbar fix. No commit or push of these changes is authorized.

## Final installation
The combined 1.4.0 app is installed and running on Pro (PID 38150) and Air (PID 94993).
Both signatures passed. Both apps passed all 183 built-in feature checks.
Both binary hashes are `158e89f9a86b93f0a87e7bd1065422ea8ebb8a37b14c473df07618d4e60663e1`.
Installation records: `pro-install-1.4.0.json` and `air-install-1.4.0.json`.
The replaced 1.4.0 apps are backed up under `~/Library/Application Support/lfg-desktop-backups/20261016-no-task-plus-1.4.0/`.
Independent final Pro UI audit: PASS. More, new task sheet, manual setup, and Search worked. Widths 300, 440, 760, and 1440 all lacked a toolbar plus. See `audit/evidence.md`. Air installation was verified without a live GUI audit.
