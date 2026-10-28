# Space Anchor Probe — original experiment disabled

This independent App Sandbox experiment investigated using public AppKit window
APIs to identify and navigate desktop Spaces. It is **not safe for interactive
use on a working desktop**. The entry point and build script are disabled.

A manual multi-display trial produced desktop switching followed by unusable
keyboard input and inconsistent desktop behavior. The user had to power the Mac
off and back on to recover, not merely restart the experiment. Do not rerun to
reproduce this unchanged experiment on the user's working session.

## Confirmed implementation defects

- Transparent anchor windows can become key/main windows. The switch path calls
  `NSApp.activate()` and `makeKeyAndOrderFront` without returning input focus to
  a usable application window afterward.
- The verifier checks anchor Space membership, but does not verify keyboard
  delivery, the focused application, or the desktop's complete visible state.
  Its `switch-verified` log event is **not evidence of a usable transition**.
- Two sequential per-display activations are not an atomic workspace change.
- Recovery from a partial transition was not implemented.

The focus defect can explain lost input. The full cause of the reported desktop
inconsistency has not been established. Reboot restoration was not validated.
No conclusion about hardware damage follows from these logs.

The original source is retained for static investigation. Prefer a separate
test environment for interactive work. The user subsequently explicitly
authorized a bounded investigation on the current Mac; this does not establish
the old experiment's safety. Require observable focus checks and an independent
exit mechanism. Production Sideby code and distribution settings were not
changed by this experiment.

The probe stores its manifest and event log only in its own App Sandbox
Application Support directory. Do not publish raw manifests or session logs.

## Offline checks

Run `bash scripts/space_anchor_probe/check_offline.sh` from the repository.
It type-checks the AppKit sources without executing them, then runs the Foundation
data-model checks and the supervisor's non-GUI subprocess checks. It creates no
windows, posts no input events, does not change Spaces, and does not build or
install an app bundle.

Passing these checks does not validate live transitions or explain the incident.
The original `switch-verified` records establish only anchor membership; they
must not be counted as successful input/desktop tests.

## Separate visible-window harness

`build_visible_trial.sh` builds a distinct sandboxed `SpaceTransitionTrial.app`
and a read-only public-API observer. This is not the disabled original app.
The trial creates one ordinary visible window and permits at most one return
transition per process after a second window is placed on another Space.
No restoration, transparent windows, nonactivating panels, private API imports,
or synthesized input are implemented in the trial app or observer.
New windows use the public `moveToActiveSpace` collection option only during
initial ordering, then remove it before the activation trial. Without explicit
placement, this inactive app was observed creating even a new A window on a
previous desktop. Verify actual membership; do not assume creation means the
window is on the current desktop.

`prepare-B-when-away` requires A to be on the current desktop when armed, then
waits for A to be off the current desktop continuously for two seconds before
creating B. It expires after 120 seconds. This avoids sending an unguarded B
creation request during a user's desktop transition. B's membership still needs
to be checked before the separate, single-use `jump-A-once` request.

`supervise_trial.py` owns the exact app and observer subprocesses. It terminates
the trial on a missing/stale heartbeat or a fixed lifetime limit. Its self-test
checks timeout and normal-exit paths and verifies that an unrelated child stays
alive. This does not guarantee recovery from a WindowServer fault.

The observer records `activeSpaceDidChangeNotification`, physical display IDs,
and the frontmost PID. The trial separately records its own windows'
`isOnActiveSpace`, key/main status, and input/click results. **No current Space
ID is obtained.** A physical display ID must never be interpreted as a Space ID.

Initial live preflight verified one ordinary visible window, a delivered key
event and a coordinate click. The first run recorded no Space changes. In the
second run the app recorded one Space notification with A still on the active
Space, while the external observer recorded none; no controlled A-to-B baseline
was established. The observer has since been changed from a bare RunLoop to an
NSApplication lifecycle with prohibited activation. A subsequent user-driven
baseline recorded three matching notifications in the app and observer, within
11 milliseconds of each other. This validates notification delivery for that
baseline, not completeness of macOS internal state. Do not treat an observer
count of zero as proof that no Space changed. Two preparation attempts were
stopped before any return-transition request: one created B while A was current,
and another exposed the inactive-window placement behavior described above.
Neither the public-API return transition nor the later stages have passed live
verification yet. Raw session evidence remains local and untracked.

After explicit initial placement was added, A was visible on the current desktop
and a synthetic key event changed its text field, confirmed through accessibility
readback. No further manual desktop change was observed during the armed
120-second preparation period, so the app exited normally on preparation timeout.
All app and observer processes from these attempts were confirmed exited. Two
physical displays remained connected throughout; only one display was targeted.
This is not a completed single-display hardware isolation test.

