# Decisions

Sideby should stay open to product ideas, but a few technical boundaries protect users and keep the app reviewable.

## Current Boundaries

- Use public macOS APIs only.
- Do not depend on private Mission Control or Spaces APIs.
- Context names are per shared Context, not per-display Space labels.
- Sideby does not infer private macOS Space indexes; capture and switching use public Previous/Next commands plus observable active-space changes.
- Context capture treats the shortest selected display Space sequence as the common Context count.
- Keep Space switching behind `ContextSwitchEngine` and `SpaceCommandExecutor`.
- Keep global input detection in system adapters such as `EventTapInputSource` and `GlobalShortcutInputSource`.
- Keep gesture interpretation in pure Swift domain logic under `SidebyCore`.
- Do not request Screen Recording for V1 Screen Switching.

## Current Distribution Baseline

- V1 targets direct distribution, not Mac App Store submission.
- The product bundle is App Sandbox off by default.
- The current bundle may include Apple Events automation entitlement for the public System Events command path.

Changing permission flow, sandboxing, event posting, global input capture, signing, or distribution strategy can affect user trust and release viability. Please open an issue before making those changes.
