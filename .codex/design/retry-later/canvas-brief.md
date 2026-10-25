# Steering: design in the existing LFG canvas

Eugene clarified: "The Claude agents can just work on the canvas right? There's a canvas that the previous Claude sessions developed to store our UIs."

Use the **native Artifact tool**, not the old claude-design MCP server. Prior Claude sessions use calls such as `Artifact(action="read", url="...", path="project/dA2-runs-rail.dc.html", out_dir="...")` and `Artifact(action="publish", url="...", root="...", file_path="...", label="...")`. Use the `artifact-design` and `artifact-capabilities` skills if available. Your prior invocation hid native tools; this resumed invocation restores the default tools.

Canvas: **LFG UI Map** https://claude.ai/artifact/F2B1MNbv5oxuscm237M9sD

Your existing context and `.codex/design/retry-later/brief.md` describe the feature. This steering replaces the separate HTML design-board destination. The existing canvas is the canonical design surface. Read it and inspect its source/instructions before editing. Use the Tasks redesign page (A2 dark tA2d-* and Desktop A2 dA2-* boards), and other native sheet boards as needed.

## Ownership

You own only new Retry later boards on a new clearly labelled row/page **Retry later (Oct 18)**, and local supporting files under `.codex/design/retry-later/`. You are not alone. Other agents use this canvas and codebase. Do not replace, delete, or modify existing boards or pages. Read the latest canvas version before writing, and use the Artifact tool's incremental edit/publish workflow to avoid overwriting concurrent work. Do not edit product code, real tasks, host settings, commit, or push.

## Design first

Design a recommended cohesive revision using LFG's existing visual language and reusable tokens/components. Include phone failed-card hierarchy, minutes sheet with selected preset/custom entry, exact-time sheet, pending retry card, and compact Mac sheet. Add light/dark variants and concise behavior notes. Preserve all current behavior from the original brief. Favor a focused compact sheet, clear time preview, strong primary action, and visibly selected chips. Use actual app patterns and no new visual system.

Publish your new boards to this existing canvas. Verify that they are persisted with a fresh read. Export the exact board source(s) under `.codex/design/retry-later/reference/` for implementation and independent comparison. Write `.codex/design/retry-later/design.md` with the canvas version/page/board IDs, component/token reuse, key copy, dimensions, interaction rules, and any limitations. This local note supports the canvas; it does not replace it.

Return the canvas link and new board IDs after publishing. Stop after the design; Codex implements next. Do not ask for approval: Eugene has already asked to design and then re-implement. If Artifact access is unavailable, report the exact missing capability/auth error and do not fabricate canvas edits or create another canvas.
