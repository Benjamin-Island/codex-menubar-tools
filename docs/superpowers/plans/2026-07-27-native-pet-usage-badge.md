# Native Pet Usage Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the duplicate Pet Island with a Primary-usage badge that follows the visible Codex Desktop native Pet and opens a compact usage summary without moving the Pet.

**Architecture:** A metadata-only CoreGraphics locator discovers the native Pet window cluster, an adaptive tracker refreshes its anchor, and a main-actor controller owns two independent nonactivating panels for the badge and summary. Existing `DashboardStore` data drives SwiftUI presentation; a small preference object migrates the old Pet Island enabled state without deleting rollback data.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreGraphics, Combine, XCTest, Swift Package Manager

## Global Constraints

- Work only on `feature/native-pet-usage-badge`; do not push feature commits directly to `main`.
- Follow test-first order in every task: add the focused failing test, run it, implement the minimum behavior, rerun it, then run the broader suite.
- The badge value is strictly `usage.primary.remainingPercent`. Never fall back to Secondary.
- Read CoreGraphics window metadata only. Do not capture pixels, request Screen Recording or Accessibility permission, open a Codex debugging port, or use private IPC.
- Runtime matching must work without `kCGWindowName` and `kCGWindowOwnerName`; optional names are diagnostic evidence only.
- Hide the badge whenever Codex is absent, its native Pet is tucked away, or a unique matching Pet cluster cannot be established.
- Keep badge and summary in separate panels. Showing or closing the summary must never resize or reposition the badge panel.
- Do not modify any Codex-owned window.
- Preserve old `petIsland.*` defaults for rollback. Remove only the obsolete code and settings UI.
- Keep the existing release history entries in both READMEs unchanged.

---

## Task 1: Add badge preferences and one-time Pet Island migration

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePreferences.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePreferencesTests.swift`

- [ ] **Step 1: Write the failing migration and persistence tests**

Add tests covering a fresh install, migration from both old enabled states, persistence, and the one-time migration marker:

```swift
import XCTest
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgePreferencesTests: XCTestCase {
    func testFreshInstallEnablesBadge() {
        let defaults = makeDefaults()
        let preferences = PetUsageBadgePreferences(defaults: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: PetUsageBadgePreferences.migrationKey))
    }

    func testFirstLaunchCopiesLegacyEnabledStateWithoutDeletingLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "petIsland.enabled")

        let preferences = PetUsageBadgePreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "petIsland.enabled") as? Bool, false)
    }

    func testMigrationDoesNotOverwriteLaterBadgeChoice() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "petIsland.enabled")
        var preferences: PetUsageBadgePreferences? =
            PetUsageBadgePreferences(defaults: defaults)
        preferences?.isEnabled = false
        preferences = nil
        defaults.set(true, forKey: "petIsland.enabled")

        XCTAssertFalse(PetUsageBadgePreferences(defaults: defaults).isEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "PetUsageBadgePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
```

- [ ] **Step 2: Run the focused test and confirm the expected compile failure**

Run:

```bash
cd codex-menubar/macos/CodexMenuBar
swift test --filter PetUsageBadgePreferencesTests
```

Expected: compilation fails because `PetUsageBadgePreferences` does not exist.

- [ ] **Step 3: Implement the preference object**

Implement this public surface:

```swift
@MainActor
final class PetUsageBadgePreferences: ObservableObject {
    static let enabledKey = "petUsageBadge.enabled"
    static let migrationKey = "petUsageBadge.migratedFromPetIsland"

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    init(defaults: UserDefaults = .standard)
}
```

Initialization rules:

1. If `migrationKey` is true, load `enabledKey`, defaulting to `true`.
2. Otherwise, copy `petIsland.enabled` when that key exists; use `true` on a fresh install.
3. Persist `enabledKey` and set `migrationKey = true`.
4. Never remove or mutate any other `petIsland.*` key.

- [ ] **Step 4: Rerun the focused test**

Run:

```bash
swift test --filter PetUsageBadgePreferencesTests
```

Expected: all preference tests pass.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePreferences.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePreferencesTests.swift
git commit -m "feat: add native pet badge preferences"
```

---

## Task 2: Build a permission-free native Pet window locator

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/CodexPetWindowLocator.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/CodexPetWindowLocatorTests.swift`

- [ ] **Step 1: Define test fixtures and write failing structural-match tests**

Use value types so matching can be tested without real desktop windows:

```swift
struct QuartzWindowDescriptor: Equatable, Sendable {
    let id: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
    let layer: Int
    let alpha: Double
    let sharingState: Int
    let name: String?
}

struct CodexApplicationDescriptor: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let version: String?
}

