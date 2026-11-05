# Step 2: compare the existing Appium path with direct WDA

The user authorized the three investigations in order and approved all operations.
Step 1 confirms a delay outside phone execution. Its upstream transport repair remains open.
This comparison is independent: a local controller times phone requests without model continuations.

## Scope

- Use Hi Hi, UDID 00008110-0011083A1151801E, currently USB connected.
- Reuse its existing Appium and WDA sessions. Create or delete neither session.
- Hold the existing UDID operation lock throughout the local comparison.
- Perform temporary navigation in Settings. Change no setting, account, content or social engagement.
- Use identical coordinate gestures and local OCR checks for both backends.
- Restore Home and the original locked state. Keep the existing WDA and Appium sessions alive.
- Bound the active benchmark. Stop on uncertain input, unexpected state or ownership change.

## Criteria

- Confirm the live device, session identity and absence of another active phone task.
- Verify every intended page or scroll state using a fresh screenshot and OCR.
- Collect warm request timing separately from OCR and screenshot timing.
- Compare at least five cycles per backend if stable. Do not infer production reliability from this sample alone.
- Make no adoption decision from a health endpoint or successful HTTP response alone.

## Initial state

Hi Hi was locked, with no scheduled task currently running. The only busy phone-related LFG session is this investigation.
After waking, it showed Home with an informational Apple account notification. Preserve that screen as before.png.
Dismiss only the notification. Make no account or authentication changes.
