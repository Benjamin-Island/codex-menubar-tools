# Pet Screen Recording Permission Repair Design

Date: 2026-07-27

## Context

Codex Menu Bar locates the Codex Desktop Pet by reading other-process
window metadata through Core Graphics. macOS protects that access with
the Screen Recording TCC permission.

Preview releases are currently ad-hoc signed. An ad-hoc app's designated
requirement is its binary CDHash, so every changed release has a different
code identity. macOS System Settings can continue to show the bundle ID as
enabled while TCC rejects the new binary because the saved requirement
belongs to the previous release.

The current controller maps every failed
`CGRequestScreenCaptureAccess()` call to "permission was denied." That
message is inaccurate for a stale code requirement and gives the user no
way to repair it from the app.

## Goals

- Never reset a privacy permission silently.
- Offer an in-app repair action when an ad-hoc upgrade invalidates a
  previously working Screen Recording grant.
- Require an explicit button click and a second confirmation before
  changing the TCC record.
- Reset only the Screen Recording record for
  `dev.benjamin.codex-menubar`.
- Immediately request Screen Recording access again after a successful
  reset and clearly communicate whether a restart is required.
- Persist enough evidence to distinguish future upgrade invalidation from
  an ordinary missing permission.
- Cover the first release of this feature, where older versions did not
  persist authorization history.

## Non-goals

- Automatically granting Screen Recording access. macOS still requires
  the user to approve the system request.
- Resetting permissions at application launch.
- Resetting permissions for any other application or TCC service.
- Replacing stable Developer ID signing. Stable signing remains the
  long-term solution for retaining grants across releases.
- Notarizing the preview build as part of this change.

## Persistent State

`PetUsageBadgePreferences` will add:

- `lastAuthorizedAppVersion: String?`: the most recent app version for
  which preflight or a system request succeeded.
- `pendingPermissionRepairVersion: String?`: the app version that has an
  unresolved repair flow.

Using the last authorized version is more precise than separately storing
a last launched version and a Boolean. If the current version differs
from the last authorized version and preflight fails, the previous grant
worked for another binary version and repair is appropriate.

`pendingPermissionRepairVersion` keeps the repair action visible across
relaunches until authorization succeeds. It also supports the one-time
compatibility path for users upgrading from versions that did not record
authorization history.

## Permission States

The controller will expose these user-visible states:

- `authorized`: permission is currently usable.
- `permissionRequired`: permission is absent with no evidence of an
  upgrade mismatch.
- `repairRequired(reason)`: an upgrade mismatch is known or a
  user-initiated request returned without a grant. The reason is either
  `upgradeMismatch` or `requestNotGranted`, allowing accurate UI text
  without changing the available repair action.
- `repairing`: the targeted TCC reset and follow-up request are in
  progress.
- `repairFailed`: the reset executable could not be launched or returned
  a nonzero status. Raw command output is not shown in the UI.
- `restartRequired`: the system request succeeded and the app must be
  restarted before tracking begins.

The existing "permission was denied" state will no longer be used for a
plain Boolean `false` result because the public Core Graphics API does not
distinguish an explicit denial from a stale code requirement.

## Startup Flow

1. Read the current bundle version and persisted permission history.
2. Run `CGPreflightScreenCaptureAccess()`.
3. If preflight succeeds:
   - enter `authorized`;
   - store the current version as `lastAuthorizedAppVersion`;
   - clear `pendingPermissionRepairVersion`;
   - preserve the user's enabled preference.
4. If preflight fails and either:
   - `pendingPermissionRepairVersion` equals the current version, or
   - `lastAuthorizedAppVersion` exists and differs from the current
     version,
   enter `repairRequired(reason: .upgradeMismatch)`.
5. Otherwise enter `permissionRequired`.
6. A failed startup preflight never runs `tccutil` and never presents a
   system prompt automatically.

## Ordinary Enable Flow

When the user turns on "Show Usage by Codex Pet":

1. Re-run preflight to handle permission changes made while the app was
   open.
2. If it succeeds, enable tracking and record authorization for the
   current version.