struct PetWindowObservation: Equatable, Sendable {
    let anchorWindowID: CGWindowID
    let trackedWindowIDs: [CGWindowID]
    let anchorFrame: CGRect
    let obstacleFrames: [CGRect]
    let processIdentifier: pid_t
    let appVersion: String?
}

protocol CodexWindowMetadataProviding: Sendable {
    func runningApplications() async -> [CodexApplicationDescriptor]
    func visibleWindows() async -> [QuartzWindowDescriptor]
    func windows(withIDs ids: [CGWindowID]) async -> [QuartzWindowDescriptor]
}
```

Tests must prove:

- a matching layer-2 anchor plus spatially associated layer-3 windows from bundle ID `com.openai.codex` returns one observation;
- the same geometry matches when every `name` is `nil`;
- names cannot rescue invalid geometry;
- ordinary Codex layer-0 windows do not match;
- windows from another PID or bundle ID do not match;
- two equally valid clusters return `nil`;
- alpha-zero, off-screen, or non-shared candidates are rejected;
- targeted refresh succeeds while all tracked IDs still satisfy the profile and fails when the anchor disappears.

Build fixtures from the measured Codex 26.721 profile:

```swift
let anchor = window(id: 10, pid: 42, x: 900, y: 500,
                    width: 243, height: 253, layer: 2, name: nil)
let composition = window(id: 11, pid: 42, x: 700, y: 350,
                         width: 768, height: 912, layer: 3, name: nil)
let activity = window(id: 12, pid: 42, x: 830, y: 760,
                      width: 345, height: 54, layer: 3, name: nil)
```

- [ ] **Step 2: Run the focused tests and confirm the expected compile failure**

```bash
cd codex-menubar/macos/CodexMenuBar
swift test --filter CodexPetWindowLocatorTests
```

Expected: compilation fails because locator types do not exist.

- [ ] **Step 3: Implement the metadata provider**

Add `SystemCodexWindowMetadataProvider`:

- Resolve running applications with `NSWorkspace.shared.runningApplications`.
- Convert only applications whose bundle ID is `com.openai.codex`.
- Read full discovery metadata with `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`.
- Read tracked IDs with `CGWindowListCreateDescriptionFromArray`.
- Parse required keys defensively: number, owner PID, bounds, layer, alpha, and sharing state.
- Parse `kCGWindowName` only when present.
- Perform CoreGraphics dictionary generation off the main actor.

- [ ] **Step 4: Implement versioned structural matching**

Expose:

```swift
struct PetWindowMatchProfile: Equatable, Sendable {
    let supportedVersionPrefix: String
    let anchorLayer: Int
    let anchorWidthRange: ClosedRange<CGFloat>
    let anchorHeightRange: ClosedRange<CGFloat>
    let validatingLayer: Int
    let minimumValidatingWindowCount: Int
    let maximumAdjacencyDistance: CGFloat

    static let codex26_721 = PetWindowMatchProfile(
        supportedVersionPrefix: "26.721.",
        anchorLayer: 2,
        anchorWidthRange: 180...300,
        anchorHeightRange: 180...320,
        validatingLayer: 3,
        minimumValidatingWindowCount: 1,
        maximumAdjacencyDistance: 80
    )
}

