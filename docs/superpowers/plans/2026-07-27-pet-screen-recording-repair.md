# Pet Screen Recording Permission Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, confirmed in-app repair flow for stale Screen Recording permission records created by ad-hoc preview upgrades.

**Architecture:** Persist the last app version known to have Screen Recording access and any pending repair version. Keep Core Graphics permission checks, TCC reset execution, controller state, and SwiftUI confirmation in separate units. Execute `/usr/bin/tccutil` asynchronously with fixed arguments only after explicit user confirmation; tests inject fakes and never modify the real TCC database.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreGraphics, Foundation `Process`, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Never reset a privacy permission at launch or in the background.
- Require both a visible repair-button click and a confirmation alert.
- Execute `/usr/bin/tccutil` directly without a shell.
- The only allowed reset arguments are `reset ScreenCapture dev.benjamin.codex-menubar`.
- Never request administrator privileges.
- Tests must never execute the real TCC reset command.
- A reset or authorization failure must keep Pet tracking disabled.
- English and Simplified Chinese copy must not claim a user denial when Core Graphics only returned `false`.
- Continue to support macOS 14 and Apple Silicon preview packaging.

---

## File Structure

- Modify `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePreferences.swift`
  - Persist last authorized and pending repair app versions.
- Modify `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift`
  - Define repair reasons/states and own startup, enable, and repair transitions.
- Create `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/ScreenCapturePermissionResetter.swift`
  - Hold the immutable reset command and asynchronous `Process` adapter.
- Modify `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/DashboardView.swift`
  - Render repair actions, confirmation alert, disabled in-progress state, and localized messages.
- Modify `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePermissionControllerTests.swift`
  - Prove version classification and repair state transitions.
- Create `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/ScreenCapturePermissionResetterTests.swift`
  - Verify the exact immutable command and failure mapping without running `tccutil`.
- Modify `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeControllerTests.swift`
  - Prove tracking remains stopped in every repair state.
- Modify `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`
  - Prove repair UI visibility, copy, and finite layout.
- Modify `README.md` and `README.zh-CN.md`
  - Correct the outdated claim that the Pet badge does not need Screen Recording permission and document the repair flow.

---

### Task 1: Persist Authorization Evidence and Classify Startup

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePreferences.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift`
- Test: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePermissionControllerTests.swift`

**Interfaces:**
- Produces: `PetUsageBadgePreferences.lastAuthorizedAppVersion: String?`
- Produces: `PetUsageBadgePreferences.pendingPermissionRepairVersion: String?`
- Produces: `PetUsageBadgePermissionRepairReason`
- Produces: `PetUsageBadgePermissionStatus.repairRequired(reason:)`
- Consumes: existing `ScreenCapturePermissionProviding`

- [ ] **Step 1: Write failing startup and persistence tests**

Add tests with literal versions:

```swift
func testAuthorizedStartupRecordsCurrentVersionAndClearsPendingRepair() {
    let (preferences, defaults) = makePreferences(enabled: true)
    defaults.set(
        "0.3.10",
        forKey: PetUsageBadgePreferences.pendingPermissionRepairVersionKey
    )

    let controller = PetUsageBadgePermissionController(
        preferences: preferences,
        permissionProvider: FakeScreenCapturePermissionProvider(
            preflightResult: true,
            requestResult: false
        ),
        currentAppVersion: "0.3.11"
    )

    XCTAssertEqual(controller.status, .authorized)
    XCTAssertEqual(
        preferences.lastAuthorizedAppVersion,
        "0.3.11"
    )
    XCTAssertNil(preferences.pendingPermissionRepairVersion)
}

func testFailedPreflightAfterPreviouslyAuthorizedVersionRequiresRepair() {
    let (preferences, defaults) = makePreferences(enabled: true)
    defaults.set(
        "0.3.10",
        forKey: PetUsageBadgePreferences.lastAuthorizedAppVersionKey
    )

    let controller = PetUsageBadgePermissionController(
        preferences: preferences,
        permissionProvider: FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        ),
        currentAppVersion: "0.3.11"
    )

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(
        controller.status,
        .repairRequired(reason: .upgradeMismatch)
    )
    XCTAssertEqual(
        preferences.pendingPermissionRepairVersion,
        "0.3.11"
    )
}

func testPendingRepairSurvivesRelaunchInSameVersion() {
    let (preferences, defaults) = makePreferences(enabled: false)
    defaults.set(
        "0.3.11",
        forKey: PetUsageBadgePreferences.pendingPermissionRepairVersionKey
    )

    let controller = PetUsageBadgePermissionController(
        preferences: preferences,
        permissionProvider: FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        ),
        currentAppVersion: "0.3.11"
    )

    XCTAssertEqual(
        controller.status,
        .repairRequired(reason: .upgradeMismatch)
    )
}

func testMissingPermissionWithoutHistoryUsesOrdinaryRequiredState() {
    let (preferences, _) = makePreferences(enabled: false)

    let controller = PetUsageBadgePermissionController(
        preferences: preferences,
        permissionProvider: FakeScreenCapturePermissionProvider(
            preflightResult: false,
            requestResult: false
        ),
        currentAppVersion: "0.3.11"
    )

    XCTAssertEqual(controller.status, .permissionRequired)
    XCTAssertNil(preferences.pendingPermissionRepairVersion)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter PetUsageBadgePermissionControllerTests
```

