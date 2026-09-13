# Decisions

Sideby should stay open to product ideas, but a few technical boundaries protect users and keep the app reviewable.

## Current Boundaries

- Prefer public macOS APIs, but allow the current read-only SkyLight layout query used by Context Capture, live Context matching, and Align Displays.
- Keep private-API use in system adapters: layout reads use `SpaceLayoutReading`/`SLSSpaceLayoutReader`, and desktop-content suggestions use `SpaceNameSuggestionProviding`. Do not spread SkyLight symbols through product UI code.
- If the SkyLight layout query is unavailable, fall back to safer behavior instead of guessing.
- If a SkyLight result contains malformed or mirrored-display entries, keep valid display layouts and ignore only the invalid entries; if no valid display layout remains, fall back.
- Launch, reconnection, and desktop refresh establish a per-process connection baseline from live observations. Refresh reconciles surviving desktop identities with saved assignments; unreadable or invalid assignments require recovery. No private Space identifiers or derived identity fingerprints are persisted.
- Named transitions verify the expected layout before each command and after movement. A completion from an older workspace configuration cannot publish success or advance the first-work guide.
- Display choices include disconnected displays. Prefer the display UUID when available; legacy migrations must be unambiguous and must not merge stored identities or discard offline assignments.
- The normal menu shows an editable workspace matrix and closes after a verified workspace move. Independent retained Settings and onboarding windows share the same application model and verified switching pipeline. First-work success requires verified visits to an origin, another workspace, and the origin again.
- UI navigation preferences store only the last Settings pane and onboarding stage. Permission preparation, guide dismissal, and verified round-trip completion remain separate. Replay must not reapply initial enablement or fabricate success; assignment confirmation never automatically repeats a move.
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
- CI must reject tracked internal-plan and raw-research paths as well as obvious machine-specific identifiers in public Markdown, HTML, and documentation JSON files.

Changing permission flow, sandboxing, event posting, global input capture, signing, or distribution strategy can affect user trust and release viability. Please open an issue before making those changes.