actor CodexPetWindowLocator {
    init(
        provider: any CodexWindowMetadataProviding =
            SystemCodexWindowMetadataProvider(),
        profiles: [PetWindowMatchProfile] = [.codex26_721]
    )

    func discover() async -> PetWindowObservation?
    func refresh(_ previous: PetWindowObservation) async
        -> PetWindowObservation?
}
```

The profile must encode the reviewed constraints rather than exact pixel equality:

- one visible layer-2 anchor in the measured Pet-effect size range;
- at least one same-PID layer-3 composition/control/task window in the expected size range;
- spatial overlap or adjacency between anchor and validating layer-3 windows;
- obstacle frames include only nearby layer-3 control/task windows, not the large composition surface;
- exactly one valid cluster is required.

Keep optional-name checks as diagnostics and additional rejection evidence only. Do not make a missing or changed name fail a structurally valid cluster.

- [ ] **Step 5: Rerun focused tests and the complete package suite**

```bash
swift test --filter CodexPetWindowLocatorTests
swift test
```

Expected: locator tests and all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/CodexPetWindowLocator.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/CodexPetWindowLocatorTests.swift
git commit -m "feat: locate the Codex native pet window"
```

---

## Task 3: Implement coordinate conversion, placement, and UI state

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePlacement.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeState.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePlacementTests.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeStateTests.swift`

- [ ] **Step 1: Write failing coordinate and placement tests**

Cover:

- CoreGraphics top-origin to AppKit bottom-origin conversion on the primary display;
- displays to the left, above, and below the primary display, including negative origins;
- 48 × 28 badge candidates in right-bottom, left-bottom, right-middle, left-middle order;
- 8-point Pet gap and 4-point visible-frame margin;
- rejection of Pet, Activity Tray, voice-control, and task-hint intersections;
- stability preference for the candidate nearest the previous frame;
- `nil` when no candidate is safe;
- 306 × 66 summary placement without changing the badge frame;
- summary stays closed when no safe summary candidate exists.

Use the exact callable surface:

```swift
enum PetUsageBadgePlacement {
    static let badgeSize = CGSize(width: 48, height: 28)
    static let summarySize = CGSize(width: 306, height: 66)
    static let gap: CGFloat = 8
    static let edgeMargin: CGFloat = 4

    static func appKitFrame(
        from quartzFrame: CGRect,
        quartzScreenFrame: CGRect,
        appKitScreenFrame: CGRect
    ) -> CGRect

    static func badgeFrame(
        anchorFrame: CGRect,
        obstacleFrames: [CGRect],
        visibleFrame: CGRect,
        previousFrame: CGRect?
    ) -> CGRect?

    static func summaryFrame(
        badgeFrame: CGRect,
        anchorFrame: CGRect,
        obstacleFrames: [CGRect],
        visibleFrame: CGRect
    ) -> CGRect?
}
```

- [ ] **Step 2: Write failing state-reducer tests**

Use:

```swift
enum PetUsageBadgeVisibility: Equatable {
    case hidden
    case badge
    case summary
}

enum PetUsageBadgeEvent: Equatable {
    case anchorFound
    case anchorLost
    case badgeClicked(summaryCanFit: Bool)
    case outsideClicked
    case escapePressed
    case movementStarted
    case disabled
}
```

Test all confirmed transitions:

- hidden + anchor found → badge;
- badge + click with safe summary → summary;
- summary + badge click/outside/Esc/movement → badge;
- any visible state + anchor lost/disabled → hidden;
- badge + click without a safe summary remains badge.

- [ ] **Step 3: Run focused tests and confirm the expected compile failures**

```bash
swift test --filter PetUsageBadgePlacementTests
swift test --filter PetUsageBadgeStateTests
```

- [ ] **Step 4: Implement conversion, candidate scoring, and reducer**

Keep functions pure. Convert each window using the screen whose Quartz frame contains its center. Score safe badge candidates by:

1. containment within inset `visibleFrame`;
2. no intersection with the anchor or obstacles;
3. shortest distance from `previousFrame`;
4. declared candidate order as the deterministic tie-breaker.

Summary candidates expand away from the Pet/screen edge and must not intersect the badge, anchor, or obstacles.

- [ ] **Step 5: Run focused and full tests**

```bash
swift test --filter PetUsageBadgePlacementTests
swift test --filter PetUsageBadgeStateTests
swift test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgePlacement.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeState.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePlacementTests.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeStateTests.swift
git commit -m "feat: place usage panels beside the native pet"
```

---

## Task 4: Add adaptive tracking without scan overlap

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeTracker.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeTrackerTests.swift`