Expected: compilation failures for the new preference keys, version properties,
initializer argument, repair reason, and repair status.

- [ ] **Step 3: Implement the minimal persistent properties**

Add fixed keys and computed properties:

```swift
static let lastAuthorizedAppVersionKey =
    "petUsageBadge.lastAuthorizedAppVersion"
static let pendingPermissionRepairVersionKey =
    "petUsageBadge.pendingPermissionRepairVersion"

var lastAuthorizedAppVersion: String? {
    get { defaults.string(forKey: Self.lastAuthorizedAppVersionKey) }
    set {
        if let newValue {
            defaults.set(
                newValue,
                forKey: Self.lastAuthorizedAppVersionKey
            )
        } else {
            defaults.removeObject(
                forKey: Self.lastAuthorizedAppVersionKey
            )
        }
    }
}

var pendingPermissionRepairVersion: String? {
    get { defaults.string(forKey: Self.pendingPermissionRepairVersionKey) }
    set {
        if let newValue {
            defaults.set(
                newValue,
                forKey: Self.pendingPermissionRepairVersionKey
            )
        } else {
            defaults.removeObject(
                forKey: Self.pendingPermissionRepairVersionKey
            )
        }
    }
}
```

Add exact state types:

```swift
enum PetUsageBadgePermissionRepairReason: Equatable {
    case upgradeMismatch
    case requestNotGranted
}

enum PetUsageBadgePermissionStatus: Equatable {
    case authorized
    case permissionRequired
    case repairRequired(reason: PetUsageBadgePermissionRepairReason)
    case repairing
    case repairFailed
    case restartRequired
}
```

Inject `currentAppVersion` with a production default from
`CFBundleShortVersionString`. During initialization:

```swift
if permissionProvider.preflight() {
    status = .authorized
    preferences.lastAuthorizedAppVersion = currentAppVersion
    preferences.pendingPermissionRepairVersion = nil
} else if preferences.pendingPermissionRepairVersion == currentAppVersion
    || preferences.lastAuthorizedAppVersion.map({ $0 != currentAppVersion })
        == true
{
    status = .repairRequired(reason: .upgradeMismatch)
    preferences.pendingPermissionRepairVersion = currentAppVersion
} else {
    status = .permissionRequired
}
```

Keep `isEnabled` false and persist false for every non-authorized startup.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same filtered test command.

Expected: all permission-controller startup tests pass.

- [ ] **Step 5: Run all permission and Pet controller tests**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter 'PetUsageBadge(PermissionController|Controller)Tests'
```

Expected: PASS with zero failures.

- [ ] **Step 6: Commit Task 1**

```bash
git add \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePreferences.swift \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift \
  codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePermissionControllerTests.swift
git commit -m "feat: detect stale Pet screen permission"
```

---

### Task 2: Add a Targeted Asynchronous TCC Resetter

**Files:**
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/ScreenCapturePermissionResetter.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/ScreenCapturePermissionResetterTests.swift`

**Interfaces:**
- Produces: `ScreenCapturePermissionResetCommand.codexMenuBar`
- Produces: `ScreenCapturePermissionResetError`
- Produces: `ScreenCapturePermissionResetting.reset() async`
- Produces: `SystemScreenCapturePermissionResetter`

- [ ] **Step 1: Write failing command-contract tests**