### Subsequent supervised findings

- Selecting an existing app window through Orca can provide a normal desktop
  transition. Mission Control desktop selection is not required for every setup.
- One background `activate()` / `makeKeyAndOrderFront` request produced no app
  activation or Space change and exited normally on the five-second limit. A and
  B were on different physical displays at request time, so this was not a valid
  same-display transition trial. It is not evidence of a reproduced system hang.
- The new harness now pins an explicit physical display, supplies screen-relative
  coordinates to the screen-taking NSWindow initializer, records frame/screen
  changes, and requires A-away/B-current on the same target display continuously
  for two seconds. It rechecks that condition immediately before switching.
- In a subsequent setup, B was initially on the intended physical display, then
  moved to the other display about 93 ms after its creation log. `isOnActiveSpace`
  stayed true. The new preparation check stopped the app before any switch.
  The active app's public full-screen presentation flag was false during this
  observation; no fullscreen-causation conclusion follows.
- With the user's explicit authorization, Magnet was normally terminated for a
  comparison and restarted afterward. The same B relocation occurred with Magnet
  stopped (about 94 ms after creation, versus 93 ms with it running), at the same
  final frame. Magnet is therefore not required to reproduce this placement issue.
- The original disabled probe already validates actual versus expected display
  in `validate`. Do not claim the original entirely lacked a display check, or
  that this new harness's missing check explains the original reboot incident.
  All six original `switch-verified` records report true for every recorded
  `onExpectedDisplay` value at those instants. The new visible-window relocation
  therefore cannot, by itself, be equated with the original incident.

The public observer now also records the active app's system presentation flags.
These flags describe the active app, not every Space on every display. A visible
Return-to-A button permits a separate foreground-initiated comparison; that path
has not yet passed live verification. `--display-id` selects a physical display,
never a desktop Space identifier. No private Space API has been added.

Further comparisons also failed before any return transition:

| Condition | Observed relocation | Result |
| --- | --- | --- |
| Pointer clicked onto the target display | B changed displays after about 93 ms | Same preparation failure |
| Remove `moveToActiveSpace` after 500 ms | A changed displays after about 90 ms, while the option was still set | Initial preparation rejected |

The Stage Manager `GloballyEnabled` preference was read as false; it was not
modified or used as a product API. The delayed removal is an optional diagnostic
variant (`--placement-delay-ms 500`); the default remains immediate removal.
No conclusion about WindowServer's internal cause or the original reboot follows
from these comparisons. The report in the ignored local build directory retains
the measured outcomes. All trial app/observer processes were confirmed stopped,
and Magnet was confirmed running again.

## Staged interactive investigation (later stages not implemented)

Use a spare Mac with no active work. A disposable macOS VM can test some AppKit
behavior, but a VM pass cannot clear the physical multi-display graphics path.
The environment and limits must be selected before starting an interactive run.

Each stage needs a manually initiated, single transition. Do not automate an
A/B loop. Record an idle baseline first and stop at the first input, menu-bar,
display, or recovery failure; do not proceed to the next stage after a failure.

1. **One display, visible ordinary window, no control panel.** Establish whether
   activating an ordinary window on another Space completes normally. Explicitly
   observe application activation and restore focus to a visible usable window
   on the destination Space. Verify actual typing and clicking there, app
   switching, Mission Control, and that the displayed windows match the Space.
2. **One display, progressively approach the anchor configuration, no panel.**
   In separate trials, remove the border, make the window transparent at the same
   size, then reduce it to 1x1. Preserve the focus checks and recovery mechanism.
3. **One display, add the nonactivating control panel.** Change only the panel
   configuration. Check input before, during, and after its involvement.
4. **Two displays.** First change just one display, then investigate sequential
   changes on both. Record each display separately and verify both remain usable.

A future harness must expire automatically and be supervised by a separate
process that can terminate only that exact probe process if its heartbeat stops
or the trial times out. This limits a stuck app's lifetime; it does **not** promise
to recover WindowServer or prevent a forced reboot. Do not restart Dock or
WindowServer, synthesize keyboard shortcuts, or activate another Space as an
automatic recovery action. Keep a manual recovery path available before starting.

Record stage, monotonic timestamps, activation/key-window notifications, Space
membership, and explicit manual input results. Collect bounded local system logs
before and after the trial. Membership alone is never the final success signal.
Keep captured identifiers and raw logs local and untracked.