3. Otherwise call `CGRequestScreenCaptureAccess()`.
4. If the request succeeds, persist the enabled preference, record the
   current authorized version, and enter `restartRequired`.
5. If it returns without a grant, keep tracking disabled, persist
   `pendingPermissionRepairVersion`, and enter
   `repairRequired(reason: .requestNotGranted)`.

Step 5 is the compatibility rule for the first release of this feature.
It does not reset anything automatically. It only exposes the repair
action after the user has already tried to enable the feature.

## Explicit Repair Flow

The permission message row will show a localized "Reset and Re-authorize"
button in `repairRequired` and `repairFailed`.

1. Clicking the button opens a confirmation alert.
2. The alert explains that only Codex Menu Bar's Screen Recording record
   will be cleared and that macOS will ask for permission again.
3. Cancel closes the alert without changing state.
4. Confirm starts an asynchronous repair operation and enters
   `repairing`. The toggle and repair button remain disabled while it is
   running.
5. The resetter launches `/usr/bin/tccutil` directly, without a shell,
   with the exact arguments:

   ```text
   reset ScreenCapture dev.benjamin.codex-menubar
   ```

6. A successful zero exit status is followed immediately by
   `CGRequestScreenCaptureAccess()`.
7. If the request succeeds, enter `restartRequired`, enable and persist
   the feature, record the current authorized version, and clear the
   pending repair marker.
8. If the user does not grant access, return to
   `repairRequired(reason: .requestNotGranted)`, keep the feature off, and
   show neutral wording that permission was not granted.
9. If `tccutil` cannot launch or exits nonzero, enter `repairFailed`, keep
   the feature off, retain the pending marker, and offer retry.

## Component Boundaries

### `ScreenCapturePermissionProviding`

Continues to wrap Core Graphics preflight and request calls so controller
state transitions remain deterministic in tests.

### `ScreenCapturePermissionResetting`

A new asynchronous protocol with one targeted reset operation. The
production implementation owns `Process`, the fixed executable path, the
fixed service, and the fixed bundle identifier. A pure command
configuration value exposes those fixed fields for unit verification.
Tests use a fake resetter and never touch the real TCC database.

### `PetUsageBadgePermissionController`

Owns the state machine, version comparison, persistence updates, and the
sequence from reset to request. It does not construct shell commands and
does not own confirmation presentation.

### `PetUsageBadgePermissionMessage`

Owns the repair button and confirmation alert. It delegates the confirmed
operation to the controller and renders localized status text.

## Safety Properties

- No launch-time or background reset.
- No shell invocation or user-controlled command arguments.
- No administrator privileges.
- The command targets one service and one bundle identifier.
- Cancellation has no side effects.
- Concurrent repairs are rejected while `repairing`.
- Unit and smoke tests never execute `/usr/bin/tccutil`.
- Command failures do not enable tracking or erase the pending repair
  state.

## Error Messages

English and Simplified Chinese presentations will distinguish:

- permission required;
- upgrade requires re-authorization;
- repairing;
- reset failed and can be retried;
- permission was not granted after reset;
- restart required.

The UI will not claim the user denied permission when Core Graphics only
returned `false`.

## Test Strategy

Controller tests will cover:

- first install with missing permission;
- existing valid authorization;
- prior authorized version plus current failed preflight;
- pending repair surviving relaunch;
- ordinary request success;
- ordinary request failure activating the compatibility repair path;
- confirmed reset success followed by request success;
- reset success followed by request failure;
- reset launch failure and nonzero exit;
- duplicate repair attempts while already repairing;
- persistence updates and pending-marker cleanup.

Resetter tests will cover command construction and exit-status mapping
without modifying the real Screen Recording permission.

SwiftUI smoke tests will cover:

- repair button visibility;
- localized labels;
- confirmation alert content;
- repairing and failed layouts;
- existing authorized, required, and restart states.

Verification will include the full Swift test suite, a release build,
`git diff --check`, and a manual ad-hoc upgrade scenario using a disposable
local build. Any real TCC reset during manual verification requires a
separate explicit user confirmation.

## Release Note

The release note must state that this is a repair flow for ad-hoc preview
updates. It reduces manual Terminal work but does not replace stable
Developer ID signing.