```swift
final class ScreenCapturePermissionResetterTests: XCTestCase {
    func testCodexMenuBarCommandTargetsOnlyItsScreenCaptureRecord() {
        let command = ScreenCapturePermissionResetCommand.codexMenuBar

        XCTAssertEqual(command.executableURL.path, "/usr/bin/tccutil")
        XCTAssertEqual(
            command.arguments,
            [
                "reset",
                "ScreenCapture",
                "dev.benjamin.codex-menubar"
            ]
        )
    }

    func testExitStatusMapsZeroToSuccessAndNonzeroToFailure() {
        XCTAssertEqual(
            ScreenCapturePermissionResetError.from(exitStatus: 0),
            nil
        )
        XCTAssertEqual(
            ScreenCapturePermissionResetError.from(exitStatus: 1),
            .nonzeroExit(1)
        )
    }
}
```

The production change these tests catch is widening the reset target, invoking
a shell, using the wrong bundle ID, or accepting a failed command.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter ScreenCapturePermissionResetterTests
```

Expected: compilation failure because the reset command and error types do not
exist.

- [ ] **Step 3: Implement the immutable command and result mapping**

```swift
struct ScreenCapturePermissionResetCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]

    static let codexMenuBar = Self(
        executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
        arguments: [
            "reset",
            "ScreenCapture",
            "dev.benjamin.codex-menubar"
        ]
    )
}

enum ScreenCapturePermissionResetError: Error, Equatable, Sendable {
    case launchFailed
    case nonzeroExit(Int32)

    static func from(exitStatus: Int32) -> Self? {
        exitStatus == 0 ? nil : .nonzeroExit(exitStatus)
    }
}

protocol ScreenCapturePermissionResetting: Sendable {
    func reset() async -> Result<Void, ScreenCapturePermissionResetError>
}
```

Implement `SystemScreenCapturePermissionResetter` as an actor. It creates
`Process`, assigns the immutable executable and arguments, and resumes a
checked continuation from the termination handler:

```swift
actor SystemScreenCapturePermissionResetter:
    ScreenCapturePermissionResetting
{
    private let command: ScreenCapturePermissionResetCommand

    init(
        command: ScreenCapturePermissionResetCommand = .codexMenuBar
    ) {
        self.command = command
    }

    func reset()
        async -> Result<Void, ScreenCapturePermissionResetError>
    {
        let command = command
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { completedProcess in
                if let error = ScreenCapturePermissionResetError.from(
                    exitStatus: completedProcess.terminationStatus
                ) {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(.launchFailed))
            }
        }
    }
}
```

Never invoke `/bin/zsh`, `/bin/bash`, `sh -c`, or user-controlled arguments.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same filtered test command.

Expected: both tests pass without changing Screen Recording permission.

- [ ] **Step 5: Build to validate Swift 6 concurrency**

Run:

```bash
swift build --package-path codex-menubar/macos/CodexMenuBar
```

Expected: build succeeds with no sendability or actor-isolation errors.

- [ ] **Step 6: Commit Task 2**

```bash
git add \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/ScreenCapturePermissionResetter.swift \
  codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/ScreenCapturePermissionResetterTests.swift
git commit -m "feat: add targeted screen permission resetter"
```

---

### Task 3: Implement the Explicit Repair State Machine

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePermissionControllerTests.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeControllerTests.swift`

**Interfaces:**
- Consumes: `ScreenCapturePermissionResetting.reset() async`
- Produces: `PetUsageBadgePermissionController.repairPermission() async`
- Produces: `PetUsageBadgePermissionController.canRepair: Bool`
- Produces: `PetUsageBadgePermissionController.isRepairing: Bool`

- [ ] **Step 1: Write failing ordinary-request compatibility tests**

Add:

```swift
func testRequestWithoutGrantActivatesFirstReleaseRepairPath() {
    let (preferences, _) = makePreferences(enabled: false)
    let controller = makeController(
        preferences: preferences,
        preflight: false,
        request: false,
        currentVersion: "0.3.11"
    )

    controller.setEnabled(true)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(
        controller.status,
        .repairRequired(reason: .requestNotGranted)
    )
    XCTAssertEqual(
        preferences.pendingPermissionRepairVersion,
        "0.3.11"
    )
    XCTAssertTrue(controller.canRepair)
}
```