- [ ] **Step 1: Write failing tracker policy tests with a fake clock**

Define injectable boundaries:

```swift
protocol PetWindowLocating: Sendable {
    func discover() async -> PetWindowObservation?
    func refresh(_ previous: PetWindowObservation) async
        -> PetWindowObservation?
}

struct PetUsageBadgeTrackingUpdate: Equatable, Sendable {
    let observation: PetWindowObservation?
    let isMoving: Bool
}

@MainActor
protocol PetUsageBadgeTracking: AnyObject {
    var onUpdate: (@MainActor (PetUsageBadgeTrackingUpdate) -> Void)? { get set }
    func start()
    func stop()
}
```

Test with an injected sleeper/clock:

- disabled/stopped tracker schedules no scans;
- no Codex process is rechecked after 5 seconds;
- undiscovered Pet is rediscovered after 2 seconds;
- stable tracked windows refresh after 500 ms;
- movement changes cadence to 75 ms;
- 750 ms without frame changes returns to 500 ms;
- every 10 seconds triggers full discovery to refresh the cluster;
- failures back off 1, 2, then 5 seconds;
- success resets backoff;
- a slow locator never has two calls in flight;
- movement emits `isMoving = true`, loss emits `observation = nil`.

- [ ] **Step 2: Run focused tests and confirm failure**

```bash
cd codex-menubar/macos/CodexMenuBar
swift test --filter PetUsageBadgeTrackerTests
```

- [ ] **Step 3: Implement the tracker state machine**

Implement:

```swift
@MainActor
final class PetUsageBadgeTracker: PetUsageBadgeTracking {
    init(
        locator: any PetWindowLocating,
        codexIsRunning: @escaping @Sendable () async -> Bool,
        sleep: @escaping @Sendable (Duration) async throws -> Void =
            { try await Task.sleep(for: $0) }
    )

    var onUpdate: (@MainActor (PetUsageBadgeTrackingUpdate) -> Void)?
    func start()
    func stop()
}
```

Use one owned `Task`, sequentially await every locator call, and calculate the next deadline only after the current scan completes. Cancel and clear the task in `stop()`. A full validation replaces the tracked observation only when a unique cluster remains valid.

- [ ] **Step 4: Run tracker tests, concurrency diagnostics, and full tests**

```bash
swift test --filter PetUsageBadgeTrackerTests
swift test
```

Expected: no Swift 6 sendability errors or actor-isolation warnings; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeTracker.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeTrackerTests.swift
git commit -m "feat: track native pet movement adaptively"
```

---

## Task 5: Build Primary-only badge and compact summary views

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/PetUsageBadgeView.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePresentationTests.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`

- [ ] **Step 1: Write failing presentation tests**

Separate data formatting from SwiftUI layout:

```swift
struct PetUsageBadgePresentation: Equatable {
    let projectTitle: String
    let primaryText: String
    let secondaryText: String
    let runningText: String
    let primaryRemainingPercent: Int?

    static func make(
        snapshot: DashboardSnapshot,
        language: AppDisplayLanguage
    ) -> PetUsageBadgePresentation
}
```

Test:

- Primary 72 and Secondary 60 produce badge `72%`, summary Primary `72%`, Secondary `60%`;
- Primary missing and Secondary present still produces badge `--`;
- loading, empty, and failure usage produce `--`;
- project title prefers the first running session display description, then the first session, then localized no-active-task text;
- running count includes only `.running` sessions and localizes singular/plural/Chinese text;
- percentage color thresholds remain green above 30, orange at 11–30, red at 0–10, neutral for missing.

