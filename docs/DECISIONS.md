# Decisions

Sideby should stay open to product ideas, but a few technical boundaries protect users and keep the app reviewable.

## Current Boundaries

- Prefer public macOS APIs, but allow the current read-only SkyLight layout query used by Context Capture, live Context matching, and Align Displays.
- Keep private-API use isolated behind `SpaceLayoutReading`/`SLSSpaceLayoutReader`; do not spread SkyLight symbols through product code.
- If the SkyLight layout query is unavailable or malformed, fall back to safer behavior instead of guessing.
- Context names are per shared Context, not per-display Space labels.
- Sideby may read private Space IDs transiently to derive per-display indexes, but it must not persist those IDs or expose them as user-facing data.
- Context Capture derives the common Context count from the shortest selected display Space sequence.
- Keep Space switching behind `ContextSwitchEngine` and `SpaceCommandExecutor`.
- Keep Space layout reads behind `SpaceLayoutReading`; keep per-step acknowledgement behind `SpaceLayoutStepAcknowledger`.
- Keep global input detection in system adapters such as `EventTapInputSource` and `GlobalShortcutInputSource`.
- Keep gesture interpretation in pure Swift domain logic under `SidebyCore`.
- Do not request Screen Recording for Screen Switching, Context Capture, or Align Displays.

## Current Distribution Baseline

- V1 targets direct distribution, not Mac App Store submission.
- The product bundle is App Sandbox off by default.
- The current bundle may include Apple Events automation entitlement for the public System Events command path.
- The current read-only SkyLight dependency is incompatible with a conservative Mac App Store posture; changing that direction needs an explicit release-strategy decision.

Changing permission flow, sandboxing, event posting, global input capture, signing, or distribution strategy can affect user trust and release viability. Please open an issue before making those changes.