Update the former denied-state test to expect neutral
`requestNotGranted` repair state.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter PetUsageBadgePermissionControllerTests
```

Expected: FAIL because the existing code still emits `.denied` and does not
persist pending repair.

- [ ] **Step 3: Implement the minimal ordinary-request transition**

On request success, record current authorization and clear pending repair. On
request failure:

```swift
status = .repairRequired(reason: .requestNotGranted)
isEnabled = false
preferences.isEnabled = false
preferences.pendingPermissionRepairVersion = currentAppVersion
```

Add `canRepair` for `.repairRequired` and `.repairFailed`, and `isRepairing`
for `.repairing`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same filtered command.

Expected: permission-controller tests pass.

- [ ] **Step 5: Write failing async repair tests**

Use an actor fake resetter that returns a configured result. Add:

```swift
func testSuccessfulResetAndGrantRequiresRestartAndClearsPending() async {
    let (preferences, defaults) = makePreferences(enabled: false)
    defaults.set(
        "0.3.11",
        forKey: PetUsageBadgePreferences.pendingPermissionRepairVersionKey
    )
    let controller = makeController(
        preferences: preferences,
        preflight: false,
        request: true,
        currentVersion: "0.3.11",
        resetResult: .success(())
    )

    await controller.repairPermission()

    XCTAssertEqual(controller.status, .restartRequired)
    XCTAssertTrue(controller.isEnabled)
    XCTAssertEqual(
        preferences.lastAuthorizedAppVersion,
        "0.3.11"
    )
    XCTAssertNil(preferences.pendingPermissionRepairVersion)
}

func testResetFailureKeepsTrackingOffAndRepairRetryAvailable() async {
    let (preferences, _) = makePreferences(enabled: false)
    let controller = makeController(
        preferences: preferences,
        preflight: false,
        request: true,
        currentVersion: "0.3.11",
        resetResult: .failure(.nonzeroExit(1))
    )

    await controller.repairPermission()

    XCTAssertEqual(controller.status, .repairFailed)
    XCTAssertFalse(controller.isEnabled)
    XCTAssertTrue(controller.canRepair)
    XCTAssertEqual(
        preferences.pendingPermissionRepairVersion,
        "0.3.11"
    )
}

func testResetSuccessWithoutGrantReturnsToNeutralRepairState() async {
    let (preferences, _) = makePreferences(enabled: false)
    let controller = makeController(
        preferences: preferences,
        preflight: false,
        request: false,
        currentVersion: "0.3.11",
        resetResult: .success(())
    )

    await controller.repairPermission()

    XCTAssertEqual(
        controller.status,
        .repairRequired(reason: .requestNotGranted)
    )
    XCTAssertFalse(controller.isEnabled)
}
```

Add a suspended actor fake and a test that starts two repair tasks:

```swift
func testSecondRepairAttemptIsIgnoredWhileFirstIsSuspended() async {
    let (preferences, _) = makePreferences(enabled: false)
    let resetter = SuspendedScreenCapturePermissionResetter()
    let controller = makeController(
        preferences: preferences,
        preflight: false,
        request: true,
        currentVersion: "0.3.11",
        resetter: resetter
    )
    controller.setEnabled(true)

    let first = Task { await controller.repairPermission() }
    await Task.yield()
    let second = Task { await controller.repairPermission() }
    await Task.yield()

    let count = await resetter.resetCount()
    XCTAssertEqual(count, 1)
    XCTAssertEqual(controller.status, .repairing)

    await resetter.finish(with: .success(()))
    await first.value
    await second.value
}
```

The fake stores one checked continuation, increments its private count in
`reset()`, exposes `resetCount()`, and resumes exactly once from
`finish(with:)`.

- [ ] **Step 6: Run focused tests and verify RED**

Run the permission-controller filter.

Expected: compilation failures for resetter injection and
`repairPermission()`.

- [ ] **Step 7: Implement the minimal async repair flow**

Inject:

```swift
private let permissionResetter: any ScreenCapturePermissionResetting
```

Implement:

```swift
func repairPermission() async {
    guard canRepair, !isRepairing else { return }

    status = .repairing
    isEnabled = false
    preferences.isEnabled = false
    preferences.pendingPermissionRepairVersion = currentAppVersion

    switch await permissionResetter.reset() {
    case .failure:
        status = .repairFailed
    case .success:
        if permissionProvider.request() {
            status = .restartRequired
            isEnabled = true
            preferences.isEnabled = true
            preferences.lastAuthorizedAppVersion = currentAppVersion
            preferences.pendingPermissionRepairVersion = nil
        } else {
            status = .repairRequired(reason: .requestNotGranted)
        }
    }
}
```

The `guard canRepair, !isRepairing` check occurs before assigning `.repairing`.
No second caller can pass that guard while the first call is suspended. Never
enable tracking in `.repairing`, `.repairFailed`, or `.repairRequired`.

- [ ] **Step 8: Run focused and dependent tests**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter 'PetUsageBadge(PermissionController|Controller)Tests'
```

