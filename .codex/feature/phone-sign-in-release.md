# Sign-in-only release

User requested separating browser streaming, merging iPhone sign-in to main, and publishing TestFlight.

Streaming is preserved unchanged as commit 9b311fb on feature/browser-stream in `.worktrees/browser-stream-only`. Sign-in was rebased directly onto main with no streaming ancestor. The old combined tip is retained as backup/phone-sign-in-before-stream-split. Native streaming build artifacts were moved to the streaming worktree.

Release contains the iPhone sign-in view and session request/history UI, Chrome extension, Playwright bridge, CLI and shared Claude/Codex skill. Successful Done dismisses; readiness requires cookies and detected or user-confirmed login.

Main's unrelated working files were snapshotted before integration. Release archives come from this isolated committed checkout, with private signing/access bootstrap files copied locally and excluded from Git. The public Fastlane app configuration is now tracked so the release lane works from a clean checkout.

Validation: rerun Swift core suite, focused Bun transport/request/integration tests, TypeScript, and iOS build after removing streaming. Previous independent iPhone/iPad UI completion audit applies because both sign-in view files are unchanged by the split. Live App Store Connect sign-in succeeded in isolated Playwright and Browse contexts,12/12 cookies each.

TestFlight done means the canonical verify_testflight_build lane confirms IPA metadata, processing VALID, correct version train, and IN_BETA_TESTING.
