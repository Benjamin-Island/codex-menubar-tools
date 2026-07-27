import AppKit
import XCTest
import CodexMenuBarCore
@testable import CodexMenuBar

@MainActor
final class PetUsageBadgeControllerTests: XCTestCase {
    func testEnableStartsTrackingAndDisableStopsAndHidesPanels() {
        let harness = makeHarness()

        harness.controller.start()
        XCTAssertEqual(harness.tracker.startCount, 1)

        harness.preferences.isEnabled = false

        XCTAssertEqual(harness.tracker.stopCount, 1)
        XCTAssertFalse(harness.badge.isVisible)
        XCTAssertFalse(harness.summary.isVisible)
    }

    func testAnchorDiscoveryShowsOnlyPlacedBadge() {
        let harness = makeHarness()
        harness.controller.start()

        harness.tracker.send(.init(observation: observation(), isMoving: false))

        XCTAssertTrue(harness.badge.isVisible)
        XCTAssertFalse(harness.summary.isVisible)
        XCTAssertEqual(
            harness.badge.frame,
            CGRect(x: 1_151, y: 147, width: 48, height: 28)
        )
    }

    func testSummaryDismissalsNeverChangeBadgeFrame() {
        let harness = makeHarness()
        harness.controller.start()
        harness.tracker.send(.init(observation: observation(), isMoving: false))
        let badgeFrame = harness.badge.frame

        harness.controller.toggleSummary()
        XCTAssertTrue(harness.summary.isVisible)
        XCTAssertEqual(harness.badge.frame, badgeFrame)

        harness.controller.toggleSummary()
        XCTAssertFalse(harness.summary.isVisible)
        XCTAssertEqual(harness.badge.frame, badgeFrame)

        harness.controller.toggleSummary()
        harness.outside.sendOutsideClick()
        XCTAssertFalse(harness.summary.isVisible)
        XCTAssertEqual(harness.badge.frame, badgeFrame)

        harness.controller.toggleSummary()
        harness.summary.sendEscape()
        XCTAssertFalse(harness.summary.isVisible)
        XCTAssertEqual(harness.badge.frame, badgeFrame)
    }

    func testMovementClosesSummaryBeforeMovingBadge() {
        let harness = makeHarness()
        harness.controller.start()
        harness.tracker.send(.init(observation: observation(), isMoving: false))
        harness.controller.toggleSummary()
        XCTAssertTrue(harness.summary.isVisible)

        harness.tracker.send(
            .init(observation: observation(x: 800), isMoving: true)
        )

        XCTAssertFalse(harness.summary.isVisible)
        XCTAssertTrue(harness.badge.isVisible)
        XCTAssertNotEqual(harness.badge.frame.origin.x, 1_151)
    }

    func testAnchorLossAndUnsafePlacementHideBothPanels() {
        let harness = makeHarness()
        harness.controller.start()
        harness.tracker.send(.init(observation: observation(), isMoving: false))
        harness.controller.toggleSummary()

        harness.tracker.send(.init(observation: nil, isMoving: false))

        XCTAssertFalse(harness.badge.isVisible)
        XCTAssertFalse(harness.summary.isVisible)

        let cramped = makeHarness(
            screens: [
                PetUsageScreenDescriptor(
                    quartzFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
                    appKitFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
                    visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 100)
                )
            ]
        )
        cramped.controller.start()
        cramped.tracker.send(
            .init(
                observation: observation(
                    x: 20,
                    y: 20,
                    width: 260,
                    height: 60
                ),
                isMoving: false
            )
        )
        XCTAssertFalse(cramped.badge.isVisible)
        XCTAssertFalse(cramped.summary.isVisible)
    }

    func testStoppedControllerIgnoresStaleTrackerUpdates() {
        let harness = makeHarness()
        harness.controller.start()
        harness.controller.stop()

        harness.tracker.send(.init(observation: observation(), isMoving: false))

        XCTAssertFalse(harness.badge.isVisible)
        XCTAssertFalse(harness.summary.isVisible)
    }

    private func makeHarness(
        screens: [PetUsageScreenDescriptor] = [
            PetUsageScreenDescriptor(
                quartzFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
            )
        ]
    ) -> Harness {
        let suite = "PetUsageBadgeControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = PetUsageBadgePreferences(defaults: defaults)
        let tracker = FakePetUsageBadgeTracker()
        let badge = FakePetUsagePanel()
        let summary = FakePetUsagePanel()
        let outside = FakeBadgeOutsideClickEventSource()
        let store = DashboardStore(
            snapshot: .loading(at: .distantPast),
            reader: { .loading(at: .distantPast) }
        )
        let controller = PetUsageBadgeController(
            store: store,
            preferences: preferences,
            languagePreferences: AppLanguagePreferences(defaults: defaults),
            tracker: tracker,
            outsideClickEventSource: outside,
            screenDescriptors: { screens },
            badgePanel: badge,
            summaryPanel: summary
        )
        return Harness(
            controller: controller,
            preferences: preferences,
            tracker: tracker,
            badge: badge,
            summary: summary,
            outside: outside
        )
    }

    private func observation(
        x: CGFloat = 900,
        y: CGFloat = 500,
        width: CGFloat = 243,
        height: CGFloat = 253
    ) -> PetWindowObservation {
        PetWindowObservation(
            anchorWindowID: 10,
            trackedWindowIDs: [10, 11],
            anchorFrame: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            obstacleFrames: [],
            processIdentifier: 42,
            appVersion: "26.721.41059"
        )
    }
}

@MainActor
private struct Harness {
    let controller: PetUsageBadgeController
    let preferences: PetUsageBadgePreferences
    let tracker: FakePetUsageBadgeTracker
    let badge: FakePetUsagePanel
    let summary: FakePetUsagePanel
    let outside: FakeBadgeOutsideClickEventSource
}

@MainActor
private final class FakePetUsageBadgeTracker: PetUsageBadgeTracking {
    var onUpdate: (@MainActor (PetUsageBadgeTrackingUpdate) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func send(_ update: PetUsageBadgeTrackingUpdate) {
        onUpdate?(update)
    }
}

@MainActor
private final class FakePetUsagePanel: PetUsagePanel {
    var contentViewController: NSViewController?
    var onEscape: (() -> Void)?
    private(set) var frame: CGRect = .zero
    private(set) var isVisible = false
    private(set) var setFrames: [CGRect] = []

    func setFrame(_ frame: CGRect, display: Bool) {
        self.frame = frame
        setFrames.append(frame)
    }

    func show(makeKey: Bool) {
        isVisible = true
    }

    func hide() {
        isVisible = false
    }

    func sendEscape() {
        onEscape?()
    }
}

@MainActor
private final class FakeBadgeOutsideClickEventSource: OutsideClickEventSource {
    private var handler: (@MainActor @Sendable () -> Void)?

    func start(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func sendOutsideClick() {
        handler?()
    }
}