Expected: all repair transitions pass and Pet tracking remains stopped outside
`.authorized`.

- [ ] **Step 9: Commit Task 3**

```bash
git add \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift \
  codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePermissionControllerTests.swift \
  codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeControllerTests.swift
git commit -m "feat: repair stale Pet screen permission"
```

---

### Task 4: Add Localized Repair UI and Confirmation

**Files:**
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/DashboardView.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`

**Interfaces:**
- Consumes: `canRepair`, `isRepairing`, and `repairPermission()`
- Produces: localized status, action, confirmation title/message, confirm, and cancel copy

- [ ] **Step 1: Write failing presentation and visibility tests**

Add literal copy assertions:

```swift
func testUpgradeMismatchPresentationExplainsReauthorization() {
    XCTAssertEqual(
        PetUsageBadgePermissionPresentation.message(
            for: .repairRequired(reason: .upgradeMismatch),
            language: .english
        ),
        "App update requires Screen Recording re-authorization"
    )
    XCTAssertEqual(
        PetUsageBadgePermissionPresentation.message(
            for: .repairRequired(reason: .upgradeMismatch),
            language: .simplifiedChinese
        ),
        "App 更新后需要重新授权“屏幕录制”"
    )
}

func testRepairConfirmationCopyStatesTheExactScope() {
    XCTAssertEqual(
        PetUsageBadgePermissionPresentation.repairActionTitle(
            language: .english
        ),
        "Reset and Re-authorize"
    )
    XCTAssertEqual(
        PetUsageBadgePermissionPresentation.repairConfirmationMessage(
            language: .english
        ),
        "This clears only Codex Menu Bar’s Screen Recording permission record. macOS will ask for permission again."
    )
}
```

Extend the dashboard harness with `currentAppVersion`,
`lastAuthorizedAppVersion`, `pendingPermissionRepairVersion`, and an injected
resetter. Host `DashboardView` in a repair-required state and locate the action
by its literal title:

```swift
func testRepairRequiredShowsEnabledRepairAction() {
    let harness = makeSettingsHarness(
        initiallyEnabled: false,
        preflightResult: false,
        requestResult: false,
        currentAppVersion: "0.3.11",
        lastAuthorizedAppVersion: "0.3.10"
    )

    let button = firstDescendant(
        of: NSButton.self,
        in: harness.hostingController.view,
        where: { $0.title == "Reset and Re-authorize" }
    )

    XCTAssertNotNil(button)
    XCTAssertTrue(button?.isEnabled == true)
    XCTAssertTrue(
        harness.hostingController.view.fittingSize.width.isFinite
    )
    XCTAssertTrue(
        harness.hostingController.view.fittingSize.height.isFinite
    )
}
```

Add an async smoke test with a suspended resetter:

```swift
func testRepairingDisablesRepairAction() async {
    let resetter = SuspendedDashboardPermissionResetter()
    let harness = makeSettingsHarness(
        initiallyEnabled: false,
        preflightResult: false,
        requestResult: false,
        currentAppVersion: "0.3.11",
        lastAuthorizedAppVersion: "0.3.10",
        resetter: resetter
    )

    let repair = Task {
        await harness.permissionController.repairPermission()
    }
    await resetter.waitUntilResetStarts()
    harness.hostingController.view.layoutSubtreeIfNeeded()

    let button = firstDescendant(
        of: NSButton.self,
        in: harness.hostingController.view,
        where: { $0.title == "Reset and Re-authorize" }
    )
    XCTAssertNotNil(button)
    XCTAssertFalse(button?.isEnabled ?? true)
    XCTAssertTrue(
        harness.hostingController.view.fittingSize.width.isFinite
    )
    XCTAssertTrue(
        harness.hostingController.view.fittingSize.height.isFinite
    )

    await resetter.finish(with: .failure(.nonzeroExit(1)))
    await repair.value
}
```

`SuspendedDashboardPermissionResetter.waitUntilResetStarts()` resumes only
after its `reset()` method has stored the completion continuation. Resume the
fake before the test returns so no task or continuation leaks. Overload the
existing `firstDescendant` helper with a predicate and apply that predicate to
each matching `NSView`.

- [ ] **Step 2: Run smoke tests and verify RED**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter DashboardViewSmokeTests
```

