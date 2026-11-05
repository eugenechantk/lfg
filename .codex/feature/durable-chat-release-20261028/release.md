# Durable chat release

Released commit: `5748c91b2c6fd62c8017ddb12bdb293090dbcc0e`.

| Target | Result | Proof |
| --- | --- | --- |
| Pro host | Live | PID 55658 runs the new source; 301 file hashes and typechecking pass. All 31 task configurations and 77 terminal sessions survive. |
| Air host | Live | PID 18397 runs the new source; 301 file hashes and typechecking pass. Its task configuration and terminal session survive. |
| Pro desktop | Live | PID 58382 runs the installed app; all eight bundle files and its signature match the verified build. |
| Air desktop | Live | PID 22025 resolves to the installed app; all eight bundle files and its signature match the verified build. |
| iOS TestFlight | Available | Version 1.4.1, build 202610281000. The canonical verifier confirms IPA metadata, VALID, highest train and IN_BETA_TESTING. |

Both public host URLs return HTTP 200 for identity, ping, durable chats, shared Tasks and push health. Push is configured on both hosts. These checks do not send a physical notification. The IPA bundles access for both hosts.

The release retains prior host folders and desktop bundles. It reuses unchanged dependencies. The Air checkout and all unrelated local work remain untouched. The generated iOS project was restored from project.yml; tracked source is clean. No new commit or tag was needed.

## Deployment notes

The old Pro API timed out during preflight. The deployment saved task configuration and terminal-session inventory from their existing files and tmux, then verified preservation after restart. The new public API checks pass.

Initial Python HTTP probes hit Cloudflare error 1010 because of their generic User-Agent. Probes using the native client User-Agent and bundled credentials pass. No access policy changed.

The first desktop archive added AppleDouble metadata files. A metadata-free archive preserves every signed bundle file and passes strict signature verification. The failed staging copy was retained for diagnosis.

The Air lacks Accessibility permission for UI automation. A release-only XcodeGen project let FlowDeck launch the verified installed bundle without building or changing permissions. The launcher output link resolves to /Applications/lfg.app. Air visual inspection was not performed.

The Air still has about 426 MiB free. This release used a small runtime archive and the already-verified desktop app. It performed no cleanup or Air compilation.

Full command logs, source manifests, deployment receipts and TestFlight verification remain beside this note.
