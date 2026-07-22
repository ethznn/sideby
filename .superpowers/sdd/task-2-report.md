# Task 2 Report — Carbon press/release input events

## Implemented behavior

- Added `ContextKeyboardShortcutInputEvent`, a public `Equatable`, `Sendable` event enum with `.pressed(ContextKeyboardCommand)` and `.released(ContextKeyboardCommand)` cases.
- Updated the input source's primary `handler:` API to deliver those events.
- A press emits only when its binding ID is newly inserted into `activeIDs`; repeated Carbon press events for an already-active ID are suppressed.
- A release emits only when it removes an active binding ID; stale or unmatched releases are ignored.
- `stop()` continues to clear active IDs, so a restart accepts the first subsequent press.
- Retained a command-only convenience initializer as a compatibility bridge for existing callers; it forwards pressed commands only. The event-based `handler:` initializer is the API for press/release lifecycle consumers.

## Tests

The lifecycle suite now verifies:

1. first press emits `.pressed(command)`;
2. repeated press before release is suppressed;
3. an active binding's release emits `.released(command)`;
4. a second press after release emits again;
5. an unmatched release is ignored; and
6. the comma/period catalog bindings register at IDs 11/12 and emit their catalog commands.

TDD RED was observed before implementation: the new lifecycle tests could not find `ContextKeyboardShortcutInputEvent`, demonstrating that the required public event API did not exist. After adding the event type and lifecycle dispatch, the targeted test suite passed.

## Verification and review

- `swift test --filter GlobalContextKeyboardShortcutInputSourceTests` — passed: 13 tests, 0 failures.
- `git diff --check` — passed.
- Reviewed press/release state transitions: repeats do not emit a second press, releases cannot emit without an active press, and each registered ID maintains independent state.
- Carbon signature validation, main-thread callback dispatch, catalog-driven registration, partial-failure reporting, and cleanup behavior were not changed.

## Note

The current Core catalog contains twelve bindings (positions 1–10 plus comma and period), despite the task brief's reference to eleven. The source still registers every catalog binding independently, and the tests assert all twelve registrations.