Expected: compilation failures for new presentation helpers/states and a
missing repair button.

- [ ] **Step 3: Add minimal localized presentation**

Add exact English and Simplified Chinese copy for:

- upgrade re-authorization;
- permission not granted;
- repairing;
- reset failure;
- reset action;
- confirmation title and message;
- confirm and cancel buttons.

Use neutral orange for required/repairing/restart states and red only for
`.repairFailed`.

- [ ] **Step 4: Add the repair button and confirmation alert**

In `PetUsageBadgePermissionMessage`:

```swift
@State private var isShowingRepairConfirmation = false
```

Render a bordered repair button only when `canRepair`. The button changes only
local alert state. Attach an alert with Cancel and an explicitly labeled reset
action. The confirmed action starts:

```swift
Task {
    await permissionController.repairPermission()
}
```

Disable the toggle and repair action while `isRepairing`; do not call
`repairPermission()` from `onAppear`, initialization, or background tasks.

- [ ] **Step 5: Run smoke tests and verify GREEN**

Run the Dashboard smoke-test filter.

Expected: all localized and layout tests pass.

- [ ] **Step 6: Run all Pet tests**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar \
  --filter PetUsage
```

Expected: all Pet permission, controller, presentation, placement, state, and
tracker tests pass.

- [ ] **Step 7: Commit Task 4**

```bash
git add \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePermissionController.swift \
  codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/DashboardView.swift \
  codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift
git commit -m "feat: guide Pet permission repair"
```

---

### Task 5: Correct Documentation and Verify the Complete Change

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`

**Interfaces:**
- Consumes: completed permission repair behavior
- Produces: accurate public permission and preview-upgrade documentation

- [ ] **Step 1: Correct the English permission description**

Replace the claim that Screen Recording is not required with:

```markdown
Detection uses read-only window metadata from the local Codex Desktop process.
It does not read pet artwork or Codex configuration and does not require
Accessibility permission. macOS classifies access to other apps' window
metadata as Screen Recording, so this optional badge requires Screen Recording
permission. Ad-hoc preview updates can require re-authorization; the dashboard
offers an explicit, confirmed repair action when that happens.
```

- [ ] **Step 2: Correct the Chinese permission description**

Use:

```markdown
检测过程只读取本机 Codex Desktop 进程的窗口元数据，不读取宠物素材或 Codex
配置，也不需要“辅助功能”权限。macOS 将读取其他 App 窗口元数据归入“屏幕录制”
权限，因此这个可选徽标需要“屏幕录制”权限。临时签名的预览版升级后可能需要重新
授权；遇到这种情况时，仪表盘会提供需要用户确认的权限修复操作。
```

- [ ] **Step 3: Verify documentation and working-tree hygiene**

Run:

```bash
git diff --check
rg -n \
  "does not require Accessibility or Screen Recording|不需要.“辅助功能”.或.“屏幕录制”" \
  README.md README.zh-CN.md
```

Expected: `git diff --check` exits 0 and the obsolete claims produce no matches.

- [ ] **Step 4: Run the complete Swift test suite**

Run:

```bash
swift test --package-path codex-menubar/macos/CodexMenuBar
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Run a release build**

Run:

```bash
swift build --package-path codex-menubar/macos/CodexMenuBar -c release
```

Expected: exit 0 with a successful production build.

- [ ] **Step 6: Review final diff against the design**

Run:

```bash
git diff main...HEAD --stat
git diff main...HEAD
git status --short --branch
```

Confirm:

- no automatic reset path exists;
- reset arguments are exact and immutable;
- confirmation is required;
- every failure keeps tracking disabled;
- history persists across relaunch;
- no test invokes real `tccutil`;
- README permission claims are accurate.

- [ ] **Step 7: Commit Task 5**

```bash
git add README.md README.zh-CN.md
git commit -m "docs: explain Pet screen permission repair"
```

- [ ] **Step 8: Optional manual TCC verification gate**

Do not run this automatically. Ask the user for a fresh explicit confirmation
before any manual scenario that resets the real Screen Recording record. If
approved, package a disposable ad-hoc build, confirm the alert, exercise the
repair action, verify the system prompt and restart state, and then report the
exact local TCC state changed.