- [ ] **Step 2: Run the focused test and confirm failure**

```bash
cd codex-menubar/macos/CodexMenuBar
swift test --filter PetUsageBadgePresentationTests
```

- [ ] **Step 3: Implement presentation and views**

Create:

```swift
struct PetUsageBadgeView: View {
    @ObservedObject var store: DashboardStore
    let language: AppDisplayLanguage
    let onClick: () -> Void
}

struct PetUsageSummaryView: View {
    @ObservedObject var store: DashboardStore
    let language: AppDisplayLanguage
}
```

Requirements:

- badge has a fixed 48 × 28 layout and accessible label such as “Primary remaining 72 percent”;
- summary has a fixed 306 × 66 content layout;
- summary order is project, Primary, Secondary, running count;
- no task list, Today initial, Pet sprite, Pet catalog, or Pet controls;
- reuse the existing visual threshold semantics without depending on `PetIslandView`.

- [ ] **Step 4: Replace the legacy Pet smoke block**

In `DashboardViewSmokeTests.swift`, remove `testPetIslandHasFiniteLayoutWithAndWithoutPet()` and add finite-layout tests for both new views using:

```swift
NSHostingController(
    rootView: PetUsageBadgeView(
        store: store,
        language: .english,
        onClick: {}
    )
)
```

and `PetUsageSummaryView`. Assert fitting sizes are finite and match their fixed container sizes.

- [ ] **Step 5: Run focused and full tests**

```bash
swift test --filter PetUsageBadgePresentationTests
swift test --filter DashboardViewSmokeTests
swift test
```

Expected: all pass, including Primary-missing/Secondary-present behavior.

- [ ] **Step 6: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/PetUsageBadgeView.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgePresentationTests.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift
git commit -m "feat: add native pet usage badge views"
```

---

## Task 6: Add the two-panel controller and wire it into the app

**Files:**

- Create: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeController.swift`
- Create: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeControllerTests.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/StatusController.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/DashboardView.swift`
- Modify: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift`

- [ ] **Step 1: Write failing controller tests against injectable panels**

Introduce a minimal panel boundary:

```swift
@MainActor
protocol PetUsagePanel: AnyObject {
    var frame: CGRect { get }
    var isVisible: Bool { get }
    func setFrame(_ frame: CGRect, display: Bool)
    func orderFrontRegardless()
    func orderOut()
}
```

Tests must verify:

- enabling starts tracking; disabling stops tracking and hides both panels;
- no anchor hides both panels;
- anchor discovery converts coordinates, chooses placement, and shows only the badge;
- badge click shows the summary panel without changing the badge frame;
- second badge click, outside click, and Esc hide only the summary;
- movement hides summary before updating frames;
- anchor loss hides both;
- unsafe placement hides both; unsafe summary placement leaves badge visible;
- controller ignores stale updates after stop;
- controller never calls any operation on a Codex-owned window.

- [ ] **Step 2: Run controller tests and confirm failure**

```bash
cd codex-menubar/macos/CodexMenuBar
swift test --filter PetUsageBadgeControllerTests
```

- [ ] **Step 3: Implement panels and Esc behavior**

Implement a borderless `NSPanel` subclass:

```swift
final class PetUsageSummaryPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
```

Configure both panels with:

- `.borderless` and `.nonactivatingPanel`;
- transparent background, no shadow-changing resize behavior;
- `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`;
- an appropriate floating level consistent with the old Pet Island;
- no dragging and no activation of the menu bar app.

The summary panel may become key only while shown so `Esc` routes through `cancelOperation`. Do not install a global keyboard monitor.

- [ ] **Step 4: Implement the controller**

Expose:

```swift
@MainActor
final class PetUsageBadgeController {
    init(
        store: DashboardStore,
        preferences: PetUsageBadgePreferences,
        languagePreferences: AppLanguagePreferences,
        tracker: any PetUsageBadgeTracking,
        outsideClickEventSource: any OutsideClickEventSource =
            GlobalMouseDownEventSource(),
        screens: @escaping () -> [NSScreen] = { NSScreen.screens }
    )

    func start()
    func stop()
}
```

Subscribe to preferences and language changes, host the two SwiftUI views, and keep the badge panel frame unchanged across every summary transition. Start outside-click monitoring only while the summary is visible and stop it immediately when the summary closes.

- [ ] **Step 5: Wire the controller into `StatusController`**

Replace:

- `PetIslandPreferences`;
- `PetConfigurationMonitor`;
- `PetIslandController`;
- `ensurePetConfigurationMonitor()` and `reloadPetConfiguration()`.

With:

- `PetUsageBadgePreferences`;
- `CodexPetWindowLocator`;
- `PetUsageBadgeTracker`;
- `PetUsageBadgeController`.

Create and start the badge controller in `StatusController.start()`. Keep it alive for the controller lifetime and stop it during teardown if a teardown path exists. Do not change the existing menu-bar status item selection in this task; the new desktop badge itself remains Primary-only.

- [ ] **Step 6: Replace the dashboard Pet menu**

Change `DashboardView` to accept `PetUsageBadgePreferences?` and replace the custom-Pet picker with a single localized toggle:

```text
EN: Show Usage by Codex Pet
ZH: 在 Codex 宠物旁显示额度
```

Help text must explain that the badge appears only while the Codex native Pet is visible. Remove custom Pet selection, follow-local-Pet, and scale controls from the active UI.

- [ ] **Step 7: Run focused tests and full suite**

```bash
swift test --filter PetUsageBadgeControllerTests
swift test --filter DashboardViewSmokeTests
swift test
```

Expected: all pass; no Accessibility or Screen Recording usage-description keys are added.

- [ ] **Step 8: Commit**

```bash
git add codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetUsageBadgeController.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/StatusController.swift codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/DashboardView.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetUsageBadgeControllerTests.swift codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/DashboardViewSmokeTests.swift
git commit -m "feat: attach usage badge to the Codex pet"
```

---

## Task 7: Retire the duplicate Pet Island and document the replacement

**Files:**

- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetIslandController.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetIslandPreferences.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/PetConfigurationMonitor.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/CodexPetCatalog.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/PetIslandView.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/PetSpriteView.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Sources/CodexMenuBar/Views/PetDragCaptureView.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/CodexPetCatalogTests.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetConfigurationMonitorTests.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetIslandMigrationAcceptanceTests.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetIslandPlacementTests.swift`
- Delete: `codex-menubar/macos/CodexMenuBar/Tests/CodexMenuBarTests/PetIslandPreferencesTests.swift`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

- [ ] **Step 1: Prove the new system no longer references legacy Pet code**

Run before deletion:

```bash
rg -n "PetIsland|PetSpriteView|PetDragCaptureView|PetConfigurationMonitor|CodexPetCatalog" codex-menubar/macos/CodexMenuBar/Sources codex-menubar/macos/CodexMenuBar/Tests
```

Expected: matches are limited to the legacy files and legacy tests listed above. If active new files still refer to them, remove that dependency before continuing.

- [ ] **Step 2: Delete the legacy implementation and tests**

Delete only the listed source/test files. Do not delete `petIsland.*` values from `UserDefaults`, `~/.codex/pets`, or any user assets.

- [ ] **Step 3: Update English and Chinese README feature text**

Replace the current Pet Island section with the confirmed behavior:

- uses Codex Desktop’s native Pet rather than rendering a second Pet;
- shows a small Primary remaining percentage badge;
- click opens project, Primary, Secondary, and running-count summary;
- hides when Codex Pet is tucked away or cannot be identified;
- requires neither Accessibility nor Screen Recording permission.

Do not rewrite historical release entries that describe older versions.

- [ ] **Step 4: Run legacy-reference and permission checks**

```bash
rg -n "PetIsland|PetSpriteView|PetDragCaptureView|PetConfigurationMonitor|CodexPetCatalog" codex-menubar/macos/CodexMenuBar/Sources codex-menubar/macos/CodexMenuBar/Tests
rg -n "ScreenCapture|Screen Recording|Accessibility|AXIsProcessTrusted|CGWindowListCreateImage" codex-menubar/macos/CodexMenuBar README.md README.zh-CN.md
```

Expected:

- first command returns no source/test matches;
- second command contains documentation saying permissions are not required, but no permission request or image-capture implementation.

- [ ] **Step 5: Run the strict verification matrix**

```bash
cd codex-menubar/macos/CodexMenuBar
swift test
swift build -c release
cd ../../..
scripts/build-app.sh
codesign --verify --deep --strict dist/CodexMenuBar.app
git diff --check
git status --short
```

Expected:

- all Swift tests pass;
- release build succeeds;
- app bundle builds;
- strict code-signature verification exits 0;
- no whitespace errors;
- only intended tracked changes/build artifacts are present.

- [ ] **Step 6: Perform manual acceptance QA on macOS**

With Codex Desktop 26.721.41059:

1. Wake the native Pet: one native Pet and one `Primary%` badge appear.
2. Click badge: compact summary appears and the Pet/badge frames do not move.
3. Click badge again, click outside, and press Esc: each closes only the summary.
4. Drag/move the native Pet: summary closes and badge follows without jumping.
5. Open native Activity Tray/voice/task hint: badge selects a non-overlapping candidate or hides.
6. Tuck Away the native Pet: badge and summary hide.
7. Quit/relaunch Codex: badge hides, then returns after the native Pet returns.
8. Move Pet across displays and display edges: badge stays on the correct visible frame.
9. Remove Primary data while Secondary exists: badge shows `--`, never Secondary.
10. Toggle the dashboard setting off/on: tracking stops/hides, then resumes.
11. Confirm macOS shows no new Accessibility or Screen Recording permission prompt.

Record any Codex version/window profile observed during QA in locator diagnostics tests before broadening matcher tolerances.

- [ ] **Step 7: Commit cleanup and documentation**

```bash
git add -A codex-menubar/macos/CodexMenuBar README.md README.zh-CN.md
git commit -m "refactor: replace Pet Island with native pet badge"
```

---

## Task 8: Review and prepare the Pull Request

**Files:**

- Review all changes since `main`
- Update PR description only; no additional source file is required unless review finds a defect

- [ ] **Step 1: Inspect the complete branch diff**

```bash
git diff --stat main...HEAD
git diff --check main...HEAD
git status --short --branch
```

Verify the diff contains the design, implementation plan, new badge system, legacy deletion, tests, and bilingual docs only.

- [ ] **Step 2: Rerun final automated verification from a clean package build**

```bash
cd codex-menubar/macos/CodexMenuBar
swift package clean
swift test
swift build -c release
cd ../../..
scripts/build-app.sh
codesign --verify --deep --strict dist/CodexMenuBar.app
```

Expected: every command exits 0.

- [ ] **Step 3: Open a PR from the feature branch**

```bash
git push -u origin feature/native-pet-usage-badge
gh pr create --base main --head feature/native-pet-usage-badge --title "Replace Pet Island with a native Pet usage badge" --body "Replaces the duplicate Pet Island with a metadata-only Primary usage badge attached to the Codex native Pet. Includes safe-hide behavior, adaptive window tracking, migration tests, bilingual docs, and automated/manual verification results."
```

The PR description must include:

- why the duplicate Pet Island is removed;
- metadata-only matching and its no-new-permission guarantee;
- Primary-only badge semantics;
- safe-hide and supported Codex version/profile behavior;
- automated and manual test results;
- screenshots showing badge-only and compact-summary states;
- rollback note that old `petIsland.*` preferences remain intact.

- [ ] **Step 4: Stop for review**

Do not merge, delete the branch, publish a release, or remove build artifacts until the user explicitly requests those actions after reviewing the PR.
