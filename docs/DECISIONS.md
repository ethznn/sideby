# Decisions

Sideby should stay open to product ideas, but a few technical boundaries protect users and keep the app reviewable.

## Current Boundaries

- Prefer public macOS APIs, but allow the current read-only SkyLight layout query used by Context Capture, live Context matching, and Align Displays.
- Keep private-API use isolated behind `SpaceLayoutReading`/`SLSSpaceLayoutReader`; do not spread SkyLight symbols through product code.
- If the SkyLight layout query is unavailable, fall back to safer behavior instead of guessing.
- If a SkyLight result contains malformed or mirrored-display entries, keep valid display layouts and ignore only the invalid entries; if no valid display layout remains, fall back.
- Context names are per shared Context, not per-display Space labels.
- Sideby may read private Space IDs transiently to derive per-display indexes, but it must not persist those IDs or expose them as user-facing data.
- Context Capture derives Context count from the largest selected display Space sequence, and may store per-display Space indexes so a display can be absent from a Context in the middle of the captured set.
- Displays without an independent Space layout, such as mirrored displays, are not treated as captured Context members during instant capture.
- Context matrix display row order is a UI preference only; it must not change captured Space indexes or switching semantics.
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

## Public Documentation Hygiene

- Keep durable product decisions, architecture, and reviewed design specifications in the repository when they help contributors understand Sideby.
- Do not track agent-generated implementation plans, local brainstorming artifacts, raw research logs, or machine-specific experiment output.
- Public examples must use synthetic placeholders for display UUIDs, stable hardware identifiers, private Space IDs, window IDs, app bundle IDs, usernames, and local filesystem paths.
- Store local research artifacts only in ignored locations. Promote a result to public documentation by rewriting it as a durable, sanitized decision or design.
- CI must reject tracked internal-plan and raw-research paths as well as obvious machine-specific identifiers in public Markdown files.

Changing permission flow, sandboxing, event posting, global input capture, signing, or distribution strategy can affect user trust and release viability. Please open an issue before making those changes.
